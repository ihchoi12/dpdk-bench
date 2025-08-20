#!/usr/bin/env bash
# L3FWD vs Pktgen RX/TX Rate Benchmark
# Tests l3fwd performance (1-16 cores) against pktgen 8-core combined mode

# Source common header for DPDK scripts
source "$(dirname "${BASH_SOURCE[0]}")/common-header.sh"

# Configuration
L3FWD_START_CORES="${L3FWD_START_CORES:-1}"
L3FWD_END_CORES="${L3FWD_END_CORES:-16}"
L3FWD_NODE="${L3FWD_NODE:-node8}"
PKTGEN_DURATION="${PKTGEN_DURATION:-10}"  # lua script duration in seconds
L3FWD_EXTRA_TIME="${L3FWD_EXTRA_TIME:-2}"  # extra seconds for l3fwd to run before/after pktgen test

# L3FWD configuration
L3FWD_PCI_ADDR="0000:31:00.1,txqs_min_inline=0,txq_mpw_en=1,txq_inline_mpw=256"
L3FWD_PORT_MASK="-p 0x1"
L3FWD_ETH_DEST="08:c0:eb:b6:cd:5d"

# Remote paths (node8)
REMOTE_REPO_ROOT="/homes/inho/Autokernel/dpdk-bench"
REMOTE_L3FWD_BIN="${REMOTE_REPO_ROOT}/dpdk/build/examples/dpdk-l3fwd"

# Results
RESULTS_DIR="${REPO_ROOT}/results"
TIMESTAMP=$(date '+%y%m%d-%H%M%S')
RESULTS_FILE="${RESULTS_DIR}/${TIMESTAMP}-l3fwd-vs-pktgen.txt"

# Create results directory
mkdir -p "${RESULTS_DIR}"

# Cleanup function
cleanup() {
    echo ">> Cleanup function called..."
    
    # Prevent recursive calls
    if [ "${CLEANUP_IN_PROGRESS:-0}" = "1" ]; then
        return 0
    fi
    export CLEANUP_IN_PROGRESS=1
    
    # Stop any running pktgen processes
    echo ">> Stopping pktgen processes..."
    sudo pkill -f 'pktgen' 2>/dev/null || true
    
    # Stop any remote l3fwd processes
    echo ">> Checking for l3fwd processes on ${L3FWD_NODE}..."
    local l3fwd_pids=$(ssh ${L3FWD_NODE} "pgrep -f 'dpdk-l3fwd'" 2>/dev/null || true)
    if [ -n "$l3fwd_pids" ]; then
        echo ">> Found l3fwd processes on ${L3FWD_NODE}: $l3fwd_pids"
        echo ">> Terminating l3fwd processes on ${L3FWD_NODE}..."
        ssh ${L3FWD_NODE} "sudo pkill -f 'dpdk-l3fwd'" 2>/dev/null || true
        sleep 2
    else
        echo ">> No l3fwd processes found on ${L3FWD_NODE}"
    fi
    
    # Clean up DPDK resources
    sudo rm -f /var/run/dpdk/rte/config 2>/dev/null || true
    ssh ${L3FWD_NODE} "sudo rm -f /var/run/dpdk/rte/config" 2>/dev/null || true
    
    export CLEANUP_IN_PROGRESS=0
}

# Set up signal handlers
trap cleanup EXIT INT TERM

# Function to generate L3FWD configuration string for given core count
generate_l3fwd_config() {
    local cores=$1
    local config=""
    
    for ((i=0; i<cores; i++)); do
        if [ $i -eq 0 ]; then
            config="(0,$i,$i)"
        else
            config="$config,(0,$i,$i)"
        fi
    done
    
    echo "$config"
}

