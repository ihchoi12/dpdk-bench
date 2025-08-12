#!/usr/bin/env bash
set -euo pipefail
trap 'echo "!! ERROR: ${BASH_SOURCE[0]}:${LINENO}: \"$BASH_COMMAND\" failed" >&2' ERR

# repo root (this script lives in build/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ---- settings ----
DPDK_DIR="${DPDK_DIR:-dpdk}"
DPDK_BUILD="${DPDK_BUILD:-$DPDK_DIR/build}"
DPDK_PREFIX="${DPDK_PREFIX:-$(pwd)/$DPDK_BUILD}"
# Build only what we need; add examples=l3fwd here
DPDK_MESON_FLAGS="${DPDK_MESON_FLAGS:--Dtests=false -Denable_kmods=false -Dexamples=l3fwd}"

# Disable most drivers to keep build small; keep mlx5
DISABLE_DRIVERS="${DISABLE_DRIVERS:-crypto/*,raw/*,baseband/*,dma/*,net/af_packet,net/af_xdp,net/ark,net/atlantic,net/avp,net/axgbe,net/bnx2x,net/bnxt,net/bonding,net/cnxk,net/cxgbe,net/dpaa,net/dpaa2,net/e1000,net/ena,net/enetc,net/enetfec,net/enic,net/fm10k,net/hinic,net/hns3,net/iavf,net/ice,net/igc,net/ionic,net/ipn3ke,net/kni,net/liquidio,net/memif,net/mlx4,net/mvneta,net/mvpp2,net/nfb,net/nfp,net/ngbe,net/octeontx,net/octeontx_ep,net/pcap,net/pfe,net/qede,net/sfc,net/softnic,net/thunderx,net/txgbe,net/vdev_netvsc,net/vhost,net/virtio,net/vmxnet3}"

# make these absolute by default
DPDK_PATCH_SERIES="${DPDK_PATCH_SERIES:-${REPO_ROOT}/build/patches/dpdk}"
DPDK_PATCH_SINGLE="${DPDK_PATCH_SINGLE:-${REPO_ROOT}/build/dpdk.patch}"


CORES="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 8)"
CMD="${1:-build}"

need() { command -v "$1" >/dev/null || { echo "Missing dependency: $1"; exit 1; }; }

sync_submodule() {
  git submodule update --init --recursive "$DPDK_DIR"
}

reset_submodule() {
  echo ">> reset/clean submodule: $DPDK_DIR"
  git -C "$DPDK_DIR" reset --hard
  git -C "$DPDK_DIR" clean -fdx
}

apply_patches() {
  # normalize to absolute paths if inputs are relative
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


meson_build() {
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
  echo ">> tip: export PKG_CONFIG_PATH=\"$DPDK_PREFIX/lib/pkgconfig:$DPDK_PREFIX/lib/x86_64-linux-gnu/pkgconfig:\$PKG_CONFIG_PATH\""
  echo ">> tip: export LD_LIBRARY_PATH=\"$DPDK_PREFIX/lib:$DPDK_PREFIX/lib/x86_64-linux-gnu:\$LD_LIBRARY_PATH\""
}

case "$CMD" in
  build)
    need git; need meson; need ninja
    sync_submodule
    reset_submodule
    apply_patches
    meson_build
    ;;
  clean)
    sync_submodule
    reset_submodule
    rm -rf "$DPDK_BUILD"
    echo ">> cleaned: $DPDK_BUILD"
    ;;
  *)
    echo "usage: $0 {build|clean}"
    exit 1
    ;;
esac
