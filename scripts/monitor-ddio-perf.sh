#!/bin/bash
#
# Monitor DDIO miss/hit metrics using perf during Pktgen execution
# Output: pktgen-perf-ddio.log in CSV format with 1-second sampling
#

# Configuration
SOCKET=0
# Socket 0 (NUMA node0): CPUs with even numbers (hyperthreading pairs)
# System: 2 sockets, 8 cores per socket, 2 threads per core
CORES="0,2,4,6,8,10,12,14,16,18,20,22,24,26,28,30"  # Socket 0 cores
INTERVAL=1000  # 1 second in milliseconds
OUTPUT_FILE="pktgen-perf-ddio.log"
RAW_OUTPUT="/tmp/pktgen-perf-ddio-raw.log"

# DDIO-related events
EVENTS="llc_misses.pcie_read,llc_misses.pcie_write,llc_references.pcie_read,llc_references.pcie_write"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -d DURATION    Duration in seconds (default: run until Ctrl+C)"
    echo "  -s SOCKET      Socket to monitor: 0 or 1 (default: 0)"
    echo "  -c CORES       Core list (default: auto-detect based on socket)"
    echo "  -o OUTPUT      Output file (default: pktgen-perf-ddio.log)"
    echo "  -p PID         Attach to specific process PID"
    echo ""
    echo "System info:"
    echo "  Socket 0 (NUMA node0): CPUs 0,2,4,6,8,10,12,14,16,18,20,22,24,26,28,30"
    echo "  Socket 1 (NUMA node1): CPUs 1,3,5,7,9,11,13,15,17,19,21,23,25,27,29,31"
    echo ""
    echo "Examples:"
    echo "  $0                          # Monitor socket 0"
    echo "  $0 -s 1                     # Monitor socket 1"
    echo "  $0 -d 60                    # Run for 60 seconds"
    echo "  $0 -p \$(pgrep pktgen)       # Attach to running pktgen"
    exit 1
}

# Parse arguments
DURATION=""
PID=""
CORES_OVERRIDE=""
while getopts "d:s:c:o:p:h" opt; do
    case $opt in
        d) DURATION=$OPTARG ;;
        s) SOCKET=$OPTARG ;;
        c) CORES_OVERRIDE=$OPTARG ;;
        o) OUTPUT_FILE=$OPTARG ;;
        p) PID=$OPTARG ;;
        h) usage ;;
        *) usage ;;
    esac
done

# Auto-detect cores based on socket if not overridden
if [ -n "$CORES_OVERRIDE" ]; then
    CORES=$CORES_OVERRIDE
else
    if [ "$SOCKET" -eq 0 ]; then
        CORES="0,2,4,6,8,10,12,14,16,18,20,22,24,26,28,30"
    elif [ "$SOCKET" -eq 1 ]; then
        CORES="1,3,5,7,9,11,13,15,17,19,21,23,25,27,29,31"
    else
        echo -e "${RED}ERROR: Invalid socket $SOCKET. Use 0 or 1.${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}=== DDIO Monitoring with Perf ===${NC}"
echo "Socket: $SOCKET"
echo "Cores: $CORES"
echo "Interval: ${INTERVAL}ms (1 second)"
echo "Output: $OUTPUT_FILE"
if [ -n "$PID" ]; then
    echo "Attaching to PID: $PID"
fi
if [ -n "$DURATION" ]; then
    echo "Duration: ${DURATION}s"
fi
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}ERROR: This script must be run as root (for perf access)${NC}"
    echo "Please run: sudo $0"
    exit 1
fi

# Check if perf is available
if ! command -v perf &> /dev/null; then
    echo -e "${RED}ERROR: perf command not found${NC}"
    exit 1
fi

# Build perf command
# Note: perf stat outputs to stderr, so we need to redirect 2> instead of -o
if [ -n "$PID" ]; then
    # Attach to existing process
    echo -e "${YELLOW}Starting perf monitoring (attached to PID $PID)...${NC}"
    echo "Press Ctrl+C to stop"
    echo ""

    if [ -n "$DURATION" ]; then
        timeout $DURATION perf stat -e $EVENTS -I $INTERVAL -x ',' -p $PID 2> $RAW_OUTPUT
    else
        perf stat -e $EVENTS -I $INTERVAL -x ',' -p $PID 2> $RAW_OUTPUT &
        PERF_PID=$!
    fi
