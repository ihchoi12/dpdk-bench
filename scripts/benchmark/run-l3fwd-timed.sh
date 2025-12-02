#!/usr/bin/env bash
# Script to run l3fwd on node8 via SSH for a specified duration and then terminate it
# This script runs from node7 and controls l3fwd on node8 remotely
# Usage: ./run-l3fwd-timed.sh
# Environment variables:
#   L3FWD_DURATION - Duration in seconds (default: 5)
#   L3FWD_NODE - Target node for l3fwd (default: node8)
# Examples:
#   ./run-l3fwd-timed.sh                    # Run for 5 seconds on node8 (default)
#   L3FWD_DURATION=10 ./run-l3fwd-timed.sh  # Run for 10 seconds on node8
#   L3FWD_NODE=node9 ./run-l3fwd-timed.sh   # Run on node9 instead

# Source common header for DPDK scripts
source "$(dirname "${BASH_SOURCE[0]}")/../utils/common-header.sh"

# L3FWD specific configuration
L3FWD_BIN="${L3FWD_BIN:-${DPDK_PREFIX}/examples/dpdk-l3fwd}"

# Load parameters from config file (can be overridden by environment)
EAL_LCORES="${EAL_LCORES:-${L3FWD_LCORES:--l 0-2}}"
EAL_MEMCH="${EAL_MEMCH:-${L3FWD_MEMCH:--n 4}}"
PCI_ADDR="${PCI_ADDR:-${L3FWD_PCI_ADDR:-0000:31:00.1}}"
PORT_MASK="${PORT_MASK:-${L3FWD_PORT_MASK:--p 0x1}}"
CONFIG_STR="${CONFIG_STR:-${L3FWD_CONFIG:-(0,0,0),(0,1,1),(0,2,2)}}"
ETH_DEST="${ETH_DEST:-${L3FWD_ETH_DEST:-08:c0:eb:b6:cd:5d}}"

# Build complete APP_ARGS - escape quotes properly for remote execution
APP_ARGS="${PORT_MASK} --config='${CONFIG_STR}' --eth-dest=0,${ETH_DEST}"

# Duration in seconds (can be overridden by environment variable)
DURATION="${L3FWD_DURATION:-5}"

# Target node for l3fwd execution
L3FWD_NODE="${L3FWD_NODE:-node8}"

# Remote paths (assuming same directory structure on target node)
REMOTE_REPO_ROOT="/homes/inho/Autokernel/dpdk-bench"
REMOTE_L3FWD_BIN="${REMOTE_REPO_ROOT}/dpdk/build/examples/dpdk-l3fwd"

# Note: We'll check the remote binary existence later in the SSH connectivity check
# check_binary "$L3FWD_BIN" "l3fwd"  # This was for local execution

echo ">> running l3fwd on ${L3FWD_NODE} for ${DURATION} seconds:"
echo "   remote binary: ${REMOTE_L3FWD_BIN}"
echo "   EAL   : ${EAL_LCORES} ${EAL_MEMCH} -a ${PCI_ADDR}"
echo "   args  : ${APP_ARGS}"

# Build the complete remote command for debugging
REMOTE_FULL_COMMAND="'${REMOTE_L3FWD_BIN}' ${EAL_LCORES} ${EAL_MEMCH} -a '${PCI_ADDR}' -- ${APP_ARGS}"

echo ""
echo ">> Final remote command to execute on ${L3FWD_NODE}:"
echo "   sudo -E ${REMOTE_FULL_COMMAND}"
echo ""

# Create a temporary file to store the process PID
PIDFILE="/tmp/l3fwd_$$.pid"

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
    if [[ -f "$PIDFILE" ]]; then
        rm -f "$PIDFILE"
    fi
}

# Set up signal handlers
trap cleanup EXIT INT TERM

echo ">> Starting l3fwd on ${L3FWD_NODE}..."
echo ">> Will terminate after ${DURATION} seconds..."

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

# Start l3fwd on remote node in background
# Use here-document to avoid quoting issues with complex command
ssh ${L3FWD_NODE} << EOF &
cd ${REMOTE_REPO_ROOT}
source scripts/utils/common-header.sh
sudo -E ${REMOTE_L3FWD_BIN} ${EAL_LCORES} ${EAL_MEMCH} -a ${PCI_ADDR} -- ${APP_ARGS}
EOF

# Get the background SSH job PID
SSH_PID=$!
echo ">> SSH process started with PID: $SSH_PID"

# Wait a moment for the remote l3fwd process to start
sleep 2

# Find the actual l3fwd process PID on remote node
L3FWD_PID=$(ssh ${L3FWD_NODE} "pgrep -f 'dpdk-l3fwd'" 2>/dev/null)
if [[ -n "$L3FWD_PID" ]]; then
    echo ">> l3fwd process found on ${L3FWD_NODE} with PID: $L3FWD_PID"
    echo $L3FWD_PID > "$PIDFILE"
else
    echo ">> Warning: Could not find l3fwd process PID on ${L3FWD_NODE}"
fi

# Wait for the specified duration
sleep ${DURATION}

echo ">> ${DURATION} seconds elapsed, terminating l3fwd on ${L3FWD_NODE}..."

# Cleanup will be called automatically by the trap
exit 0
