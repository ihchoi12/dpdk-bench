#!/usr/bin/env bash
# DPDK Benchmark Suite - Interactive Entry Point
# This script provides a menu-driven interface for common operations

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for better UX
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Print header
print_header() {
    clear
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${BLUE}DPDK Benchmark Suite - Interactive Menu${NC}              ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"

    # Show cluster config
    CLUSTER_CONFIG="$SCRIPT_DIR/cluster.config"
    if [ -f "$CLUSTER_CONFIG" ]; then
        PKTGEN_NODE=$(grep "^PKTGEN_NODE=" "$CLUSTER_CONFIG" | cut -d'=' -f2)
        L3FWD_NODE=$(grep "^L3FWD_NODE=" "$CLUSTER_CONFIG" | cut -d'=' -f2)
        echo -e "  ${CYAN}Cluster:${NC} PKTGEN=${GREEN}${PKTGEN_NODE:-?}${NC} | L3FWD=${GREEN}${L3FWD_NODE:-?}${NC}  ${YELLOW}(edit cluster.config to change)${NC}"
    else
        echo -e "  ${RED}⚠ cluster.config not found${NC} ${YELLOW}(create it for multi-node tests)${NC}"
    fi
    echo ""
}

# Print menu options
print_menu() {
    echo -e "${GREEN}Available Options:${NC}"
    echo ""
    echo -e "  ${YELLOW}1)${NC} Show and Update System Configuration"
    echo -e "     ${CYAN}→${NC} Display hardware info and update config files"
    echo ""
    echo -e "  ${YELLOW}2)${NC} Initial Machine Setup"
    echo -e "     ${CYAN}→${NC} Install dependencies, setup hugepages/MSR (for new machines)"
    echo ""
    echo -e "  ${YELLOW}3)${NC} Build"
    echo -e "     ${CYAN}→${NC} Build DPDK, Pktgen, and related components"
    echo ""
    echo -e "  ${YELLOW}4)${NC} Run Simple Pktgen Test"
    echo -e "     ${CYAN}→${NC} config/simple-test/simple-test.config"
    echo ""
    echo -e "  ${YELLOW}5)${NC} Run Full Benchmark"
    echo -e "     ${CYAN}→${NC} scripts/benchmark/test_config.py"
    echo ""
    echo -e "  ${YELLOW}6)${NC} DDIO Control"
    echo -e "     ${CYAN}→${NC} Enable/Disable DDIO, adjust LLC ways"
    echo ""
    echo -e "  ${YELLOW}0)${NC} Exit"
    echo ""
    echo -e "${GREEN}────────────────────────────────────────────────────────────${NC}"
}

# Option 1: Show and update system configuration
option_system_config() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  System Configuration${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""

    # Run get_system_info.sh
    if [ -f "./scripts/utils/get_system_info.sh" ]; then
        ./scripts/utils/get_system_info.sh
        echo ""
        echo -e "${GREEN}✓ Configuration files updated successfully!${NC}"
        echo -e "  ${CYAN}→${NC} config/system.config"
    else
        echo -e "${RED}✗ Error: get_system_info.sh not found${NC}"
        return 1
    fi

    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
}