else
    # System-wide monitoring
    echo -e "${YELLOW}Starting perf monitoring (system-wide on cores $CORES)...${NC}"
    echo "Press Ctrl+C to stop"
    echo ""

    if [ -n "$DURATION" ]; then
        timeout $DURATION perf stat -e $EVENTS -I $INTERVAL -x ',' -a -C $CORES -- sleep $DURATION 2> $RAW_OUTPUT
    else
        perf stat -e $EVENTS -I $INTERVAL -x ',' -a -C $CORES 2> $RAW_OUTPUT &
        PERF_PID=$!
    fi
fi

# Cleanup flag to prevent multiple executions
CLEANUP_DONE=0

# Cleanup function
cleanup() {
    # Prevent multiple executions
    if [ $CLEANUP_DONE -eq 1 ]; then
        return 0
    fi
    CLEANUP_DONE=1

    echo ""
    echo -e "${YELLOW}Stopping perf monitoring...${NC}"
    if [ -n "$PERF_PID" ] && kill -0 $PERF_PID 2>/dev/null; then
        kill $PERF_PID 2>/dev/null
        wait $PERF_PID 2>/dev/null
    fi

    # Give perf a moment to flush output
    sleep 0.5

    # Process raw output to CSV
    if [ -f "$RAW_OUTPUT" ]; then
        echo -e "${GREEN}Processing results to CSV format...${NC}"

        # Create CSV with header
        echo "timestamp_sec,pcie_read_misses,pcie_write_misses,pcie_read_refs,pcie_write_refs,ddio_misses,pcie_miss_rate" > "$OUTPUT_FILE"

        # Parse perf output
        # CSV Format: timestamp,value,unit,event,runtime,percentage,,
        awk -F',' '
        BEGIN {
            prev_ts = 0;
            read_miss = 0; write_miss = 0; read_ref = 0; write_ref = 0;
            sample_count = 0;
        }
        {
            # Extract timestamp and event name
            ts = $1;
            value = $2;
            event = $4;

            # Round timestamp to nearest second for grouping
            ts_sec = int(ts + 0.5);

            # If new timestamp group, print previous sample
            if (prev_ts > 0 && ts_sec != prev_ts) {
                total_miss = read_miss + write_miss;
                total_ref = read_ref + write_ref;
                miss_rate = (total_ref > 0) ? (total_miss * 100.0 / total_ref) : 0;
                printf "%.3f,%d,%d,%d,%d,%d,%.2f\n", prev_ts, read_miss, write_miss, read_ref, write_ref, total_miss, miss_rate;
                sample_count++;
                read_miss = 0; write_miss = 0; read_ref = 0; write_ref = 0;
            }

            prev_ts = ts_sec;

            # Accumulate values for this timestamp
            if (event ~ /llc_misses.pcie_read/) {
                read_miss += value;
            } else if (event ~ /llc_misses.pcie_write/) {
                write_miss += value;
            } else if (event ~ /llc_references.pcie_read/) {
                read_ref += value;
            } else if (event ~ /llc_references.pcie_write/) {
                write_ref += value;
            }
        }
        END {
            # Print last sample
            if (prev_ts > 0) {
                total_miss = read_miss + write_miss;
                total_ref = read_ref + write_ref;
                miss_rate = (total_ref > 0) ? (total_miss * 100.0 / total_ref) : 0;
                printf "%.3f,%d,%d,%d,%d,%d,%.2f\n", prev_ts, read_miss, write_miss, read_ref, write_ref, total_miss, miss_rate;
                sample_count++;
            }
            print "# Total samples: " sample_count > "/dev/stderr"
        }
        ' "$RAW_OUTPUT" >> "$OUTPUT_FILE"

        # Show summary
        SAMPLE_COUNT=$(tail -n +2 "$OUTPUT_FILE" | wc -l)
        echo ""
        echo -e "${GREEN}=== Monitoring Complete ===${NC}"
        echo "Samples collected: $SAMPLE_COUNT"
        echo "Output saved to: $OUTPUT_FILE"
        echo ""
        echo "All samples (CSV format):"
        cat "$OUTPUT_FILE"

        # Cleanup raw file
        rm -f "$RAW_OUTPUT"
    else
        echo -e "${RED}ERROR: No perf output generated${NC}"
        exit 1
    fi
}

# Set trap for cleanup
trap cleanup EXIT INT TERM

# If no duration specified, wait for user interrupt
if [ -z "$DURATION" ] && [ -n "$PERF_PID" ]; then
    wait $PERF_PID
fi

# Cleanup will be called via trap
