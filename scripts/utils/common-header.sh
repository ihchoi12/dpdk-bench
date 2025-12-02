#!/usr/bin/env bash
# Common header for DPDK benchmark scripts
# Usage: source "$(dirname "${BASH_SOURCE[0]}")/common-header.sh"

# Bash strict mode
set -euo pipefail

# Error handling function
on_error() {
  echo "!! ERROR: ${BASH_SOURCE[1]}:${BASH_LINENO[0]}: \"$BASH_COMMAND\" failed" >&2
}

# TTY state management
ORIG_STTY=""
if [ -t 0 ]; then
  ORIG_STTY="$(stty -g || true)"
fi

restore_tty() {
  # Try exact restore first; fallback to sane
  if [ -n "${ORIG_STTY}" ]; then
    stty "${ORIG_STTY}" 2>/dev/null || stty sane 2>/dev/null || true
  fi
}

# Set up traps
trap 'restore_tty' EXIT INT TERM
trap 'on_error; restore_tty' ERR

# Common path variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DPDK_PREFIX="${DPDK_PREFIX:-${REPO_ROOT}/dpdk/build}"

# Load configuration file
CONFIG_FILE="${REPO_ROOT}/pktgen.config"
if [ -f "$CONFIG_FILE" ]; then
  echo ">> Loading configuration from: $CONFIG_FILE"
  # Source the config file, ignoring comments and empty lines
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip comments and empty lines
    if [[ "$line" =~ ^[[:space:]]*# ]] || [[ "$line" =~ ^[[:space:]]*$ ]]; then
      continue
    fi
    # Export the variable
    if [[ "$line" =~ ^[[:space:]]*([A-Z_][A-Z0-9_]*)=(.*)$ ]]; then
      export "${BASH_REMATCH[1]}"="${BASH_REMATCH[2]}"
    fi
  done < "$CONFIG_FILE"
else
  echo ">> Warning: Configuration file not found: $CONFIG_FILE"
  echo "   Using default values..."
fi

# Setup DPDK runtime environment
setup_dpdk_env() {
  export PKG_CONFIG_PATH="${DPDK_PREFIX}/lib/pkgconfig:${DPDK_PREFIX}/lib/x86_64-linux-gnu/pkgconfig:${PKG_CONFIG_PATH:-}"
  export LD_LIBRARY_PATH="${DPDK_PREFIX}/lib:${DPDK_PREFIX}/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"
}

# Common binary check function
check_binary() {
  local binary_path="$1"
  local build_target="$2"
  
  if [ ! -x "$binary_path" ]; then
    echo ">> Binary not found, building $build_target..."
    make -C "$REPO_ROOT" "$build_target"
  fi
  
  if [ ! -x "$binary_path" ]; then
    echo "Binary not found after build: $binary_path" >&2
    exit 1
  fi
}

# Initialize environment
setup_dpdk_env

echo ">> DPDK common environment initialized"
echo "   REPO_ROOT   : ${REPO_ROOT}"
echo "   DPDK_PREFIX : ${DPDK_PREFIX}"
