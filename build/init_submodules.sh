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
DISABLE_DRIVERS="${DISABLE_DRIVERS:-crypto/*,raw/*,baseband/*,dma/*,net/af_packet,net/af_xdp,net/ark,net/atlantic,net/avp,net/axgbe,net/bnx2x,net/bnxt,net/bonding,net/cnxk,net/cxgbe,net/dpaa,net/dpaa2,net/e1000,net/ena,net/enetc,net/enetfec,net/enic,net/fm10k,net/hinic,net/hns3,net/iavf,net/ice,net/igc,net/ionic,net/ipn3ke,net/kni,net/liquidio,net/memif,net/mlx4,net/mvneta,net/mvpp2,net/nfb,net/nfp,net/ngbe,net/octeontx,net/octeontx_ep,net/pcap,net/pfe,net/qede,net/softnic,net/thunderx,net/txgbe,net/vdev_netvsc,net/vhost,net/virtio,net/vmxnet3}"

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
# PCM settings
# -----------------------
PCM_DIR="${PCM_DIR:-pcm}"
PCM_BUILD="${PCM_BUILD:-${PCM_DIR}/build}"

# -----------------------
CORES="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 8)"
CMD="${1:-build}"

need() { command -v "$1" >/dev/null || { echo "Missing dependency: $1"; exit 1; }; }

# -----------------------
# DPDK helpers
# -----------------------
sync_dpdk() {
  git submodule update --init --recursive "$DPDK_DIR"
  # Checkout autokernel branch if exists (avoid detached HEAD)
  if git -C "$DPDK_DIR" rev-parse --verify autokernel >/dev/null 2>&1; then
    echo ">> checking out autokernel branch in $DPDK_DIR"
    git -C "$DPDK_DIR" checkout autokernel
  fi
}

reset_dpdk() {
  echo ">> cleaning build artifacts: $DPDK_DIR"
  git -C "$DPDK_DIR" clean -fdx -e '*.c' -e '*.h' -e '*.cpp' -e 'Makefile' -e 'meson.build'
}

build_dpdk() {
  echo ">> meson setup (prefix=$DPDK_PREFIX, examples=l3fwd)"
  pushd "$DPDK_DIR" >/dev/null
  rm -rf build
  mkdir -p build
  
  # Prepare debug flags if environment variables are set
  DEBUG_CFLAGS=""
  if [ "${RTE_LIBRTE_ETHDEV_DEBUG:-}" = "1" ]; then
    DEBUG_CFLAGS="${DEBUG_CFLAGS} -DRTE_LIBRTE_ETHDEV_DEBUG"
    echo ">> ETHDEV debug enabled (TX + RX)"
  fi
  
  # Setup meson with debug flags if any
  if [ -n "$DEBUG_CFLAGS" ]; then
    echo ">> Building with debug flags: $DEBUG_CFLAGS"
    
    # Set environment variables for meson/ninja
    export CFLAGS="$DEBUG_CFLAGS"
    export CPPFLAGS="$DEBUG_CFLAGS"
    
    meson setup build \
      -Dprefix="$PWD/build" \
      -Ddisable_drivers="$DISABLE_DRIVERS" \
      -Dc_args="$DEBUG_CFLAGS" \
      -Dcpp_args="$DEBUG_CFLAGS" \
      $DPDK_MESON_FLAGS
    
    # Build with environment variables set
    CFLAGS="$DEBUG_CFLAGS" CPPFLAGS="$DEBUG_CFLAGS" ninja -C build -j"$CORES"
    CFLAGS="$DEBUG_CFLAGS" CPPFLAGS="$DEBUG_CFLAGS" ninja -C build examples/dpdk-l3fwd
    CFLAGS="$DEBUG_CFLAGS" CPPFLAGS="$DEBUG_CFLAGS" ninja -C build install
    
    unset CFLAGS CPPFLAGS
  else
    meson setup build \
      -Dprefix="$PWD/build" \
      -Ddisable_drivers="$DISABLE_DRIVERS" \
      $DPDK_MESON_FLAGS
    
    ninja -C build -j"$CORES"
    ninja -C build examples/dpdk-l3fwd
    ninja -C build install
  fi
  popd >/dev/null
  echo ">> done. libdpdk installed under: $DPDK_PREFIX"
}

build_l3fwd() {
  # First ensure PCM is built
  echo ">> ensuring PCM is built for L3FWD integration"
  sync_pcm
  if [ ! -f "${PCM_DIR}/build/src/libpcm.a" ]; then
    build_pcm
  else
    echo ">> PCM already built"
  fi
  
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
  # Checkout autokernel branch if exists (avoid detached HEAD)
  if git -C "$PKTGEN_DIR" rev-parse --verify autokernel >/dev/null 2>&1; then
    echo ">> checking out autokernel branch in $PKTGEN_DIR"
    git -C "$PKTGEN_DIR" checkout autokernel
  fi
}

