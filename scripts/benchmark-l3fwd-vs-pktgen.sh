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

# Main execution
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
    
    # Start l3fwd with current core count
    if ! start_l3fwd $cores; then
        echo ">> Skipping test for $cores cores due to l3fwd startup failure"
        echo "pktgen_config|l3fwd_${cores}core|failed|failed" >> "$RESULTS_FILE"
        continue
    fi
    
    # Wait extra time for l3fwd to stabilize
    echo ">> Waiting ${L3FWD_EXTRA_TIME} seconds for l3fwd to stabilize..."
    sleep $L3FWD_EXTRA_TIME
    
    # Run pktgen test and get rates
    echo ">> Running pktgen test against l3fwd ($cores cores)..."
    
    # Set environment variables for pktgen
    export SCRIPT_FILE="${REPO_ROOT}/Pktgen-DPDK/scripts/measure-rx-tx-rate.lua"
    export PKTGEN_DURATION="$PKTGEN_DURATION"
    
    # Run pktgen with lua script and capture output
    output_file="/tmp/pktgen_output_${cores}cores.txt"
    echo "   Executing: make run-pktgen-with-lua-script"
    
    cd "${REPO_ROOT}" && make run-pktgen-with-lua-script
    pktgen_exit_code=$?
    
    if [ $pktgen_exit_code -eq 0 ]; then
        # Extract RX and TX rates from output
        tx_rate=$(grep "RESULT_TX_RATE_MPPS:" "$output_file" 2>/dev/null | cut -d':' -f2 | sed 's/^[[:space:]]*//' || echo "0.000")
        rx_rate=$(grep "RESULT_RX_RATE_MPPS:" "$output_file" 2>/dev/null | cut -d':' -f2 | sed 's/^[[:space:]]*//' || echo "0.000")
        
        echo ">> Pktgen test completed successfully"
        echo "   TX Rate: ${tx_rate} Mpps"
        echo "   RX Rate: ${rx_rate} Mpps"
        
        # Debug: Show the relevant lines from output file
        echo "   Debug - found result lines:"
        grep "RESULT_.*_RATE_MPPS:" "$output_file" 2>/dev/null || echo "   No result lines found"
        
        # Clean up output file
        rm -f "$output_file"
    else
        echo ">> ERROR: Pktgen test failed (exit code: $pktgen_exit_code)"
        echo "   Debug - last 20 lines of output:"
        cat "$output_file" | tail -20  # Show last 20 lines for debugging
        rm -f "$output_file"
        tx_rate="0.000"
        rx_rate="0.000"
    fi
    
    # Save results
    echo "pktgen_config|l3fwd_${cores}core|${rx_rate}|${tx_rate}" >> "$RESULTS_FILE"
    
    # Stop l3fwd
    stop_l3fwd
    
    # Wait between tests to ensure clean state
    echo ">> Waiting 3 seconds between tests..."
    sleep 3
    
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
        echo "    $l3fwd_setup: RX=${rx_rate} Mpps, TX=${tx_rate} Mpps"
    fi
done
