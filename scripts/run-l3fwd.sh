#!/usr/bin/env bash
set -euo pipefail
trap 'echo "!! ERROR: ${BASH_SOURCE[0]}:${LINENO}: \"$BASH_COMMAND\" failed" >&2' ERR

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DPDK_PREFIX="${REPO_ROOT}/dpdk/build"
L3FWD_BIN="${DPDK_PREFIX}/examples/dpdk-l3fwd"

# EAL & app params (override via env)
EAL_LCORES="${EAL_LCORES:--l 0}"
EAL_MEMCH="${EAL_MEMCH:--n 4}"
PCI_ADDR="${PCI_ADDR:-0000:31:00.1}"
APP_ARGS='-p 0x1 --config="(0,0,0)" --eth-dest=0,08:c0:eb:b6:cd:5d'

# Ensure dpdk+l3fwd are built
if [ ! -x "$L3FWD_BIN" ]; then
  echo ">> l3fwd binary not found, building..."
  make -C "$REPO_ROOT" submodules
fi
[ -x "$L3FWD_BIN" ] || { echo "l3fwd not found after build: $L3FWD_BIN"; exit 1; }

# Runtime env (preserved by sudo -E)
export PKG_CONFIG_PATH="${DPDK_PREFIX}/lib/pkgconfig:${DPDK_PREFIX}/lib/x86_64-linux-gnu/pkgconfig:${PKG_CONFIG_PATH:-}"
export LD_LIBRARY_PATH="${DPDK_PREFIX}/lib:${DPDK_PREFIX}/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"

echo ">> running l3fwd:"
echo "   binary: ${L3FWD_BIN}"
echo "   EAL   : ${EAL_LCORES} ${EAL_MEMCH} -a ${PCI_ADDR}"
echo "   args  : ${APP_ARGS}"

sudo -E "${L3FWD_BIN}" \
  ${EAL_LCORES} ${EAL_MEMCH} -a "${PCI_ADDR}" -- \
  ${APP_ARGS}