# Option 2: Initial Machine Setup
option_initial_setup() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Initial Machine Setup${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${CYAN}This will install dependencies and configure the system for DPDK.${NC}"
    echo -e "${YELLOW}Note: Some steps require sudo privileges.${NC}"
    echo ""

    # Step 1: Install system dependencies
    echo -e "${GREEN}[1/4] Installing system dependencies...${NC}"
    echo ""
    sudo apt update && sudo apt install -y \
        meson ninja-build build-essential pkg-config git \
        libnuma-dev libpcap-dev python3-pyelftools liblua5.3-dev \
        libibverbs-dev librdmacm-dev rdma-core ibverbs-providers libmlx5-1 \
        libelf-dev libbsd-dev zlib1g-dev libpci-dev \
        python3-pip python3-dev ethtool wget gpg apt-transport-https

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ System dependencies installed successfully${NC}"
    else
        echo -e "${RED}✗ Failed to install system dependencies${NC}"
        return 1
    fi
    echo ""

    # Step 2: Install/Upgrade CMake (Meson requires >= 3.17)
    echo -e "${GREEN}[2/4] Upgrading CMake...${NC}"
    echo ""
    CMAKE_VERSION=$(cmake --version 2>/dev/null | head -1 | awk '{print $3}')
    CMAKE_MAJOR=$(echo "$CMAKE_VERSION" | cut -d. -f1)
    CMAKE_MINOR=$(echo "$CMAKE_VERSION" | cut -d. -f2)

    if [ -z "$CMAKE_VERSION" ] || [ "$CMAKE_MAJOR" -lt 3 ] || ([ "$CMAKE_MAJOR" -eq 3 ] && [ "$CMAKE_MINOR" -lt 17 ]); then
        echo -e "${CYAN}Current CMake: ${CMAKE_VERSION:-not installed}. Installing latest from Kitware...${NC}"
        # Add Kitware APT repository for latest CMake
        wget -qO - https://apt.kitware.com/keys/kitware-archive-latest.asc 2>/dev/null | gpg --dearmor - | sudo tee /usr/share/keyrings/kitware-archive-keyring.gpg >/dev/null
        UBUNTU_CODENAME=$(lsb_release -cs)
        echo "deb [signed-by=/usr/share/keyrings/kitware-archive-keyring.gpg] https://apt.kitware.com/ubuntu/ $UBUNTU_CODENAME main" | sudo tee /etc/apt/sources.list.d/kitware.list >/dev/null
        sudo apt update && sudo apt install -y cmake
        echo -e "${GREEN}✓ CMake upgraded to $(cmake --version | head -1 | awk '{print $3}')${NC}"
    else
        echo -e "${GREEN}✓ CMake $CMAKE_VERSION already meets requirements (>= 3.17)${NC}"
    fi
    echo ""

    # Step 3: Install Python dependencies
    echo -e "${GREEN}[3/4] Installing Python dependencies...${NC}"
    echo ""
    pip3 install --user --break-system-packages numpy pandas matplotlib cycler pyrem 2>/dev/null || \
    pip3 install --user numpy pandas matplotlib cycler pyrem

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Python dependencies installed successfully${NC}"
    else
        echo -e "${YELLOW}⚠ Some Python dependencies may have failed${NC}"
    fi
    echo ""

    # Step 4: Machine setup (hugepages, MSR)
    echo -e "${GREEN}[4/4] Running machine setup (hugepages, MSR)...${NC}"
    echo ""
    if [ -f "./scripts/setup/setup_machines.sh" ]; then
        sudo ./scripts/setup/setup_machines.sh
    elif [ -f "./scripts/setup_machines.sh" ]; then
        sudo ./scripts/setup_machines.sh
    else
        echo -e "${YELLOW}⚠ setup_machines.sh not found, skipping...${NC}"
    fi
    echo ""

    # Verify PCM setup
    echo -e "${BLUE}───────────────────────────────────────────────────────────${NC}"
    echo -e "${BLUE}  Verifying PCM Setup${NC}"
    echo -e "${BLUE}───────────────────────────────────────────────────────────${NC}"
    echo ""

    echo -e "${CYAN}Checking MSR module...${NC}"
    if lsmod | grep -q msr; then
        echo -e "${GREEN}✓ MSR module is loaded${NC}"
    else
        echo -e "${YELLOW}⚠ MSR module not loaded. Loading now...${NC}"
        sudo modprobe msr
        if lsmod | grep -q msr; then
            echo -e "${GREEN}✓ MSR module loaded successfully${NC}"
        else
            echo -e "${RED}✗ Failed to load MSR module${NC}"
        fi
    fi
    echo ""

    echo -e "${CYAN}Checking /dev/cpu/0/msr...${NC}"
    if [ -e /dev/cpu/0/msr ]; then
        echo -e "${GREEN}✓ /dev/cpu/0/msr exists${NC}"
    else
        echo -e "${RED}✗ /dev/cpu/0/msr not found${NC}"
        echo -e "  ${CYAN}→${NC} Try: sudo modprobe msr"
    fi
    echo ""

    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}✓ Initial setup completed!${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
}

