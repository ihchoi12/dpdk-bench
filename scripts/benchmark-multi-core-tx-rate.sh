#!/usr/bin/env bash
# Multi-core TX Rate Benchmark Script with Retry Logic
# This script runs pktgen with different core configurations (1-15 cores)
# and measures TX rate for each setup. It includes retry logic for SEGFAULT errors.

# Source common header for DPDK scripts
source "$(dirname "${BASH_SOURCE[0]}")/common-header.sh"

PKTGEN_BIN="${PKTGEN_BIN:-${REPO_ROOT}/Pktgen-DPDK/build/app/pktgen}"

# Original config values from pktgen.config as template
MEMCH="${PKTGEN_MEMCH:--n 4}"
PCI_ADDR="${PKTGEN_PCI_ADDR:-0000:31:00.1,txqs_min_inline=0,txq_mpw_en=1,txq_inline_mpw=256}"
FILE_PREFIX="${PKTGEN_FILE_PREFIX:-pktgen1}"
PROC_TYPE="${PKTGEN_PROC_TYPE:---proc-type auto}"
APP_ARGS="${PKTGEN_APP_ARGS:--P -T}"

# Script file to execute  
SCRIPT_FILE="${REPO_ROOT}/scripts/measure-tx-rate.lua"

# Generate timestamp and output file name
TIMESTAMP=$(date +"%y%m%d-%H%M%S")
EXPERIMENT_DESC="multi-core-tx"
OUTPUT_FILE="${REPO_ROOT}/results/${TIMESTAMP}-${EXPERIMENT_DESC}.txt"

# Ensure results directory exists
mkdir -p "${REPO_ROOT}/results"

# Check if script file exists
if [ ! -f "$SCRIPT_FILE" ]; then
    echo "Error: Script file not found: $SCRIPT_FILE"
    exit 1
fi

# Ensure pktgen is built
check_binary "$PKTGEN_BIN" "pktgen"

echo ">> Starting multi-core TX rate benchmark with retry logic (1-15 cores)"
echo "   Output file: ${OUTPUT_FILE}"
echo ""

# Initialize output file
echo "# Multi-core TX Rate Benchmark Results with Retry Logic" > "$OUTPUT_FILE"
echo "# Format: setup|TX_rate_in_Mpps" >> "$OUTPUT_FILE"
echo "# Experiment: ${EXPERIMENT_DESC}" >> "$OUTPUT_FILE"
echo "# Generated on: $(date)" >> "$OUTPUT_FILE"
echo "# Timestamp: ${TIMESTAMP}" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Function to run a single core configuration test
run_core_test() {
    local cores=$1
    local attempt=$2
    
    # Configure core range and port mapping
    if [ $cores -eq 1 ]; then
        LCORES="-l 0-1"
        PORTMAP="[1].0"
    else
        LCORES="-l 0-$cores"
        PORTMAP="[1-$cores].0"
    fi
    
    # Build the setup string for output
    SETUP_STRING="$LCORES $MEMCH $PROC_TYPE --file-prefix '$FILE_PREFIX' --allow='$PCI_ADDR' -- $APP_ARGS -m '$PORTMAP' -f 'scripts/measure-tx-rate.lua'"
    
    if [ $attempt -gt 1 ]; then
        echo "   Attempt $attempt for $cores core(s)"
    fi
    echo "   Setup: $SETUP_STRING"
    
    # Convert script to relative path from Pktgen-DPDK directory
    SCRIPT_REL_PATH=$(realpath --relative-to="${REPO_ROOT}/Pktgen-DPDK" "${SCRIPT_FILE}")
    
    # Change to Pktgen-DPDK directory
    cd "${REPO_ROOT}/Pktgen-DPDK"
    
    # Run pktgen and capture output
    echo "   Running pktgen..."
    
    # Create a temporary file to capture the output
    TEMP_OUTPUT=$(mktemp)
    
    # Run pktgen in background and capture PID
    sudo bash -lc "LD_LIBRARY_PATH='${LD_LIBRARY_PATH}' \
      PKG_CONFIG_PATH='${PKG_CONFIG_PATH}' \
      exec '${PKTGEN_BIN}' \
      ${LCORES} ${MEMCH} ${PROC_TYPE} --file-prefix '${FILE_PREFIX}' --allow='${PCI_ADDR}' \
      -- ${APP_ARGS} -m '${PORTMAP}' -f '${SCRIPT_REL_PATH}'" > "$TEMP_OUTPUT" 2>&1 &
    
    PKTGEN_PID=$!
    
    # Wait for pktgen to complete, but kill it after 20 seconds if it doesn't exit
    wait_time=0
    max_wait=20
    PKTGEN_EXIT_CODE=0
    
    while [ $wait_time -lt $max_wait ]; do
        if ! kill -0 $PKTGEN_PID 2>/dev/null; then
            # Process has already terminated
            break
        fi
        sleep 1
        wait_time=$((wait_time + 1))
    done
    
    # If process is still running, force kill it
    if kill -0 $PKTGEN_PID 2>/dev/null; then
        echo "   Warning: pktgen didn't exit after ${max_wait}s, force killing..."
        sudo pkill -P $PKTGEN_PID 2>/dev/null || true
        sudo kill -9 $PKTGEN_PID 2>/dev/null || true
        sleep 2
        PKTGEN_EXIT_CODE=143  # SIGTERM exit code
    else
        # Try to get the exit code if process finished naturally
        wait $PKTGEN_PID 2>/dev/null || PKTGEN_EXIT_CODE=0
    fi
    
    # Check for segfault or other errors
    local has_segfault=false
    local has_error=false
    
    if [ -f "$TEMP_OUTPUT" ]; then
        if grep -q "Segment Fault\|Segmentation fault\|segfault" "$TEMP_OUTPUT" 2>/dev/null; then
            has_segfault=true
        fi
    fi
    
    if [ $PKTGEN_EXIT_CODE -ne 0 ] && [ $PKTGEN_EXIT_CODE -ne 143 ] && [ "$has_segfault" = false ]; then
        has_error=true
    fi
    
    # Extract TX rate if no major errors
    TX_RATE=""
    if [ "$has_segfault" = false ] && [ "$has_error" = false ] && [ -f "$TEMP_OUTPUT" ] && [ -s "$TEMP_OUTPUT" ]; then
        set +e
        TX_RATE=$(grep "Average TX Rate:" "$TEMP_OUTPUT" 2>/dev/null | sed -n 's/.*Average TX Rate: \([0-9.]*\) Mpps.*/\1/p' 2>/dev/null || echo "")
        set -e
    fi
    
    # Clean up temp file
    rm -f "$TEMP_OUTPUT"
    
    # Return status: 0=success, 1=segfault/retry, 2=permanent error
    if [ "$has_segfault" = true ]; then
        echo "   Segmentation fault detected, will retry..."
        return 1
    elif [ "$has_error" = true ]; then
        echo "   Permanent error (exit code: $PKTGEN_EXIT_CODE)"
        return 2
    elif [ -n "$TX_RATE" ]; then
        echo "   TX Rate: ${TX_RATE} Mpps"
        echo "$SETUP_STRING|$TX_RATE" >> "$OUTPUT_FILE"
        return 0
    else
        echo "   Could not extract TX rate, will retry..."
        return 1
    fi
}

