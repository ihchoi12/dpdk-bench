#!/usr/bin/env bash
# Script to run l3fwd multi-core benchmark (1-16 cores) on remote node
# This script runs from node7 and controls l3fwd on node8 remotely
# Usage: ./benchmark-l3fwd-multi-core.sh
# Environment variables:
#   L3FWD_DURATION - Duration in seconds for each test (default: 5)
#   L3FWD_NODE - Target node for l3fwd (default: node8)
# Examples:
#   ./benchmark-l3fwd-multi-core.sh                    # Run with default settings
#   L3FWD_DURATION=10 ./benchmark-l3fwd-multi-core.sh  # Run each test for 10 seconds

# Source common header for DPDK scripts
source "$(dirname "${BASH_SOURCE[0]}")/common-header.sh"

# L3FWD specific configuration
L3FWD_BIN="${L3FWD_BIN:-${DPDK_PREFIX}/examples/dpdk-l3fwd}"

# Load parameters from config file (can be overridden by environment)
EAL_MEMCH="${EAL_MEMCH:-${L3FWD_MEMCH:--n 4}}"
PCI_ADDR="${PCI_ADDR:-${L3FWD_PCI_ADDR:-0000:31:00.1}}"
PORT_MASK="${PORT_MASK:-${L3FWD_PORT_MASK:--p 0x1}}"
ETH_DEST="${ETH_DEST:-${L3FWD_ETH_DEST:-08:c0:eb:b6:cd:5d}}"

# Duration in seconds for each test (can be overridden by environment variable)
DURATION="${L3FWD_DURATION:-5}"

# Target node for l3fwd execution
L3FWD_NODE="${L3FWD_NODE:-node8}"

# Remote paths (assuming same directory structure on target node)
REMOTE_REPO_ROOT="/homes/inho/Autokernel/dpdk-bench"
REMOTE_L3FWD_BIN="${REMOTE_REPO_ROOT}/dpdk/build/examples/dpdk-l3fwd"
REMOTE_L3FWD_PREFIX="${REMOTE_REPO_ROOT}/dpdk/build"

# Results directory and file
RESULTS_DIR="${REPO_ROOT}/results"
TIMESTAMP=$(date '+%y%m%d-%H%M%S')
RESULTS_FILE="${RESULTS_DIR}/${TIMESTAMP}-l3fwd-multi-core.txt"

# Create results directory if it doesn't exist
mkdir -p "${RESULTS_DIR}"

# Note: We'll check the remote binary existence later in the SSH connectivity check
# check_binary "$L3FWD_BIN" "l3fwd"  # This was for local execution

# Function to generate L3FWD configuration string for given core count
generate_l3fwd_config() {
    local cores=$1
    local config=""
    
    for ((i=0; i<cores; i++)); do
        if [ $i -eq 0 ]; then
            config="(0,$i,$i)"
        else
            config="${config},(0,$i,$i)"
        fi
    done
    
    echo "$config"
}

# Function to cleanup on exit
cleanup() {
    echo ">> Cleanup function called..."
    # Kill any l3fwd processes that might be running on remote node
    echo ">> Checking for l3fwd processes on ${L3FWD_NODE}..."
    local l3fwd_pids=$(ssh ${L3FWD_NODE} "pgrep -f 'dpdk-l3fwd'" 2>/dev/null)
    if [[ -n "$l3fwd_pids" ]]; then
        echo ">> Found l3fwd processes on ${L3FWD_NODE}: $l3fwd_pids"
        echo ">> Terminating l3fwd processes on ${L3FWD_NODE}..."
        ssh ${L3FWD_NODE} "sudo pkill -TERM -f 'dpdk-l3fwd'" 2>/dev/null
        sleep 2
        # Force kill if still running
        local remaining_pids=$(ssh ${L3FWD_NODE} "pgrep -f 'dpdk-l3fwd'" 2>/dev/null)
        if [[ -n "$remaining_pids" ]]; then
            echo ">> Force killing remaining l3fwd processes on ${L3FWD_NODE}: $remaining_pids"
            ssh ${L3FWD_NODE} "sudo pkill -KILL -f 'dpdk-l3fwd'" 2>/dev/null
        fi
    else
        echo ">> No l3fwd processes found on ${L3FWD_NODE}"
    fi
}