# Function to start l3fwd on remote node
start_l3fwd() {
    local cores=$1
    local lcores_arg="-l 0-$((cores-1))"
    local config_str=$(generate_l3fwd_config $cores)
    local app_args="${L3FWD_PORT_MASK} --config=\"${config_str}\" --eth-dest=0,${L3FWD_ETH_DEST}"
    
    echo ">> Starting l3fwd with $cores cores on ${L3FWD_NODE}..."
    echo "   EAL lcores: $lcores_arg"
    echo "   Config: $config_str"
    echo "   Final l3fwd command: sudo -E ${REMOTE_L3FWD_BIN} ${lcores_arg} -n 4 -a ${L3FWD_PCI_ADDR} -- ${app_args}"
    
    # Start l3fwd in background on remote node
    ssh ${L3FWD_NODE} << EOF &
cd ${REMOTE_REPO_ROOT}
export REPO_ROOT="${REMOTE_REPO_ROOT}"
export DPDK_PREFIX="${REMOTE_REPO_ROOT}/dpdk/build"
sudo -E ${REMOTE_L3FWD_BIN} ${lcores_arg} -n 4 -a ${L3FWD_PCI_ADDR} -- ${app_args}
EOF
    
    local ssh_pid=$!
    
    # Wait a moment for l3fwd to start
    sleep 3
    
    # Verify l3fwd is running
    local l3fwd_check=$(ssh ${L3FWD_NODE} "pgrep -f 'dpdk-l3fwd'" 2>/dev/null || true)
    if [ -z "$l3fwd_check" ]; then
        echo ">> ERROR: l3fwd failed to start on ${L3FWD_NODE}"
        return 1
    fi
    
    echo ">> l3fwd started successfully on ${L3FWD_NODE} (PID: $l3fwd_check)"
    return 0
}

# Function to stop l3fwd
stop_l3fwd() {
    echo ">> Stopping l3fwd on ${L3FWD_NODE}..."
    ssh ${L3FWD_NODE} "sudo pkill -f 'dpdk-l3fwd'" 2>/dev/null || true
    sleep 2
}