reset_pktgen() {
  echo ">> cleaning build artifacts: $PKTGEN_DIR"
  git -C "$PKTGEN_DIR" clean -fdx -e '*.c' -e '*.h' -e '*.cpp' -e 'Makefile' -e 'meson.build' -e '*.lua'
  rm -rf "$PKTGEN_BUILD"
}

export_dpdk_env() {
  export PKG_CONFIG_PATH="${DPDK_PREFIX}/lib/pkgconfig:${DPDK_PREFIX}/lib/x86_64-linux-gnu/pkgconfig:${PKG_CONFIG_PATH:-}"
  export LD_LIBRARY_PATH="${DPDK_PREFIX}/lib:${DPDK_PREFIX}/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"
}

build_pktgen() {
  echo ">> building Pktgen-DPDK (using DPDK at ${DPDK_PREFIX})"
  export_dpdk_env
  pushd "$PKTGEN_DIR" >/dev/null

  # Check if debug flags should be applied to Pktgen too
  DEBUG_CFLAGS=""
  if [ "${RTE_LIBRTE_ETHDEV_DEBUG:-}" = "1" ]; then
    DEBUG_CFLAGS="-DRTE_LIBRTE_ETHDEV_DEBUG"
    echo ">> Building Pktgen with ETHDEV debug flags: $DEBUG_CFLAGS"
  fi

  # Use local 'build' dir inside Pktgen-DPDK
  if [ ! -f "build/meson-private/coredata.dat" ]; then
    if [ -n "$DEBUG_CFLAGS" ]; then
      meson setup build $PKTGEN_MESON_FLAGS -Dc_args="$DEBUG_CFLAGS" -Dcpp_args="$DEBUG_CFLAGS"
    else
      meson setup build $PKTGEN_MESON_FLAGS
    fi
  else
    if [ -n "$DEBUG_CFLAGS" ]; then
      meson setup build $PKTGEN_MESON_FLAGS --reconfigure -Dc_args="$DEBUG_CFLAGS" -Dcpp_args="$DEBUG_CFLAGS"
    else
      meson setup build $PKTGEN_MESON_FLAGS --reconfigure
    fi
  fi
  
  meson configure build -Denable_lua=true
  
  # Build with debug flags if needed
  if [ -n "$DEBUG_CFLAGS" ]; then
    CFLAGS="$DEBUG_CFLAGS" CPPFLAGS="$DEBUG_CFLAGS" ninja -C build -j"$CORES"
  else
    ninja -C build -j"$CORES"
  fi

  popd >/dev/null
  echo ">> done. pktgen binary at: ${PKTGEN_DIR}/build/app/pktgen"
}

# -----------------------
# PCM helpers
# -----------------------
sync_pcm() {
  git submodule update --init --recursive "$PCM_DIR"
}

reset_pcm() {
  echo ">> reset/clean submodule: $PCM_DIR"
  git -C "$PCM_DIR" reset --hard
  git -C "$PCM_DIR" clean -fdx
}

build_pcm() {
  echo ">> building PCM static library"
  pushd "$PCM_DIR" >/dev/null
  
  # Create build directory and configure with CMake
  mkdir -p build
  cd build
  
  # Configure and build PCM
  cmake ..
  make -j"$CORES"
  
  popd >/dev/null
  echo ">> done. PCM static library at: ${PCM_DIR}/build/src/libpcm.a"
}


# -----------------------
# Main
# -----------------------
# ... Keep the above functions as is, only extending the case statement ...
case "$CMD" in
  build)
    need git; need meson; need ninja
    # PCM (must be built before DPDK since l3fwd depends on it)
    sync_pcm
    if [ ! -f "${PCM_DIR}/build/src/libpcm.a" ]; then
      build_pcm
    else
      echo ">> PCM already built, skipping"
    fi
    # DPDK
    sync_dpdk
    reset_dpdk
    build_dpdk
    # Pktgen
    sync_pktgen
    reset_pktgen
    build_pktgen
    echo ""
    echo ">> Build complete!"
    echo ">> Environment setup:"
    echo "   export PKG_CONFIG_PATH=\"${DPDK_PREFIX}/lib/pkgconfig:${DPDK_PREFIX}/lib/x86_64-linux-gnu/pkgconfig:\$PKG_CONFIG_PATH\""
    echo "   export LD_LIBRARY_PATH=\"${DPDK_PREFIX}/lib:${DPDK_PREFIX}/lib/x86_64-linux-gnu:\$LD_LIBRARY_PATH\""
    ;;
  l3fwd)
    need git; need meson; need ninja
    sync_dpdk
    build_l3fwd
    ;;
  clean)
    sync_dpdk
    reset_dpdk
    rm -rf "$DPDK_BUILD"
    sync_pktgen
    reset_pktgen
    rm -rf "$PKTGEN_BUILD"
    sync_pcm
    reset_pcm
    rm -rf "$PCM_BUILD"
    echo ">> Cleaned all build directories"
    ;;
  *)
    echo "usage: $0 {build|l3fwd|clean}"
    exit 1
    ;;
esac

