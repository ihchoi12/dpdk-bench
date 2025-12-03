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
    echo -e "  ${YELLOW}1)${NC} Full Clean Build"
    echo -e "     ${CYAN}→${NC} make clean && make submodules"
    echo -e "       (rebuilds everything from scratch)"
    echo ""
    echo -e "  ${YELLOW}2)${NC} Full Clean Build (Debug)"
    echo -e "     ${CYAN}→${NC} make clean && make submodules-debug"
    echo -e "       (rebuilds with TX/RX debug logging enabled)"
    echo ""
    echo -e "  ${YELLOW}3)${NC} Rebuild Pktgen Only"
    echo -e "     ${CYAN}→${NC} make pktgen-rebuild"
    echo -e "       (quick incremental build for Pktgen-DPDK changes)"
    echo ""
    echo -e "  ${YELLOW}4)${NC} Rebuild L3FWD Only"
    echo -e "     ${CYAN}→${NC} make l3fwd-rebuild"
    echo -e "       (quick incremental build for L3FWD changes)"
    echo ""
    echo -e "  ${YELLOW}0)${NC} Back to Main Menu"
    echo ""
    echo -e "${GREEN}────────────────────────────────────────────────────────────${NC}"

    read -p "$(echo -e ${CYAN}Select build option:${NC} )" build_choice

    case $build_choice in
        1)
            echo ""
            echo -e "${BLUE}>> Running make clean...${NC}"
            make clean
            echo ""
            echo -e "${BLUE}>> Running make submodules...${NC}"
            make submodules
            echo ""
            echo -e "${GREEN}✓ Full build completed!${NC}"
            ;;
        2)
            echo ""
            echo -e "${BLUE}>> Running make clean...${NC}"
            make clean
            echo ""
            echo -e "${BLUE}>> Running make submodules-debug...${NC}"
            make submodules-debug
            echo ""
            echo -e "${GREEN}✓ Full debug build completed!${NC}"
            ;;
        3)
            echo ""
            echo -e "${BLUE}>> Running make pktgen-rebuild...${NC}"
            make pktgen-rebuild
            echo ""
            echo -e "${GREEN}✓ Pktgen rebuild completed!${NC}"
            ;;
        4)
            echo ""
            echo -e "${BLUE}>> Running make l3fwd-rebuild...${NC}"
            make l3fwd-rebuild
            echo ""
            echo -e "${GREEN}✓ L3FWD rebuild completed!${NC}"
            ;;
        0)
            return
            ;;
        *)
            echo -e "${RED}Invalid option.${NC}"
            ;;
    esac
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
