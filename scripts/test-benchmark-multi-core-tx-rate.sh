#!/usr/bin/env bash
# Test version of multi-core TX Rate Benchmark Script
# This script tests only 1-2 cores to verify the functionality

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
EXPERIMENT_DESC="test-multi-core"
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

echo ">> Starting test multi-core TX rate benchmark (1-2 cores only)"
echo "   Output file: ${OUTPUT_FILE}"
echo ""

# Clear output file
echo "# Test Multi-core TX Rate Benchmark Results" > "$OUTPUT_FILE"
echo "# Format: setup|TX_rate_in_Mpps" >> "$OUTPUT_FILE"
echo "# Experiment: ${EXPERIMENT_DESC}" >> "$OUTPUT_FILE"
echo "# Generated on: $(date)" >> "$OUTPUT_FILE"
echo "# Timestamp: ${TIMESTAMP}" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Loop through core configurations: 1 to 2 cores only for testing
for cores in {1..2}; do
    echo "=== Testing with $cores core(s) ==="
    
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
    while kill -0 $PKTGEN_PID 2>/dev/null && [ $wait_time -lt $max_wait ]; do
        sleep 1
        wait_time=$((wait_time + 1))
    done
    
    # If process is still running, force kill it
    if kill -0 $PKTGEN_PID 2>/dev/null; then
        echo "   Warning: pktgen didn't exit after ${max_wait}s, force killing..."
        sudo pkill -P $PKTGEN_PID 2>/dev/null || true
        sudo kill -9 $PKTGEN_PID 2>/dev/null || true
        sleep 2
    fi
    
    # Wait for the background process to complete and get exit code
    wait $PKTGEN_PID 2>/dev/null
    PKTGEN_EXIT_CODE=$?
    
    # Check exit code
    if [ $PKTGEN_EXIT_CODE -eq 124 ]; then
        echo "   Error: pktgen timed out after 30 seconds"
        echo "[$SETUP_STRING]|[TIMEOUT]" >> "$OUTPUT_FILE"
        rm -f "$TEMP_OUTPUT"
        continue
    elif [ $PKTGEN_EXIT_CODE -ne 0 ]; then
        echo "   Error: pktgen exited with code $PKTGEN_EXIT_CODE"
        echo "[$SETUP_STRING]|[ERROR_EXIT_$PKTGEN_EXIT_CODE]" >> "$OUTPUT_FILE"
        echo "   Debug output:"
        cat "$TEMP_OUTPUT" | tail -20
        rm -f "$TEMP_OUTPUT"
        continue
    fi
    
    # Extract TX rate from output (look for "Average TX Rate: X.XXX Mpps")
    TX_RATE=$(grep "Average TX Rate:" "$TEMP_OUTPUT" | sed -n 's/.*Average TX Rate: \([0-9.]*\) Mpps.*/\1/p')
    
    if [ -n "$TX_RATE" ]; then
        echo "   TX Rate: ${TX_RATE} Mpps"
        echo "$SETUP_STRING|$TX_RATE" >> "$OUTPUT_FILE"
    else
        echo "   Error: Could not extract TX rate from output"
        echo "$SETUP_STRING|ERROR" >> "$OUTPUT_FILE"
        
        # Debug: show the captured output
        echo "   Debug output:"
        cat "$TEMP_OUTPUT" | tail -20
    fi
    
    # Clean up temp file
    rm -f "$TEMP_OUTPUT"
    
    echo ""
    
    # Small delay between tests to ensure clean state
    sleep 2
done

echo "=== Test benchmark completed ==="
echo "Results saved to: $OUTPUT_FILE"
echo ""
echo "Summary of results:"
cat "$OUTPUT_FILE"
