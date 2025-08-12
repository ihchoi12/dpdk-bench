#!/usr/bin/env bash
set -euo pipefail
trap 'echo "!! ERROR: ${BASH_SOURCE[0]}:${LINENO}: \"$BASH_COMMAND\" failed" >&2' ERR

# repo root (this script lives in build/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# -----------------------
# DPDK settings
# -----------------------
DPDK_DIR="${DPDK_DIR:-dpdk}"
DPDK_BUILD="${DPDK_BUILD:-$DPDK_DIR/build}"
DPDK_PREFIX="${DPDK_PREFIX:-${REPO_ROOT}/${DPDK_BUILD}}"
DPDK_MESON_FLAGS="${DPDK_MESON_FLAGS:--Dtests=false -Denable_kmods=false -Dexamples=l3fwd}"

# Disable most drivers to keep build small; keep mlx5
DISABLE_DRIVERS="${DISABLE_DRIVERS:-crypto/*,raw/*,baseband/*,dma/*,net/af_packet,net/af_xdp,net/ark,net/atlantic,net/avp,net/axgbe,net/bnx2x,net/bnxt,net/bonding,net/cnxk,net/cxgbe,net/dpaa,net/dpaa2,net/e1000,net/ena,net/enetc,net/enetfec,net/enic,net/fm10k,net/hinic,net/hns3,net/iavf,net/ice,net/igc,net/ionic,net/ipn3ke,net/kni,net/liquidio,net/memif,net/mlx4,net/mvneta,net/mvpp2,net/nfb,net/nfp,net/ngbe,net/octeontx,net/octeontx_ep,net/pcap,net/pfe,net/qede,net/sfc,net/softnic,net/thunderx,net/txgbe,net/vdev_netvsc,net/vhost,net/virtio,net/vmxnet3}"

# make these absolute by default
DPDK_PATCH_SERIES="${DPDK_PATCH_SERIES:-${REPO_ROOT}/build/patches/dpdk}"
DPDK_PATCH_SINGLE="${DPDK_PATCH_SINGLE:-${REPO_ROOT}/build/dpdk.patch}"

# -----------------------
# Pktgen settings
# -----------------------
PKTGEN_DIR="${PKTGEN_DIR:-Pktgen-DPDK}"
PKTGEN_BUILD="${PKTGEN_BUILD:-${PKTGEN_DIR}/build}"
PKTGEN_MESON_FLAGS="${PKTGEN_MESON_FLAGS:--Denable_lua=true}"

PKTGEN_PATCH_SERIES="${PKTGEN_PATCH_SERIES:-${REPO_ROOT}/build/patches/pktgen}"
PKTGEN_PATCH_SINGLE="${PKTGEN_PATCH_SINGLE:-${REPO_ROOT}/build/pktgen.patch}"

# -----------------------
CORES="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 8)"
CMD="${1:-build}"

need() { command -v "$1" >/dev/null || { echo "Missing dependency: $1"; exit 1; }; }

# -----------------------
# DPDK helpers
# -----------------------
sync_dpdk() {
  git submodule update --init --recursive "$DPDK_DIR"
}

reset_dpdk() {
  echo ">> reset/clean submodule: $DPDK_DIR"
  git -C "$DPDK_DIR" reset --hard
  git -C "$DPDK_DIR" clean -fdx
}

