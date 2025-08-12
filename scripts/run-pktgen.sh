#!/usr/bin/env bash
set -euo pipefail

on_error() {
  echo "!! ERROR: ${BASH_SOURCE[0]}:${LINENO}: \"$BASH_COMMAND\" failed" >&2
}

# Save current TTY state (if we have a TTY) and ensure restore on exit
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
trap 'restore_tty' EXIT INT TERM
trap 'on_error; restore_tty' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

DPDK_PREFIX="${DPDK_PREFIX:-${REPO_ROOT}/dpdk/build}"
PKTGEN_BIN="${PKTGEN_BIN:-${REPO_ROOT}/Pktgen-DPDK/build/app/pktgen}"

# Defaults (override via env)
LCORES="${LCORES:--l 0-1}"
MEMCH="${MEMCH:--n 4}"
FILE_PREFIX="${FILE_PREFIX:-pktgen1}"
PCI_ADDR="${PCI_ADDR:-0000:31:00.1}"
PORTMAP="${PORTMAP:-"[1].0"}"

# Ensure built
if [ ! -x "$PKTGEN_BIN" ]; then
  echo ">> pktgen binary not found, building..."
  make -C "$REPO_ROOT" pktgen
fi
[ -x "$PKTGEN_BIN" ] || { echo "pktgen not found after build: $PKTGEN_BIN"; exit 1; }

# Runtime env for shared libs
export PKG_CONFIG_PATH="${DPDK_PREFIX}/lib/pkgconfig:${DPDK_PREFIX}/lib/x86_64-linux-gnu/pkgconfig:${PKG_CONFIG_PATH:-}"
export LD_LIBRARY_PATH="${DPDK_PREFIX}/lib:${DPDK_PREFIX}/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"

echo ">> running pktgen:"
echo "   bin   : ${PKTGEN_BIN}"
echo "   EAL   : ${LCORES} ${MEMCH} --proc-type auto --file-prefix ${FILE_PREFIX} --allow=${PCI_ADDR}"
echo "   args  : -P -T -m \"${PORTMAP}\""

# Run under sudo while preserving env inside the root shell
sudo bash -lc "LD_LIBRARY_PATH='${LD_LIBRARY_PATH}' \
  PKG_CONFIG_PATH='${PKG_CONFIG_PATH}' \
  exec '${PKTGEN_BIN}' \
  ${LCORES} ${MEMCH} --proc-type auto --file-prefix '${FILE_PREFIX}' --allow='${PCI_ADDR}' \
  -- -P -T -m '${PORTMAP}'"

# Just in case, ensure we end with a newline and restored TTY
printf '\n' || true