# Function to run l3fwd with retry logic for a specific core configuration
run_l3fwd_test() {
    local cores=$1
    local lcores_arg="-l 0-$((cores-1))"
    local config_str=$(generate_l3fwd_config $cores)
    local app_args="${PORT_MASK} --config=\"${config_str}\" --eth-dest=0,${ETH_DEST}"
    
    echo ">> Testing l3fwd with $cores cores on ${L3FWD_NODE}..."
    echo "   EAL lcores: $lcores_arg"
    echo "   Config: $config_str"
    
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        echo ">> Attempt $attempt of $max_attempts for $cores cores..."
        
        # Disable 'set -e' temporarily to handle failures gracefully
        set +e
        
        # Run l3fwd on remote node
        timeout "${DURATION}" ssh ${L3FWD_NODE} << EOF &
cd ${REMOTE_REPO_ROOT}
# Set environment manually to avoid BASH_SOURCE issues  
export REPO_ROOT="${REMOTE_REPO_ROOT}"
export DPDK_PREFIX="${REMOTE_L3FWD_PREFIX}"
sudo -E ${REMOTE_L3FWD_BIN} ${lcores_arg} ${EAL_MEMCH} -a ${PCI_ADDR} -- ${app_args}
EOF
        
        # Get the background SSH job PID
        local ssh_pid=$!
        
        # Wait for the test to complete
        wait $ssh_pid
        local exit_code=$?
        
        # Re-enable 'set -e'
        set -e
        
        if [ $exit_code -eq 0 ] || [ $exit_code -eq 124 ]; then  # 124 is timeout exit code
            echo ">> Test completed successfully for $cores cores (exit code: $exit_code)"
            echo "${cores}|completed" >> "$RESULTS_FILE"
            return 0
        else
            echo ">> Attempt $attempt failed for $cores cores with exit code $exit_code"
            if [ $attempt -lt $max_attempts ]; then
                echo ">> Waiting 2 seconds before retry..."
                sleep 2
                # Clean up any leftover processes
                ssh ${L3FWD_NODE} "sudo pkill -f 'dpdk-l3fwd'" 2>/dev/null || true
                sleep 1
            fi
        fi
        
        attempt=$((attempt + 1))
    done
    
    echo ">> All $max_attempts attempts failed for $cores cores"
    echo "${cores}|failed" >> "$RESULTS_FILE"
    return 1
}

# Set up signal handlers
trap cleanup EXIT INT TERM

echo ">> L3FWD Multi-core Benchmark"
echo "   Duration per test: ${DURATION} seconds"
echo "   Target node: ${L3FWD_NODE}"
echo "   Results file: ${RESULTS_FILE}"
echo ""

# Check SSH connectivity first
if ! ssh ${L3FWD_NODE} "echo 'SSH connection test successful'" 2>/dev/null; then
    echo ">> ERROR: Cannot connect to ${L3FWD_NODE} via SSH"
    echo ">> Please ensure:"
    echo "   1. SSH keys are set up for passwordless access"
    echo "   2. ${L3FWD_NODE} is accessible from this machine"
    exit 1
fi

# Check if the remote binary exists
if ! ssh ${L3FWD_NODE} "test -f '${REMOTE_L3FWD_BIN}'" 2>/dev/null; then
    echo ">> ERROR: l3fwd binary not found on ${L3FWD_NODE}: ${REMOTE_L3FWD_BIN}"
    echo ">> Please build l3fwd on ${L3FWD_NODE} first"
    exit 1
fi

# Write header to results file
echo "# L3FWD Multi-core Benchmark Results" > "$RESULTS_FILE"
echo "# Generated: $(date)" >> "$RESULTS_FILE"
echo "# Format: cores|status" >> "$RESULTS_FILE"
echo "# Duration per test: ${DURATION} seconds" >> "$RESULTS_FILE"
echo "# Target node: ${L3FWD_NODE}" >> "$RESULTS_FILE"
echo "" >> "$RESULTS_FILE"

# Run tests for specified core range (default 1 to 16)
START_CORES="${L3FWD_START_CORES:-1}"
END_CORES="${L3FWD_END_CORES:-16}"

for cores in $(seq $START_CORES $END_CORES); do
    echo "=================="
    echo "Testing $cores core(s)"
    echo "=================="
    
    run_l3fwd_test $cores
    
    # Brief pause between tests
    sleep 2
done

echo ""
echo ">> L3FWD multi-core benchmark completed!"
echo ">> Results saved to: $RESULTS_FILE"
echo ""
echo ">> Summary:"
cat "$RESULTS_FILE" | grep -E '^[0-9]+\|' | while IFS='|' read -r cores status; do
    printf "   %2d cores: %s\n" "$cores" "$status"
done

exit 0