apply_dpdk_patches() {
  local SERIES="$DPDK_PATCH_SERIES"
  local SINGLE="$DPDK_PATCH_SINGLE"
  [[ "$SERIES" = /* ]] || SERIES="${REPO_ROOT}/${SERIES}"
  [[ "$SINGLE" = /* ]] || SINGLE="${REPO_ROOT}/${SINGLE}"

  if [ -d "$SERIES" ] && ls "$SERIES"/*.patch >/dev/null 2>&1; then
    echo ">> applying patch series: $SERIES/*.patch"
    git -C "$DPDK_DIR" -c user.name="x" -c user.email="x" am --3way --whitespace=fix $(ls "$SERIES"/*.patch | sort)
  elif [ -f "$SINGLE" ]; then
    echo ">> applying single patch: $SINGLE"
    git -C "$DPDK_DIR" apply --whitespace=fix "$SINGLE"
  else
    echo ">> no dpdk patches found (building vanilla submodule)"
  fi
}

build_dpdk() {
  echo ">> meson setup (prefix=$DPDK_PREFIX, examples=l3fwd)"
  pushd "$DPDK_DIR" >/dev/null
  rm -rf build
  mkdir -p build
  meson setup build \
    -Dprefix="$PWD/build" \
    -Ddisable_drivers="$DISABLE_DRIVERS" \
    $DPDK_MESON_FLAGS
  ninja -C build -j"$CORES"
  ninja -C build examples/dpdk-l3fwd
  ninja -C build install
  popd >/dev/null
  echo ">> done. libdpdk installed under: $DPDK_PREFIX"
}

build_l3fwd() {
  pushd "$DPDK_DIR" >/dev/null
  if [ ! -d build ]; then
    echo ">> DPDK build/ not found; doing full DPDK build first"
    popd >/dev/null
    build_dpdk
    return
  fi
  # ensure l3fwd is enabled and rebuild just the example
  meson setup build -Dprefix="$PWD/build" -Ddisable_drivers="$DISABLE_DRIVERS" $DPDK_MESON_FLAGS --reconfigure
  meson configure build -Dexamples=l3fwd
  ninja -C build examples/dpdk-l3fwd
  popd >/dev/null
}

# -----------------------
# Pktgen helpers
# -----------------------
sync_pktgen() {
  git submodule update --init --recursive "$PKTGEN_DIR"
}

reset_pktgen() {
  echo ">> reset/clean submodule: $PKTGEN_DIR"
  git -C "$PKTGEN_DIR" reset --hard
  git -C "$PKTGEN_DIR" clean -fdx
  rm -rf "$PKTGEN_BUILD"
}

apply_pktgen_patches() {
  local SERIES="$PKTGEN_PATCH_SERIES"
  local SINGLE="$PKTGEN_PATCH_SINGLE"
  [[ "$SERIES" = /* ]] || SERIES="${REPO_ROOT}/${SERIES}"
  [[ "$SINGLE" = /* ]] || SINGLE="${REPO_ROOT}/${SINGLE}"

  if [ -d "$SERIES" ] && ls "$SERIES"/*.patch >/dev/null 2>&1; then
    echo ">> applying pktgen patch series: $SERIES/*.patch"
    git -C "$PKTGEN_DIR" -c user.name="x" -c user.email="x" am --3way --whitespace=fix $(ls "$SERIES"/*.patch | sort)
  elif [ -f "$SINGLE" ]; then
    echo ">> applying pktgen single patch: $SINGLE"
    git -C "$PKTGEN_DIR" apply --whitespace=fix "$SINGLE"
  else
    echo ">> no pktgen patches found (building vanilla submodule)"
  fi
}

export_dpdk_env() {
  export PKG_CONFIG_PATH="${DPDK_PREFIX}/lib/pkgconfig:${DPDK_PREFIX}/lib/x86_64-linux-gnu/pkgconfig:${PKG_CONFIG_PATH:-}"
  export LD_LIBRARY_PATH="${DPDK_PREFIX}/lib:${DPDK_PREFIX}/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"
}

build_pktgen() {
  echo ">> building Pktgen-DPDK (using DPDK at ${DPDK_PREFIX})"
  export_dpdk_env
  pushd "$PKTGEN_DIR" >/dev/null

  # Use local 'build' dir inside Pktgen-DPDK
  if [ ! -f "build/meson-private/coredata.dat" ]; then
    meson setup build $PKTGEN_MESON_FLAGS
  else
    meson setup build $PKTGEN_MESON_FLAGS --reconfigure
  fi
  meson configure build -Denable_lua=true
  ninja -C build -j"$CORES"

  popd >/dev/null
  echo ">> done. pktgen binary at: ${PKTGEN_DIR}/build/app/pktgen"
}


# -----------------------
# Main
# -----------------------
# ... 상단/함수들은 그대로 두고, case 문만 확장 ...
case "$CMD" in
  build)
    need git; need meson; need ninja
    # DPDK
    sync_dpdk
    reset_dpdk
    apply_dpdk_patches
    build_dpdk
    # Pktgen
    sync_pktgen
    reset_pktgen
    apply_pktgen_patches
    build_pktgen
    echo ">> tip: export PKG_CONFIG_PATH=\"${DPDK_PREFIX}/lib/pkgconfig:${DPDK_PREFIX}/lib/x86_64-linux-gnu/pkgconfig:\$PKG_CONFIG_PATH\""
    echo ">> tip: export LD_LIBRARY_PATH=\"${DPDK_PREFIX}/lib:${DPDK_PREFIX}/lib/x86_64-linux-gnu:\$LD_LIBRARY_PATH\""
    ;;
  l3fwd)
    need git; need meson; need ninja
    sync_dpdk
    build_l3fwd
    ;;
  pktgen)
    need git; need meson; need ninja
    # ensure DPDK is already built/installed to ${DPDK_PREFIX}
    if [ ! -f "${DPDK_PREFIX}/lib/pkgconfig/libdpdk.pc" ] && \
       [ ! -f "${DPDK_PREFIX}/lib/x86_64-linux-gnu/pkgconfig/libdpdk.pc" ]; then
      echo "DPDK not built at ${DPDK_PREFIX}. Run: make submodules"
      exit 1
    fi
    sync_pktgen
    reset_pktgen
    apply_pktgen_patches
    build_pktgen
    ;;
  pktgen-clean)
    sync_pktgen
    reset_pktgen
    ;;
  clean)
    # clean both submodules
    sync_dpdk
    reset_dpdk
    rm -rf "$DPDK_BUILD"
    sync_pktgen
    reset_pktgen
    echo ">> cleaned: $DPDK_BUILD and $PKTGEN_BUILD"
    ;;
  *)
    echo "usage: $0 {build|pktgen|pktgen-clean|l3fwd|clean}"
    exit 1
    ;;
esac