# Function to run complete test (L3FWD + pktgen) with retry logic
run_complete_test_with_retry() {
    local cores=$1
    local max_retries=3
    local attempt=1
    local success=false
    local tx_rate="FAILED"
    local rx_rate="FAILED"
    local pktgen_setup=""
    local l3fwd_setup=""
    
    # Generate L3FWD parameters for this test
    local l3fwd_lcores="-l 0-$((cores-1))"
    local l3fwd_config=$(generate_l3fwd_config $cores)
    
    # Get pktgen parameters from config
    local pktgen_lcores="${PKTGEN_LCORES:--l 0-8}"
    local pktgen_portmap="${PKTGEN_PORTMAP:-[1-8].0}"
    
    # Create setup strings for results
    pktgen_setup="${pktgen_lcores} -m ${pktgen_portmap}"
    l3fwd_setup="${l3fwd_lcores}"
    
    while [ $attempt -le $max_retries ] && [ "$success" = false ]; do
        if [ $attempt -gt 1 ]; then
            echo "   Attempt $attempt for $cores core(s)"
            # Clean up any lingering processes and shared memory
            sudo pkill -f pktgen 2>/dev/null || true
            sudo pkill -f dpdk 2>/dev/null || true
            sudo rm -f /dev/hugepages/rtemap_* 2>/dev/null || true
            sudo rm -f /var/run/dpdk/rte/config 2>/dev/null || true
            sudo rm -rf /var/run/dpdk/pktgen1/* 2>/dev/null || true
            sudo rm -f /tmp/.rte_config 2>/dev/null || true
            
            # Also clean up remote l3fwd processes
            stop_l3fwd
            sleep 3
        fi
        
        # Start l3fwd with current core count
        echo ">> Starting l3fwd with $cores cores on ${L3FWD_NODE}... (attempt $attempt)"
        if ! start_l3fwd $cores; then
            echo "   L3FWD startup failed, will retry..."
            attempt=$((attempt + 1))
            if [ $attempt -le $max_retries ]; then
                echo "   Waiting 5 seconds before retry..."
                sleep 5
            fi
            continue
        fi
        
        # Wait extra time for l3fwd to stabilize
        echo ">> Waiting ${L3FWD_EXTRA_TIME} seconds for l3fwd to stabilize..."
        sleep $L3FWD_EXTRA_TIME
        
        # Run pktgen test
        echo ">> Running pktgen test against l3fwd ($cores cores)..."
        
        # Set environment variables for pktgen
        export SCRIPT_FILE="${REPO_ROOT}/Pktgen-DPDK/scripts/measure-rx-tx-rate.lua"
        export PKTGEN_DURATION="$PKTGEN_DURATION"
        
        # Run pktgen with lua script and capture output
        output_file="/tmp/pktgen_output_${cores}cores_attempt${attempt}.txt"
        echo "   Executing: make run-pktgen-with-lua-script > "$output_file" 2>&1"
        
        # Temporarily disable exit on error for this function
        set +e
        local original_set_e=$(set +o | grep 'set +o errexit' > /dev/null && echo "false" || echo "true")
        
        cd "${REPO_ROOT}" && make run-pktgen-with-lua-script > "$output_file" 2>&1
        pktgen_exit_code=$?
        
        # Restore original set -e state
        if [ "$original_set_e" = "true" ]; then
            set -e
        fi
        
        # Check for segfault or other errors
        local has_segfault=false
        local has_error=false
        
        if [ -f "$output_file" ]; then
            if grep -q "Segment Fault\|Segmentation fault\|segfault" "$output_file" 2>/dev/null; then
                has_segfault=true
                echo ""
                echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
                echo "!!! SEGMENTATION FAULT DETECTED !!!"
                echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
                echo ">> Critical error: Segmentation fault occurred during pktgen execution"
                echo ">> This indicates a serious bug that needs investigation"
                echo ">> Stopping benchmark test immediately for safety"
                echo ">> Check the following for debugging:"
                echo "   - pktgen-workq.c workq_run() function"
                echo "   - Multi-core workqueue initialization"
                echo "   - Memory corruption or NULL pointer dereference"
                echo ""
                echo ">> Segfault details from output:"
                grep -A 5 -B 5 "Segment Fault\|Segmentation fault\|segfault" "$output_file" 2>/dev/null || true
                echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
                echo ""
                
                # Save the output file for debugging
                local debug_file="${RESULTS_DIR}/${TIMESTAMP}-segfault-debug-${cores}cores.txt"
                cp "$output_file" "$debug_file" 2>/dev/null || true
                echo ">> Segfault debug output saved to: $debug_file"
                
                # Add segfault info to results file
                echo "# SEGMENTATION FAULT DETECTED - Test stopped at $cores cores" >> "$RESULTS_FILE"
                echo "${pktgen_setup}|${l3fwd_setup}|SEGFAULT|SEGFAULT" >> "$RESULTS_FILE"
                
                # Cleanup and exit immediately
                cleanup
                exit 1
            fi
        fi
        
        if [ $pktgen_exit_code -ne 0 ] && [ "$has_segfault" = false ]; then
            has_error=true
        fi
        
        # Extract rates if no major errors
        if [ "$has_segfault" = false ] && [ "$has_error" = false ] && [ -f "$output_file" ] && [ -s "$output_file" ]; then
            tx_rate=$(grep "RESULT_TX_RATE_MPPS:" "$output_file" 2>/dev/null | cut -d':' -f2 | sed 's/^[[:space:]]*//' || echo "0.000")
            rx_rate=$(grep "RESULT_RX_RATE_MPPS:" "$output_file" 2>/dev/null | cut -d':' -f2 | sed 's/^[[:space:]]*//' || echo "0.000")
            
            # Consider test successful if we got meaningful rates (either TX or RX should be non-zero)
            if [ "$tx_rate" != "0.000" ] || [ "$rx_rate" != "0.000" ]; then
                echo ">> Complete test (L3FWD + pktgen) completed successfully"
                echo "   TX Rate: ${tx_rate} Mpps"
                echo "   RX Rate: ${rx_rate} Mpps"
                success=true
            else
                echo "   Could not extract meaningful rates, will retry complete test..."
            fi
        elif [ "$has_segfault" = true ]; then
            echo "   Segmentation fault detected, will retry complete test..."
        elif [ "$has_error" = true ]; then
            echo "   Error detected (exit code: $pktgen_exit_code), will retry complete test..."
        else
            echo "   No output or empty output, will retry complete test..."
        fi
        
        # Clean up output file
        rm -f "$output_file"
        
        # Stop l3fwd before next attempt or exit
        stop_l3fwd
        
        if [ "$success" = false ]; then
            attempt=$((attempt + 1))
            if [ $attempt -le $max_retries ]; then
                echo "   Waiting 5 seconds before retry..."
                sleep 5
            fi
        fi
    done
    
    if [ "$success" = false ]; then
        echo ">> ERROR: Complete test (L3FWD + pktgen) failed after $max_retries attempts"
        tx_rate="FAILED"
        rx_rate="FAILED"
    fi
    
    # Export results for caller
    export COMPLETE_TEST_TX_RATE="$tx_rate"
    export COMPLETE_TEST_RX_RATE="$rx_rate"
    export COMPLETE_TEST_PKTGEN_SETUP="$pktgen_setup"
    export COMPLETE_TEST_L3FWD_SETUP="$l3fwd_setup"
    
    return $([ "$success" = true ] && echo 0 || echo 1)
}

