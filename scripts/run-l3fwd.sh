#!/usr/bin/env bash
# Source common header for DPDK scripts
source "$(dirname "${BASH_SOURCE[0]}")/common-header.sh"

# L3FWD specific configuration
L3FWD_BIN="${L3FWD_BIN:-${DPDK_PREFIX}/examples/dpdk-l3fwd}"

# Load parameters from config file (can be overridden by environment)
EAL_LCORES="${EAL_LCORES:-${L3FWD_LCORES:--l 0-2}}"
EAL_MEMCH="${EAL_MEMCH:-${L3FWD_MEMCH:--n 4}}"
PCI_ADDR="${PCI_ADDR:-${L3FWD_PCI_ADDR:-0000:31:00.1}}"
PORT_MASK="${PORT_MASK:-${L3FWD_PORT_MASK:--p 0x1}}"
CONFIG_STR="${CONFIG_STR:-${L3FWD_CONFIG:-(0,0,0),(0,1,1),(0,2,2)}}"
ETH_DEST="${ETH_DEST:-${L3FWD_ETH_DEST:-08:c0:eb:b6:cd:5d}}"

# Build complete APP_ARGS
APP_ARGS="${PORT_MASK} --config=\"${CONFIG_STR}\" --eth-dest=0,${ETH_DEST}"

# Ensure dpdk+l3fwd are built
check_binary "$L3FWD_BIN" "l3fwd"

echo ">> running l3fwd:"
echo "   binary: ${L3FWD_BIN}"
echo "   EAL   : ${EAL_LCORES} ${EAL_MEMCH} -a ${PCI_ADDR}"
echo "   args  : ${APP_ARGS}"

# Build the complete command for debugging
FULL_COMMAND="'${L3FWD_BIN}' ${EAL_LCORES} ${EAL_MEMCH} -a '${PCI_ADDR}' -- ${APP_ARGS}"

echo ""
echo ">> Final command to execute:"
echo "   sudo -E ${FULL_COMMAND}"
echo ""

sudo -E "${L3FWD_BIN}" \
  ${EAL_LCORES} ${EAL_MEMCH} -a "${PCI_ADDR}" -- \
  ${APP_ARGS}
