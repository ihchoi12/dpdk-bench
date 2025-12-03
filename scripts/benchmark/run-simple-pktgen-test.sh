#!/usr/bin/env bash
# Source common header for DPDK scripts
source "$(dirname "${BASH_SOURCE[0]}")/../utils/common-header.sh"

PKTGEN_BIN="${PKTGEN_BIN:-${REPO_ROOT}/Pktgen-DPDK/build/app/pktgen}"

# Load parameters from config files
# - system.config: PKTGEN_NIC_PCI (hardware)
# - simple-test/simple-test.config: PKTGEN_* (test parameters)
LCORES="${LCORES:-${PKTGEN_LCORES:--l 0-1}}"
MEMCH="${MEMCH:-${PKTGEN_MEMCH:--n 4}}"
FILE_PREFIX="${FILE_PREFIX:-${PKTGEN_FILE_PREFIX:-pktgen1}}"
PORTMAP="${PORTMAP:-${PKTGEN_PORTMAP:-[1].0}}"
PROC_TYPE="${PROC_TYPE:-${PKTGEN_PROC_TYPE:---proc-type auto}}"
APP_ARGS="${APP_ARGS:-${PKTGEN_APP_ARGS:--P -T}}"

# Build PCI address with device args from system.config + test.config
NIC_PCI="${PKTGEN_NIC_PCI:-0000:31:00.1}"
NIC_DEVARGS="${PKTGEN_NIC_DEVARGS:-}"
if [ -n "$NIC_DEVARGS" ]; then
    PCI_ADDR="${NIC_PCI},${NIC_DEVARGS}"
else
    PCI_ADDR="${NIC_PCI}"
fi

# Script file to execute (can be overridden by command line argument or environment)
SCRIPT_FILE="${1:-${SCRIPT_FILE:-${REPO_ROOT}/config/simple-test/simple-pktgen-test.lua}}"

# Convert to relative path from Pktgen-DPDK directory
SCRIPT_REL_PATH=$(realpath --relative-to="${REPO_ROOT}/Pktgen-DPDK" "${SCRIPT_FILE}")

# Check if script file exists
if [ ! -f "$SCRIPT_FILE" ]; then
    echo "Error: Script file not found: $SCRIPT_FILE"
    echo "Usage: $0 [script_file.lua]"
    exit 1
fi

# Ensure built
check_binary "$PKTGEN_BIN" "pktgen"

echo ">> running pktgen with script:"
echo "   bin     : ${PKTGEN_BIN}"
echo "   script  : ${SCRIPT_FILE}"
echo "   script_rel: ${SCRIPT_REL_PATH}"
echo "   EAL     : ${LCORES} ${MEMCH} ${PROC_TYPE} --file-prefix ${FILE_PREFIX} --allow=${PCI_ADDR}"
echo "   args    : ${APP_ARGS} -m ${PORTMAP} -f ${SCRIPT_REL_PATH}"

# Debug: Check if files exist before execution
echo ""
echo ">> Pre-execution checks:"
echo "   Binary exists: $([ -f "${PKTGEN_BIN}" ] && echo "YES" || echo "NO")"
echo "   Script exists: $([ -f "${SCRIPT_FILE}" ] && echo "YES" || echo "NO")"
echo "   Pktgen.lua exists: $([ -f "${REPO_ROOT}/Pktgen-DPDK/Pktgen.lua" ] && echo "YES" || echo "NO")"
echo "   Working directory will be: ${REPO_ROOT}/Pktgen-DPDK"

# Build the complete command for debugging
FULL_COMMAND="'${PKTGEN_BIN}' ${LCORES} ${MEMCH} ${PROC_TYPE} --file-prefix '${FILE_PREFIX}' --allow='${PCI_ADDR}' -- ${APP_ARGS} -m '${PORTMAP}' -f '${SCRIPT_REL_PATH}'"

echo ""
echo ">> Final command to execute:"
echo "   cd ${REPO_ROOT}/Pktgen-DPDK && sudo bash -lc \"LD_LIBRARY_PATH='${LD_LIBRARY_PATH}' PKG_CONFIG_PATH='${PKG_CONFIG_PATH}' exec ${FULL_COMMAND}\""
echo ""

# Change to Pktgen-DPDK directory so Lua can find Pktgen.lua
cd "${REPO_ROOT}/Pktgen-DPDK"

# Run under sudo while preserving env inside the root shell
sudo bash -lc "LD_LIBRARY_PATH='${LD_LIBRARY_PATH}' \
  PKG_CONFIG_PATH='${PKG_CONFIG_PATH}' \
  PCIE_LOG_ENABLE='${PCIE_LOG_ENABLE:-0}' \
  ENABLE_PCM='${ENABLE_PCM:-0}' \
  exec '${PKTGEN_BIN}' \
  ${LCORES} ${MEMCH} ${PROC_TYPE} --file-prefix '${FILE_PREFIX}' --allow='${PCI_ADDR}' \
  -- ${APP_ARGS} -m '${PORTMAP}' -f '${SCRIPT_REL_PATH}'"

# Just in case, ensure we end with a newline and restored TTY
printf '\n' || true