# Function to run pktgen test with retry logic (keeping for compatibility, but now unused)
run_pktgen_test_with_retry() {
    local cores=$1
    local max_retries=3
    local attempt=1
    local success=false
    local tx_rate="0.000"
    local rx_rate="0.000"
    
    while [ $attempt -le $max_retries ] && [ "$success" = false ]; do
        if [ $attempt -gt 1 ]; then
            echo "   Attempt $attempt for $cores core(s)"
            # Clean up any lingering processes and shared memory
            sudo pkill -f pktgen 2>/dev/null || true
            sudo pkill -f dpdk 2>/dev/null || true
            sudo rm -f /dev/hugepages/rtemap_* 2>/dev/null || true
            sudo rm -f /var/run/dpdk/rte/config 2>/dev/null || true
            sudo rm -rf /var/run/dpdk/pktgen1/* 2>/dev/null || true
            sudo rm -f /tmp/.rte_config 2>/dev/null || true
            sleep 3
        fi
        
        # Set environment variables for pktgen
        export SCRIPT_FILE="${REPO_ROOT}/Pktgen-DPDK/scripts/measure-rx-tx-rate.lua"
        export PKTGEN_DURATION="$PKTGEN_DURATION"
        
        # Run pktgen with lua script and capture output
        output_file="/tmp/pktgen_output_${cores}cores_attempt${attempt}.txt"
        echo "   Executing: make run-pktgen-with-lua-script > "$output_file" 2>&1"
        
        # Temporarily disable exit on error for this function
        set +e
        local original_set_e=$(set +o | grep 'set +o errexit' > /dev/null && echo "false" || echo "true")
        
        cd "${REPO_ROOT}" && make run-pktgen-with-lua-script > "$output_file" 2>&1
        pktgen_exit_code=$?
        
        # Restore original set -e state
        if [ "$original_set_e" = "true" ]; then
            set -e
        fi
        
        # Check for segfault or other errors
        local has_segfault=false
        local has_error=false
        
        if [ -f "$output_file" ]; then
            if grep -q "Segment Fault\|Segmentation fault\|segfault" "$output_file" 2>/dev/null; then
                has_segfault=true
            fi
        fi
        
        if [ $pktgen_exit_code -ne 0 ] && [ "$has_segfault" = false ]; then
            has_error=true
        fi
        
        # Extract rates if no major errors
        if [ "$has_segfault" = false ] && [ "$has_error" = false ] && [ -f "$output_file" ] && [ -s "$output_file" ]; then
            tx_rate=$(grep "RESULT_TX_RATE_MPPS:" "$output_file" 2>/dev/null | cut -d':' -f2 | sed 's/^[[:space:]]*//' || echo "0.000")
            rx_rate=$(grep "RESULT_RX_RATE_MPPS:" "$output_file" 2>/dev/null | cut -d':' -f2 | sed 's/^[[:space:]]*//' || echo "0.000")
            
            # Consider test successful if we got meaningful rates
            if [ "$tx_rate" != "0.000" ] || [ "$rx_rate" != "0.000" ]; then
                echo ">> Pktgen test completed successfully"
                echo "   TX Rate: ${tx_rate} Mpps"
                echo "   RX Rate: ${rx_rate} Mpps"
                success=true
            else
                echo "   Could not extract meaningful rates, will retry..."
            fi
        elif [ "$has_segfault" = true ]; then
            echo "   Segmentation fault detected, will retry..."
        elif [ "$has_error" = true ]; then
            echo "   Error detected (exit code: $pktgen_exit_code), will retry..."
        else
            echo "   No output or empty output, will retry..."
        fi
        
        # Clean up output file
        rm -f "$output_file"
        
        if [ "$success" = false ]; then
            attempt=$((attempt + 1))
            if [ $attempt -le $max_retries ]; then
                echo "   Waiting 5 seconds before retry..."
                sleep 5
            fi
        fi
    done
    
    if [ "$success" = false ]; then
        echo ">> ERROR: Pktgen test failed after $max_retries attempts"
        tx_rate="FAILED"
        rx_rate="FAILED"
    fi
    
    # Export results for caller
    export PKTGEN_TX_RATE="$tx_rate"
    export PKTGEN_RX_RATE="$rx_rate"
    
    return $([ "$success" = true ] && echo 0 || echo 1)
}
echo ">> L3FWD vs Pktgen RX/TX Rate Benchmark"
echo "   L3FWD cores range: ${L3FWD_START_CORES}-${L3FWD_END_CORES}"
echo "   L3FWD target node: ${L3FWD_NODE}"
echo "   Pktgen setup: Using pktgen.config settings"
echo "   Pktgen duration: ${PKTGEN_DURATION} seconds"
echo "   Results file: ${RESULTS_FILE}"
echo ""