# Option 3: Build
option_build() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Build Options${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${YELLOW}1)${NC} Full Build (PCM + NeoHost + DPDK + Pktgen + DDIO)"
    echo -e "     ${CYAN}→${NC} make clean-all && make build-all + ddio-modify rebuild"
    echo -e "       (for new machines or profiling tool updates)"
    echo ""
    echo -e "  ${YELLOW}2)${NC} DPDK + Pktgen Clean-Rebuild"
    echo -e "     ${CYAN}→${NC} make clean && make build"
    echo ""
    echo -e "  ${YELLOW}3)${NC} DPDK + Pktgen Clean-Rebuild (Debug Mode)"
    echo -e "     ${CYAN}→${NC} make clean && make build-debug"
    echo ""
    echo -e "  ${YELLOW}4)${NC} Light Rebuild"
    echo -e "     ${CYAN}→${NC} pktgen-rebuild / l3fwd-rebuild"
    echo -e "       (incremental build for app changes only)"
    echo ""
    echo -e "  ${YELLOW}0)${NC} Back to Main Menu"
    echo ""
    echo -e "${GREEN}────────────────────────────────────────────────────────────${NC}"

    read -p "$(echo -e ${CYAN}Select build option:${NC} )" build_choice

    case $build_choice in
        1)
            echo ""
            echo -e "${BLUE}>> Running make clean-all...${NC}"
            make clean-all
            echo ""
            echo -e "${BLUE}>> Running make build-all...${NC}"
            make build-all
            echo ""
            echo -e "${BLUE}>> Rebuilding ddio-modify for this machine...${NC}"
            DDIO_DIR="$SCRIPT_DIR/ddio-modify"
            if [ -d "$DDIO_DIR" ]; then
                rm -rf "$DDIO_DIR/build"
                mkdir -p "$DDIO_DIR/build"
                cd "$DDIO_DIR/build" && cmake .. && make
                cd "$SCRIPT_DIR"
                echo -e "${GREEN}✓ ddio-modify rebuilt successfully${NC}"
            else
                echo -e "${YELLOW}⚠ ddio-modify directory not found, skipping${NC}"
            fi
            echo ""
            echo -e "${GREEN}✓ Full build completed!${NC}"
            ;;
        2)
            echo ""
            echo -e "${BLUE}>> Running make clean...${NC}"
            make clean
            echo ""
            echo -e "${BLUE}>> Running make build...${NC}"
            make build
            echo ""
            echo -e "${GREEN}✓ DPDK + Pktgen build completed!${NC}"
            ;;
        3)
            echo ""
            echo -e "${BLUE}>> Running make clean...${NC}"
            make clean
            echo ""
            echo -e "${BLUE}>> Running make build-debug (TX/RX debug enabled)...${NC}"
            make build-debug
            echo ""
            echo -e "${GREEN}✓ DPDK + Pktgen debug build completed!${NC}"
            ;;
        4)
            echo ""
            echo -e "${BLUE}>> Running make pktgen-rebuild...${NC}"
            make pktgen-rebuild
            echo ""
            echo -e "${BLUE}>> Running make l3fwd-rebuild...${NC}"
            make l3fwd-rebuild
            echo ""
            echo -e "${GREEN}✓ Light rebuild completed (Pktgen + L3FWD)!${NC}"
            ;;
        0)
            return
            ;;
        *)
            echo -e "${RED}Invalid option.${NC}"
            ;;
    esac
}

# Option 3: Run Simple Pktgen Test
option_simple_test() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Simple Pktgen Test${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${CYAN}Script: config/simple-test/simple-pktgen-test.lua${NC}"
    echo -e "${CYAN}Log: results/simple-pktgen-test.log${NC}"
    echo ""

    make run-simple-pktgen-test

    echo ""
    echo -e "${GREEN}✓ Test completed! Log saved to results/simple-pktgen-test.log${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
}

# Option 4: Run Full Benchmark
option_full_benchmark() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Full Benchmark${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${CYAN}Config: scripts/benchmark/test_config.py${NC}"
    echo -e "${CYAN}Results: results/${NC}"
    echo ""

    make run-full-benchmark

    echo ""
    echo -e "${GREEN}✓ Benchmark completed! Results saved to results/${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
}

