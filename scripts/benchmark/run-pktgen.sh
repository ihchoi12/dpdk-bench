#!/usr/bin/env bash
# Source common header for DPDK scripts
source "$(dirname "${BASH_SOURCE[0]}")/../utils/common-header.sh"

PKTGEN_BIN="${PKTGEN_BIN:-${REPO_ROOT}/Pktgen-DPDK/build/app/pktgen}"

# Load parameters from config file (can be overridden by environment)
LCORES="${LCORES:-${PKTGEN_LCORES:--l 0-1}}"
MEMCH="${MEMCH:-${PKTGEN_MEMCH:--n 4}}"
PCI_ADDR="${PCI_ADDR:-${PKTGEN_PCI_ADDR:-0000:31:00.1}}"
FILE_PREFIX="${FILE_PREFIX:-${PKTGEN_FILE_PREFIX:-pktgen1}}"
PORTMAP="${PORTMAP:-${PKTGEN_PORTMAP:-[1].0}}"
PROC_TYPE="${PROC_TYPE:-${PKTGEN_PROC_TYPE:---proc-type auto}}"
APP_ARGS="${APP_ARGS:-${PKTGEN_APP_ARGS:--P -T}}"

# Ensure built
check_binary "$PKTGEN_BIN" "pktgen"

echo ">> running pktgen:"
echo "   bin   : ${PKTGEN_BIN}"
echo "   EAL   : ${LCORES} ${MEMCH} ${PROC_TYPE} --file-prefix ${FILE_PREFIX} --allow=${PCI_ADDR}"
echo "   args  : ${APP_ARGS} -m ${PORTMAP}"

# Build the complete command for debugging
FULL_COMMAND="'${PKTGEN_BIN}' ${LCORES} ${MEMCH} ${PROC_TYPE} --file-prefix '${FILE_PREFIX}' --allow='${PCI_ADDR}' -- ${APP_ARGS} -m '${PORTMAP}'"

echo ""
echo ">> Final command to execute:"
echo "   sudo bash -lc \"LD_LIBRARY_PATH='${LD_LIBRARY_PATH}' PKG_CONFIG_PATH='${PKG_CONFIG_PATH}' exec ${FULL_COMMAND}\""
echo ""

# Run under sudo while preserving env inside the root shell
sudo bash -lc "LD_LIBRARY_PATH='${LD_LIBRARY_PATH}' \
  PKG_CONFIG_PATH='${PKG_CONFIG_PATH}' \
  exec '${PKTGEN_BIN}' \
  ${LCORES} ${MEMCH} ${PROC_TYPE} --file-prefix '${FILE_PREFIX}' --allow='${PCI_ADDR}' \
  -- ${APP_ARGS} -m '${PORTMAP}'"

# Just in case, ensure we end with a newline and restored TTY
printf '\n' || true