# Loop through core configurations: 13 to 15 cores with retry logic (testing problematic cores)
for cores in {13..15}; do
    echo "=== Testing with $cores core(s) ==="
    
    # Retry logic: up to 3 attempts for each configuration
    max_retries=3
    attempt=1
    success=false
    
    while [ $attempt -le $max_retries ] && [ "$success" = false ]; do
        # Clean up any lingering DPDK processes and shared memory more thoroughly
        sudo pkill -f pktgen 2>/dev/null || true
        sudo pkill -f dpdk 2>/dev/null || true
        sudo rm -f /dev/hugepages/rtemap_* 2>/dev/null || true
        sudo rm -f /var/run/dpdk/rte/config 2>/dev/null || true
        sudo rm -rf /var/run/dpdk/pktgen1/* 2>/dev/null || true
        sudo rm -f /tmp/.rte_config 2>/dev/null || true
        sleep 2
        
        # Run the test (handle return code manually to avoid set -e exit)
        result=0
        run_core_test $cores $attempt || result=$?
        
        case $result in
            0)  # Success
                success=true
                ;;
            1)  # Segfault or temporary error, retry
                echo "   Attempt $attempt failed, retrying..."
                attempt=$((attempt + 1))
                if [ $attempt -le $max_retries ]; then
                    echo "   Waiting 5 seconds before retry..."
                    sleep 5
                fi
                ;;
            2)  # Permanent error, don't retry
                echo "   Permanent error detected, skipping retries"
                # Build setup string for error logging
                if [ $cores -eq 1 ]; then
                    LCORES="-l 0-1"
                    PORTMAP="[1].0"
                else
                    LCORES="-l 0-$cores"
                    PORTMAP="[1-$cores].0"
                fi
                SETUP_STRING="$LCORES $MEMCH $PROC_TYPE --file-prefix '$FILE_PREFIX' --allow='$PCI_ADDR' -- $APP_ARGS -m '$PORTMAP' -f 'scripts/measure-tx-rate.lua'"
                echo "$SETUP_STRING|PERMANENT_ERROR" >> "$OUTPUT_FILE"
                success=true  # Stop retrying
                ;;
        esac
    done
    
    if [ "$success" = false ]; then
        echo "   Failed after $max_retries attempts, marking as failed"
        # Build setup string for failure logging
        if [ $cores -eq 1 ]; then
            LCORES="-l 0-1"
            PORTMAP="[1].0"
        else
            LCORES="-l 0-$cores"
            PORTMAP="[1-$cores].0"
        fi
        SETUP_STRING="$LCORES $MEMCH $PROC_TYPE --file-prefix '$FILE_PREFIX' --allow='$PCI_ADDR' -- $APP_ARGS -m '$PORTMAP' -f 'scripts/measure-tx-rate.lua'"
        echo "$SETUP_STRING|FAILED_AFTER_RETRIES" >> "$OUTPUT_FILE"
    fi
    
    echo ""
    
    # Longer delay between different core configurations
    echo "   Waiting 5 seconds for resource cleanup..."
    sleep 5
done

echo "=== Benchmark completed ==="
echo "Results saved to: $OUTPUT_FILE"
echo ""
echo "Summary of results:"
cat "$OUTPUT_FILE"