# Option 5: DDIO Control
option_ddio_control() {
    DDIO_BIN="$SCRIPT_DIR/ddio-modify/build/ddio_modify"
    SYSTEM_CONFIG="$SCRIPT_DIR/config/system.config"

    if [ ! -x "$DDIO_BIN" ]; then
        echo -e "${RED}✗ Error: ddio_modify not found or not built${NC}"
        echo -e "  ${CYAN}→${NC} Build with: cd ddio-modify && mkdir -p build && cd build && cmake .. && make"
        return 1
    fi

    # Check system.config exists
    if [ ! -f "$SYSTEM_CONFIG" ]; then
        echo -e "${RED}✗ Error: config/system.config not found${NC}"
        echo -e "  ${CYAN}→${NC} Run option 1 (Show and Update System Configuration) first"
        return 1
    fi

    # Read NIC info from system.config
    NIC_PCI=$(grep "^PKTGEN_NIC_PCI=" "$SYSTEM_CONFIG" | cut -d'=' -f2)
    NIC_MAC=$(grep "^PKTGEN_NIC_MAC=" "$SYSTEM_CONFIG" | cut -d'=' -f2)
    NIC_IP=$(grep "^PKTGEN_NIC_IP=" "$SYSTEM_CONFIG" | cut -d'=' -f2)

    if [ -z "$NIC_PCI" ]; then
        echo -e "${RED}✗ Error: PKTGEN_NIC_PCI not configured in system.config${NC}"
        echo -e "  ${CYAN}→${NC} Run option 1 (Show and Update System Configuration) first"
        return 1
    fi

    # Extract bus from PCI address (format: 0000:XX:00.0)
    NIC_BUS=$(echo "$NIC_PCI" | cut -d':' -f2)

    # Display NIC info
    echo ""
    echo -e "${BLUE}───────────────────────────────────────────────────────────${NC}"
    echo -e "${BLUE}  Target NIC Configuration${NC}"
    echo -e "${BLUE}───────────────────────────────────────────────────────────${NC}"
    echo -e "  PCI Address: ${GREEN}$NIC_PCI${NC}"
    echo -e "  MAC Address: ${GREEN}${NIC_MAC:-N/A}${NC}"
    echo -e "  IP Address:  ${GREEN}${NIC_IP:-N/A}${NC}"
    echo -e "${BLUE}───────────────────────────────────────────────────────────${NC}"
    echo ""

    sudo "$DDIO_BIN" "0x$NIC_BUS"
}

# Wait for user to press Enter
press_enter() {
    echo ""
    read -p "Press Enter to continue..."
}

# Main menu loop
main_menu() {
    while true; do
        print_header
        print_menu

        # Read user choice
        read -p "$(echo -e ${CYAN}Select an option:${NC} )" choice

        case $choice in
            1)
                option_system_config
                press_enter
                ;;
            2)
                option_initial_setup
                press_enter
                ;;
            3)
                option_build
                press_enter
                ;;
            4)
                option_simple_test
                press_enter
                ;;
            5)
                option_full_benchmark
                press_enter
                ;;
            6)
                option_ddio_control
                press_enter
                ;;
            0)
                echo ""
                echo -e "${GREEN}Exiting... Goodbye!${NC}"
                echo ""
                exit 0
                ;;
            *)
                echo ""
                echo -e "${RED}Invalid option. Please try again.${NC}"
                sleep 1
                ;;
        esac
    done
}

# Check if running with proper permissions
check_requirements() {
    # Check if ethtool is available (needed for get_system_info.sh)
    if ! command -v ethtool &> /dev/null; then
        echo -e "${YELLOW}Warning: ethtool not found. Some network info may be unavailable.${NC}"
        echo -e "${YELLOW}Install with: sudo apt-get install ethtool${NC}"
        echo ""
        read -p "Continue anyway? (y/n): " continue_choice
        if [[ ! "$continue_choice" =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Entry point
check_requirements
main_menu