# Check SSH connectivity
echo ">> Checking SSH connectivity to ${L3FWD_NODE}..."
if ! ssh ${L3FWD_NODE} "echo 'SSH connection test successful'" 2>/dev/null; then
    echo "!! ERROR: Cannot connect to ${L3FWD_NODE} via SSH"
    exit 1
fi

# Check required binaries
check_binary "${REPO_ROOT}/Pktgen-DPDK/build/app/pktgen" "pktgen"

# Create results file header
cat > "$RESULTS_FILE" << EOF
# L3FWD vs Pktgen RX/TX Rate Benchmark Results
# Generated: $(date)
# Format: pktgen_setup|l3fwd_setup|RX_rate|TX_rate
# Pktgen: Using pktgen.config settings
# L3FWD: Variable cores (${L3FWD_START_CORES}-${L3FWD_END_CORES}) on ${L3FWD_NODE}
# Test duration: ${PKTGEN_DURATION} seconds per test

EOF

# Run tests for each core count
for cores in $(seq $L3FWD_START_CORES $L3FWD_END_CORES); do
    echo "========================================"
    echo "Testing L3FWD with $cores core(s)"
    echo "========================================"
    
    # Run complete test (L3FWD + pktgen) with retry logic
    if run_complete_test_with_retry $cores; then
        tx_rate="$COMPLETE_TEST_TX_RATE"
        rx_rate="$COMPLETE_TEST_RX_RATE"
        pktgen_setup="$COMPLETE_TEST_PKTGEN_SETUP"
        l3fwd_setup="$COMPLETE_TEST_L3FWD_SETUP"
    else
        tx_rate="FAILED"
        rx_rate="FAILED"
        # Still save setup info even on failure
        pktgen_setup="$COMPLETE_TEST_PKTGEN_SETUP"
        l3fwd_setup="$COMPLETE_TEST_L3FWD_SETUP"
    fi
    
    # Save results with actual setup parameters
    echo "${pktgen_setup}|${l3fwd_setup}|${rx_rate}|${tx_rate}" >> "$RESULTS_FILE"
    
    # Wait between tests to ensure clean state
    echo ">> Waiting 5 seconds between tests for thorough cleanup..."
    
    # More thorough cleanup between tests
    sudo pkill -f pktgen 2>/dev/null || true
    sudo pkill -f dpdk 2>/dev/null || true
    sudo rm -f /dev/hugepages/rtemap_* 2>/dev/null || true
    sudo rm -f /var/run/dpdk/rte/config 2>/dev/null || true
    sudo rm -rf /var/run/dpdk/pktgen1/* 2>/dev/null || true
    sudo rm -f /tmp/.rte_config 2>/dev/null || true
    
    sleep 5
    
    echo ">> Test completed for $cores cores"
    echo ""
done

echo "========================================"
echo "L3FWD vs Pktgen benchmark completed!"
echo "========================================"
echo ">> Results saved to: ${RESULTS_FILE}"
echo ""
echo ">> Summary:"
echo "   Format: pktgen_setup|l3fwd_setup|RX_rate|TX_rate"
grep -v "^#" "$RESULTS_FILE" | while IFS='|' read -r pktgen_setup l3fwd_setup rx_rate tx_rate; do
    if [ -n "$pktgen_setup" ]; then
        if [ "$rx_rate" = "FAILED" ] || [ "$tx_rate" = "FAILED" ]; then
            echo "    ${l3fwd_setup}: Test FAILED"
        elif [ "$rx_rate" = "failed" ] || [ "$tx_rate" = "failed" ]; then
            echo "    ${l3fwd_setup}: L3FWD startup failed"
        else
            echo "    ${l3fwd_setup}: RX=${rx_rate} Mpps, TX=${tx_rate} Mpps"
        fi
    fi
done
