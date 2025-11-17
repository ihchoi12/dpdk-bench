#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PYTHONPATH="$SCRIPT_DIR/sdk/opt/neohost/sdk:$SCRIPT_DIR/backend/opt/neohost/backend:$PYTHONPATH"
export LD_LIBRARY_PATH="$SCRIPT_DIR/backend/opt/neohost/backend/plugins/mftFw:$LD_LIBRARY_PATH"

PYTHON="$SCRIPT_DIR/miniconda3/envs/py27/bin/python"

# Run neohost performance counters
exec sudo -E "$PYTHON" \
    "$SCRIPT_DIR/sdk/opt/neohost/sdk/get_device_performance_counters.py" \
    "$@"
