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
    echo ""
}

# Print menu options
print_menu() {
    echo -e "${GREEN}Available Options:${NC}"
    echo ""
    echo -e "  ${YELLOW}1)${NC} Show and Update System Configuration"
    echo -e "     ${CYAN}→${NC} Display hardware info and update config files"
    echo ""
    echo -e "  ${YELLOW}2)${NC} Build"
    echo -e "     ${CYAN}→${NC} Build DPDK, Pktgen, and related components"
    echo ""
    echo -e "  ${YELLOW}3)${NC} Run Simple Pktgen Test"
    echo -e "     ${CYAN}→${NC} Run pktgen with simple-pktgen-test.lua"
    echo ""
    echo -e "  ${YELLOW}4)${NC} Run Full Benchmark"
    echo -e "     ${CYAN}→${NC} Run benchmark suite (see scripts/benchmark/test_config.py)"
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

# Option 2: Build
option_build() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Build Options${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${YELLOW}1)${NC} Full Build (PCM + NeoHost + DPDK + Pktgen)"
    echo -e "     ${CYAN}→${NC} make clean-all && make build-all"
    echo -e "       (for new machines or profiling tool updates)"
    echo ""
    echo -e "  ${YELLOW}2)${NC} DPDK + Pktgen Rebuild"
    echo -e "     ${CYAN}→${NC} make clean && make build"
    echo -e "       (clean rebuild, skips PCM if already built)"
    echo ""
    echo -e "  ${YELLOW}3)${NC} Light Rebuild"
    echo -e "     ${CYAN}→${NC} pktgen-rebuild / l3fwd-rebuild"
    echo -e "       (quick incremental build for app changes only)"
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
    echo -e "${CYAN}Script: config/simple-pktgen-test.lua${NC}"
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
                option_build
                press_enter
                ;;
            3)
                option_simple_test
                press_enter
                ;;
            4)
                option_full_benchmark
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
