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

# Helper: Get system info for a node (local or remote)
get_node_system_info() {
    local node="$1"
    local is_local="$2"  # "local" or "remote"
    local output_file="$3"

    local cmd='
        echo "=== SYSTEM ==="
        hostname
        grep "^PRETTY_NAME=" /etc/os-release 2>/dev/null | cut -d"\"" -f2 || uname -s
        uname -r

        echo "=== CPU ==="
        lscpu | grep "Model name" | sed "s/Model name:\s*//"
        # Detect CPU generation from model number and stepping
        MODEL=$(grep -m1 "^model[[:space:]]*:" /proc/cpuinfo | awk -F": " "{print \$2}" | tr -d " ")
        STEPPING=$(grep -m1 "^stepping[[:space:]]*:" /proc/cpuinfo | awk -F": " "{print \$2}" | tr -d " ")
        case "$MODEL" in
            85)
                if [ "$STEPPING" -ge 10 ] 2>/dev/null; then
                    GEN="Cooper Lake"
                elif [ "$STEPPING" -ge 5 ] 2>/dev/null; then
                    GEN="Cascade Lake-SP"
                else
                    GEN="Skylake-SP"
                fi
                ;;
            106) GEN="Ice Lake-SP" ;;
            143) GEN="Sapphire Rapids" ;;
            207) GEN="Emerald Rapids" ;;
            *) GEN="Model $MODEL" ;;
        esac
        echo "Generation: $GEN"
        SOCKETS=$(lscpu | grep "Socket(s):" | awk "{print \$2}")
        CORES=$(lscpu | grep "Core(s) per socket:" | awk "{print \$4}")
        echo "${SOCKETS}S × ${CORES}C = $((SOCKETS * CORES)) cores"

        echo "=== NUMA ==="
        lscpu | grep "NUMA node[0-9]" | while read line; do
            node_num=$(echo $line | awk "{print \$2}" | sed "s/://")
            cpus=$(echo $line | awk "{print \$NF}")
            echo "NUMA-$node_num: $cpus"
        done

        echo "=== NICs ==="
        for iface in $(ls /sys/class/net/ | grep -v "^lo$\|^docker\|^virbr\|^br-\|^veth"); do
            pci=$(ethtool -i $iface 2>/dev/null | grep "bus-info:" | awk "{print \$2}")
            [ -z "$pci" ] && continue
            driver=$(ethtool -i $iface 2>/dev/null | grep "driver:" | awk "{print \$2}")
            mac=$(cat /sys/class/net/$iface/address 2>/dev/null)
            link=$(ethtool $iface 2>/dev/null | grep "Link detected:" | awk "{print \$3}")
            speed_raw=$(ethtool $iface 2>/dev/null | grep "Speed:" | awk "{print \$2}" | sed "s/Mb\/s//")
            ip=$(ip -4 addr show $iface 2>/dev/null | grep -oP "(?<=inet\s)\d+(\.\d+){3}" | head -1)
            numa=$(cat /sys/bus/pci/devices/$pci/numa_node 2>/dev/null || echo "?")

            if [ "$link" = "yes" ] && [ -n "$speed_raw" ] && [ "$speed_raw" != "Unknown!" ]; then
                if [ "$speed_raw" -ge 1000 ] 2>/dev/null; then
                    speed_gb="$((speed_raw / 1000))Gb/s"
                else
                    speed_gb="${speed_raw}Mb/s"
                fi
                status="UP $speed_gb"
            else
                max_speed=$(ethtool $iface 2>/dev/null | grep -A 50 "Supported link modes:" | grep -oP "\d+(?=base)" | sort -rn | head -1)
                if [ -n "$max_speed" ] && [ "$max_speed" -ge 1000 ]; then
                    status="DOWN (max $((max_speed/1000))Gb/s)"
                else
                    status="DOWN"
                fi
            fi

            echo "NIC|$iface|$pci|$driver|$mac|${ip:-none}|$numa|$status"
        done
    '

    if [ "$is_local" = "local" ]; then
        bash -c "$cmd" > "$output_file" 2>/dev/null
    else
        ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$node" "$cmd" > "$output_file" 2>/dev/null
    fi
}

# Helper: Parse and display node info
display_node_column() {
    local info_file="$1"
    local width="$2"

    if [ ! -f "$info_file" ] || [ ! -s "$info_file" ]; then
        printf "%-${width}s\n" "  (connection failed)"
        return
    fi

    local section=""
    while IFS= read -r line; do
        case "$line" in
            "=== SYSTEM ===") section="system"; continue ;;
            "=== CPU ===") section="cpu"; continue ;;
            "=== NUMA ===") section="numa"; continue ;;
            "=== NICs ===") section="nics"; continue ;;
        esac

        case "$section" in
            system|cpu|numa)
                # Truncate if too long
                local display_line="  ${line:0:$((width-2))}"
                printf "%s\n" "$display_line"
                ;;
        esac
    done < "$info_file"
}

# Helper: Display NICs for selection (returns count via global variable)
display_nics_for_selection() {
    local info_file="$1"
    local node_name="$2"

    echo ""
    echo -e "${CYAN}NICs on $node_name:${NC}"

    _NIC_COUNT=0
    local idx=1
    while IFS='|' read -r type iface pci driver mac ip numa status; do
        [ "$type" != "NIC" ] && continue
        echo -e "  ${YELLOW}$idx)${NC} $iface ($pci)"
        echo -e "     Driver: $driver | NUMA: $numa | $status | IP: $ip | MAC: $mac"
        idx=$((idx + 1))
    done < <(grep "^NIC|" "$info_file") || true

    _NIC_COUNT=$((idx - 1))
}

# Helper: Get NIC by index
get_nic_by_index() {
    local info_file="$1"
    local index="$2"

    grep "^NIC|" "$info_file" | sed -n "${index}p"
}

# Option 1: Show and update system configuration
option_system_config() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  System Configuration${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
    echo ""

    # Read cluster config
    CLUSTER_CONFIG="$SCRIPT_DIR/cluster.config"
    if [ ! -f "$CLUSTER_CONFIG" ]; then
        echo -e "${RED}✗ Error: cluster.config not found${NC}"
        return 1
    fi

    PKTGEN_NODE=$(grep "^PKTGEN_NODE=" "$CLUSTER_CONFIG" | cut -d'=' -f2)
    L3FWD_NODE=$(grep "^L3FWD_NODE=" "$CLUSTER_CONFIG" | cut -d'=' -f2)

    if [ -z "$PKTGEN_NODE" ] || [ -z "$L3FWD_NODE" ]; then
        echo -e "${RED}✗ Error: PKTGEN_NODE or L3FWD_NODE not set in cluster.config${NC}"
        return 1
    fi

    echo -e "${CYAN}Gathering system info...${NC}"
    echo -e "  PKTGEN: ${GREEN}$PKTGEN_NODE${NC} (local)"
    echo -e "  L3FWD:  ${GREEN}$L3FWD_NODE${NC} (remote via SSH)"
    echo ""

    # Temp files for system info
    local pktgen_info="/tmp/pktgen_info_$$.txt"
    local l3fwd_info="/tmp/l3fwd_info_$$.txt"

    # Get system info (local for PKTGEN, SSH for L3FWD)
    echo -n "  Fetching PKTGEN info... "
    get_node_system_info "$PKTGEN_NODE" "local" "$pktgen_info"
    echo -e "${GREEN}done${NC}"

    echo -n "  Fetching L3FWD info... "
    get_node_system_info "$L3FWD_NODE" "remote" "$l3fwd_info"
    if [ -s "$l3fwd_info" ]; then
        echo -e "${GREEN}done${NC}"
    else
        echo -e "${RED}failed (SSH connection error?)${NC}"
    fi

    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
    printf "${GREEN}%-46s${NC} │ ${GREEN}%-46s${NC}\n" "  PKTGEN ($PKTGEN_NODE)" "  L3FWD ($L3FWD_NODE)"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════════════════════════${NC}"

    # Display side by side using paste
    paste <(display_node_column "$pktgen_info" 46) <(display_node_column "$l3fwd_info" 46) | \
        while IFS=$'\t' read -r left right; do
            printf "%-46s │ %-46s\n" "$left" "$right"
        done

    echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════════════════════════${NC}"

    # NIC selection for PKTGEN
    display_nics_for_selection "$pktgen_info" "PKTGEN ($PKTGEN_NODE)"
    pktgen_nic_count=$_NIC_COUNT

    if [ "$pktgen_nic_count" -gt 0 ]; then
        if [ "$pktgen_nic_count" -eq 1 ]; then
            pktgen_selection=1
            echo -e "  ${CYAN}→ Auto-selected (only 1 NIC)${NC}"
        else
            while true; do
                read -p "$(echo -e "${CYAN}Select PKTGEN NIC [1-$pktgen_nic_count]: ${NC}")" pktgen_selection || {
                    echo -e "\n${RED}Input cancelled.${NC}"
                    rm -f "$pktgen_info" "$l3fwd_info"
                    return 1
                }
                if [[ "$pktgen_selection" =~ ^[0-9]+$ ]] && [ "$pktgen_selection" -ge 1 ] && [ "$pktgen_selection" -le "$pktgen_nic_count" ]; then
                    break
                fi
                echo -e "${RED}Invalid selection. Please enter 1-$pktgen_nic_count${NC}"
            done
        fi

        pktgen_nic_line=$(get_nic_by_index "$pktgen_info" "$pktgen_selection")
        IFS='|' read -r _ PKTGEN_NIC_NAME PKTGEN_NIC_PCI PKTGEN_NIC_DRIVER PKTGEN_NIC_MAC PKTGEN_NIC_IP _ _ <<< "$pktgen_nic_line"
        echo -e "  ${GREEN}✓ PKTGEN NIC: $PKTGEN_NIC_NAME ($PKTGEN_NIC_PCI)${NC}"
    fi

    # NIC selection for L3FWD
    if [ -s "$l3fwd_info" ]; then
        display_nics_for_selection "$l3fwd_info" "L3FWD ($L3FWD_NODE)"
        l3fwd_nic_count=$_NIC_COUNT

        if [ "$l3fwd_nic_count" -gt 0 ]; then
            if [ "$l3fwd_nic_count" -eq 1 ]; then
                l3fwd_selection=1
                echo -e "  ${CYAN}→ Auto-selected (only 1 NIC)${NC}"
            else
                while true; do
                    read -p "$(echo -e "${CYAN}Select L3FWD NIC [1-$l3fwd_nic_count]: ${NC}")" l3fwd_selection || {
                        echo -e "\n${RED}Input cancelled.${NC}"
                        rm -f "$pktgen_info" "$l3fwd_info"
                        return 1
                    }
                    if [[ "$l3fwd_selection" =~ ^[0-9]+$ ]] && [ "$l3fwd_selection" -ge 1 ] && [ "$l3fwd_selection" -le "$l3fwd_nic_count" ]; then
                        break
                    fi
                    echo -e "${RED}Invalid selection. Please enter 1-$l3fwd_nic_count${NC}"
                done
            fi

            l3fwd_nic_line=$(get_nic_by_index "$l3fwd_info" "$l3fwd_selection")
            IFS='|' read -r _ L3FWD_NIC_NAME L3FWD_NIC_PCI L3FWD_NIC_DRIVER L3FWD_NIC_MAC L3FWD_NIC_IP _ _ <<< "$l3fwd_nic_line"
            echo -e "  ${GREEN}✓ L3FWD NIC: $L3FWD_NIC_NAME ($L3FWD_NIC_PCI)${NC}"
        fi
    else
        echo -e "\n${YELLOW}⚠ Skipping L3FWD NIC selection (connection failed)${NC}"
    fi

    # Update config file
    CONFIG_FILE="$SCRIPT_DIR/config/system.config"
    mkdir -p "$SCRIPT_DIR/config"

    cat > "$CONFIG_FILE" << EOF
# System Configuration
# Auto-generated by entry.sh option 1
# Last updated: $(date '+%Y-%m-%d %H:%M:%S')

# PKTGEN Node NIC Configuration
PKTGEN_NIC_PCI=${PKTGEN_NIC_PCI:-}
PKTGEN_NIC_MAC=${PKTGEN_NIC_MAC:-}
PKTGEN_NIC_IP=${PKTGEN_NIC_IP:-}

# L3FWD Node NIC Configuration
L3FWD_NIC_PCI=${L3FWD_NIC_PCI:-}
L3FWD_NIC_MAC=${L3FWD_NIC_MAC:-}
L3FWD_NIC_IP=${L3FWD_NIC_IP:-}
EOF

    echo ""
    echo -e "${GREEN}✓ Configuration saved to config/system.config${NC}"

    # Connectivity test between PKTGEN and L3FWD
    if [ -n "$PKTGEN_NIC_IP" ] && [ "$PKTGEN_NIC_IP" != "none" ] && \
       [ -n "$L3FWD_NIC_IP" ] && [ "$L3FWD_NIC_IP" != "none" ]; then
        echo ""
        echo -e "${CYAN}Testing connectivity: PKTGEN ($PKTGEN_NIC_IP) → L3FWD ($L3FWD_NIC_IP)${NC}"
        echo ""

        # Ping from PKTGEN to L3FWD (3 packets)
        ping_output=$(ping -c 3 -W 2 "$L3FWD_NIC_IP" 2>&1)
        ping_result=$?

        # Show ping summary
        echo "$ping_output" | grep -E "^PING|bytes from|packets|rtt" || true
        echo ""

        if [ $ping_result -eq 0 ]; then
            echo -e "${GREEN}✓ Connectivity OK${NC}"
        else
            echo -e "${RED}✗ Ping failed (exit code: $ping_result) - check network configuration${NC}"
        fi
    else
        echo ""
        echo -e "${YELLOW}⚠ Skipping connectivity test (IP not configured on selected NICs)${NC}"
    fi

    # Cleanup
    rm -f "$pktgen_info" "$l3fwd_info"

    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
}

# Option 2: Initial Machine Setup (runs on both nodes simultaneously)
option_initial_setup() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Initial Machine Setup (Both Nodes)${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
    echo ""

    # Read cluster config
    CLUSTER_CONFIG="$SCRIPT_DIR/cluster.config"
    if [ ! -f "$CLUSTER_CONFIG" ]; then
        echo -e "${RED}✗ Error: cluster.config not found${NC}"
        return 1
    fi

    PKTGEN_NODE=$(grep "^PKTGEN_NODE=" "$CLUSTER_CONFIG" | cut -d'=' -f2)
    L3FWD_NODE=$(grep "^L3FWD_NODE=" "$CLUSTER_CONFIG" | cut -d'=' -f2)

    if [ -z "$PKTGEN_NODE" ] || [ -z "$L3FWD_NODE" ]; then
        echo -e "${RED}✗ Error: PKTGEN_NODE or L3FWD_NODE not set in cluster.config${NC}"
        return 1
    fi

    echo -e "${CYAN}This will install dependencies and configure DPDK on both nodes simultaneously.${NC}"
    echo -e "${YELLOW}Note: Requires sudo privileges on both machines.${NC}"
    echo ""
    echo -e "  PKTGEN: ${GREEN}$PKTGEN_NODE${NC} (local)"
    echo -e "  L3FWD:  ${GREEN}$L3FWD_NODE${NC} (remote via SSH)"
    echo ""

    # Temp files for output
    local pktgen_log="/tmp/setup_pktgen_$$.log"
    local l3fwd_log="/tmp/setup_l3fwd_$$.log"

    # Setup script to run on each node
    local setup_script='
set -e
HOSTNAME=$(hostname)

echo "=== [$HOSTNAME] Step 1/4: Installing system dependencies ==="
sudo apt update && sudo apt install -y \
    meson ninja-build build-essential pkg-config git \
    libnuma-dev libpcap-dev python3-pyelftools liblua5.3-dev \
    libibverbs-dev librdmacm-dev rdma-core ibverbs-providers libmlx5-1 \
    libelf-dev libbsd-dev zlib1g-dev libpci-dev \
    python3-pip python3-dev ethtool wget gpg apt-transport-https
echo "[$HOSTNAME] ✓ System dependencies installed"

echo "=== [$HOSTNAME] Step 2/4: Checking/Upgrading CMake ==="
CMAKE_VERSION=$(cmake --version 2>/dev/null | head -1 | awk "{print \$3}")
CMAKE_MAJOR=$(echo "$CMAKE_VERSION" | cut -d. -f1)
CMAKE_MINOR=$(echo "$CMAKE_VERSION" | cut -d. -f2)
if [ -z "$CMAKE_VERSION" ] || [ "$CMAKE_MAJOR" -lt 3 ] || ([ "$CMAKE_MAJOR" -eq 3 ] && [ "$CMAKE_MINOR" -lt 17 ]); then
    echo "[$HOSTNAME] Current CMake: ${CMAKE_VERSION:-not installed}. Installing latest..."
    wget -qO - https://apt.kitware.com/keys/kitware-archive-latest.asc 2>/dev/null | gpg --dearmor - | sudo tee /usr/share/keyrings/kitware-archive-keyring.gpg >/dev/null
    UBUNTU_CODENAME=$(lsb_release -cs)
    echo "deb [signed-by=/usr/share/keyrings/kitware-archive-keyring.gpg] https://apt.kitware.com/ubuntu/ $UBUNTU_CODENAME main" | sudo tee /etc/apt/sources.list.d/kitware.list >/dev/null
    sudo apt update && sudo apt install -y cmake
    echo "[$HOSTNAME] ✓ CMake upgraded to $(cmake --version | head -1 | awk "{print \$3}")"
else
    echo "[$HOSTNAME] ✓ CMake $CMAKE_VERSION already meets requirements (>= 3.17)"
fi

echo "=== [$HOSTNAME] Step 3/4: Installing Python dependencies ==="
pip3 install --user --break-system-packages numpy pandas matplotlib cycler pyrem 2>/dev/null || \
pip3 install --user numpy pandas matplotlib cycler pyrem || true
echo "[$HOSTNAME] ✓ Python dependencies installed"

echo "=== [$HOSTNAME] Step 4/4: Setting up hugepages and MSR ==="
# Setup hugepages
echo 2048 | sudo tee /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages >/dev/null || true
HUGEPAGES=$(cat /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages)
echo "[$HOSTNAME] Hugepages configured: $HUGEPAGES"

# Load MSR module
sudo modprobe msr 2>/dev/null || true
if lsmod | grep -q msr; then
    echo "[$HOSTNAME] ✓ MSR module loaded"
else
    echo "[$HOSTNAME] ⚠ MSR module not available"
fi

# Check /dev/cpu/0/msr
if [ -e /dev/cpu/0/msr ]; then
    echo "[$HOSTNAME] ✓ /dev/cpu/0/msr exists"
else
    echo "[$HOSTNAME] ⚠ /dev/cpu/0/msr not found"
fi

echo "=== [$HOSTNAME] Setup completed! ==="
'

    # Step 0: Sync Mellanox RDMA libraries from PKTGEN to L3FWD node
    echo -e "${CYAN}Syncing Mellanox RDMA libraries to $L3FWD_NODE...${NC}"

    # Check rdma-core versions on both nodes
    LOCAL_RDMA_VER=$(dpkg -l rdma-core 2>/dev/null | grep rdma-core | awk '{print $3}')
    REMOTE_RDMA_VER=$(ssh -o StrictHostKeyChecking=no "$L3FWD_NODE" "dpkg -l rdma-core 2>/dev/null | grep rdma-core | awk '{print \$3}'" 2>/dev/null)

    echo -e "  PKTGEN ($PKTGEN_NODE): rdma-core $LOCAL_RDMA_VER"
    echo -e "  L3FWD ($L3FWD_NODE): rdma-core $REMOTE_RDMA_VER"

    if [ "$LOCAL_RDMA_VER" != "$REMOTE_RDMA_VER" ]; then
        echo -e "  ${YELLOW}버전 불일치 - 동기화 진행${NC}"

        # Find OFED .deb files
        OFED_DIR=$(find /home -maxdepth 3 -name "MLNX_OFED*" -type d 2>/dev/null | head -1)
        if [ -n "$OFED_DIR" ] && [ -d "$OFED_DIR/DEBS" ]; then
            # Copy and install required packages
            DEB_FILES="$OFED_DIR/DEBS/rdma-core_*_amd64.deb $OFED_DIR/DEBS/libibverbs1_*_amd64.deb $OFED_DIR/DEBS/ibverbs-providers_*_amd64.deb"

            echo -e "  .deb 파일 복사 중..."
            scp -o StrictHostKeyChecking=no $DEB_FILES "$L3FWD_NODE:/tmp/" 2>/dev/null

            echo -e "  패키지 설치 중..."
            ssh -o StrictHostKeyChecking=no "$L3FWD_NODE" "sudo dpkg -i --force-overwrite /tmp/rdma-core_*.deb /tmp/libibverbs1_*.deb /tmp/ibverbs-providers_*.deb" 2>&1 | grep -E "Unpacking|Setting up" || true

            # Verify
            NEW_VER=$(ssh -o StrictHostKeyChecking=no "$L3FWD_NODE" "dpkg -l rdma-core 2>/dev/null | grep rdma-core | awk '{print \$3}'" 2>/dev/null)
            if [ "$LOCAL_RDMA_VER" = "$NEW_VER" ]; then
                echo -e "${GREEN}✓ 라이브러리 동기화 완료: $NEW_VER${NC}"
            else
                echo -e "${RED}✗ 동기화 실패${NC}"
            fi
        else
            echo -e "${YELLOW}⚠ OFED .deb 파일을 찾을 수 없음, 수동 설치 필요${NC}"
        fi
    else
        echo -e "${GREEN}✓ 이미 동일한 버전${NC}"
    fi
    echo ""

    echo -e "${CYAN}Starting setup on both nodes in parallel...${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
    echo ""

    # Run on PKTGEN (local) in background - show output with prefix
    bash -c "$setup_script" 2>&1 | tee "$pktgen_log" | awk '{print "\033[1;33m[PKTGEN]\033[0m " $0; fflush()}' &
    local pktgen_pid=$!

    # Run on L3FWD (remote) in background - show output with prefix
    ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$L3FWD_NODE" "$setup_script" 2>&1 | tee "$l3fwd_log" | awk '{print "\033[0;36m[L3FWD]\033[0m  " $0; fflush()}' &
    local l3fwd_pid=$!

    # Wait for both processes
    local pktgen_status=0
    local l3fwd_status=0

    wait $pktgen_pid || pktgen_status=$?
    wait $l3fwd_pid || l3fwd_status=$?

    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
    echo ""

    # Summary
    if [ $pktgen_status -eq 0 ]; then
        echo -e "${GREEN}✓ PKTGEN ($PKTGEN_NODE): Setup completed successfully${NC}"
    else
        echo -e "${RED}✗ PKTGEN ($PKTGEN_NODE): Setup failed (exit code: $pktgen_status)${NC}"
        echo -e "  ${CYAN}→${NC} Check full log: $pktgen_log"
    fi

    if [ $l3fwd_status -eq 0 ]; then
        echo -e "${GREEN}✓ L3FWD ($L3FWD_NODE): Setup completed successfully${NC}"
    else
        echo -e "${RED}✗ L3FWD ($L3FWD_NODE): Setup failed (exit code: $l3fwd_status)${NC}"
        echo -e "  ${CYAN}→${NC} Check full log: $l3fwd_log"
    fi

    echo ""

    # Offer to show full logs
    echo -e "${CYAN}View full logs?${NC}"
    echo -e "  ${YELLOW}1)${NC} PKTGEN log"
    echo -e "  ${YELLOW}2)${NC} L3FWD log"
    echo -e "  ${YELLOW}3)${NC} Both logs"
    echo -e "  ${YELLOW}0)${NC} Skip"
    echo ""
    read -p "$(echo -e ${CYAN}Select:${NC} )" log_choice || log_choice=0

    case $log_choice in
        1)
            echo ""
            echo -e "${BLUE}─── PKTGEN ($PKTGEN_NODE) Full Log ───${NC}"
            cat "$pktgen_log"
            ;;
        2)
            echo ""
            echo -e "${BLUE}─── L3FWD ($L3FWD_NODE) Full Log ───${NC}"
            cat "$l3fwd_log"
            ;;
        3)
            echo ""
            echo -e "${BLUE}─── PKTGEN ($PKTGEN_NODE) Full Log ───${NC}"
            cat "$pktgen_log"
            echo ""
            echo -e "${BLUE}─── L3FWD ($L3FWD_NODE) Full Log ───${NC}"
            cat "$l3fwd_log"
            ;;
    esac

    # Cleanup temp files
    rm -f "$pktgen_log" "$l3fwd_log"

    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
    if [ $pktgen_status -eq 0 ] && [ $l3fwd_status -eq 0 ]; then
        echo -e "${GREEN}✓ Initial setup completed on both nodes!${NC}"
    else
        echo -e "${YELLOW}⚠ Setup completed with some issues. Check logs above.${NC}"
    fi
    echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
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

# Option 4: Run Simple Pktgen Test (with L3FWD)
option_simple_test() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Simple Test (L3FWD + PKTGEN)${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
    echo ""

    # Read cluster config
    CLUSTER_CONFIG="$SCRIPT_DIR/cluster.config"
    if [ ! -f "$CLUSTER_CONFIG" ]; then
        echo -e "${RED}✗ Error: cluster.config not found${NC}"
        return 1
    fi

    PKTGEN_NODE=$(grep "^PKTGEN_NODE=" "$CLUSTER_CONFIG" | cut -d'=' -f2)
    L3FWD_NODE=$(grep "^L3FWD_NODE=" "$CLUSTER_CONFIG" | cut -d'=' -f2)

    echo -e "${CYAN}Cluster Configuration:${NC}"
    echo -e "  PKTGEN: ${GREEN}$PKTGEN_NODE${NC} (local) - Packet Generator"
    echo -e "  L3FWD:  ${GREEN}$L3FWD_NODE${NC} (remote) - Packet Forwarder"
    echo ""
    echo -e "${CYAN}Config: config/simple-test/simple-test.config${NC}"
    echo -e "${CYAN}Script: config/simple-test/simple-pktgen-test.lua${NC}"
    echo ""

    # Load test config
    TEST_CONFIG="$SCRIPT_DIR/config/simple-test/simple-test.config"
    if [ -f "$TEST_CONFIG" ]; then
        source "$TEST_CONFIG"
    fi

    # Load system config for NIC addresses
    SYSTEM_CONFIG="$SCRIPT_DIR/config/system.config"
    if [ -f "$SYSTEM_CONFIG" ]; then
        source "$SYSTEM_CONFIG"
    fi

    # Validate required config from system.config
    if [ -z "${PKTGEN_NIC_MAC:-}" ]; then
        echo -e "${RED}✗ Error: PKTGEN_NIC_MAC not configured${NC}"
        echo -e "  ${CYAN}→${NC} Run option 1 to configure NIC settings"
        return 1
    fi
    if [ -z "${L3FWD_NIC_MAC:-}" ]; then
        echo -e "${RED}✗ Error: L3FWD_NIC_MAC not configured${NC}"
        echo -e "  ${CYAN}→${NC} Run option 1 to configure NIC settings"
        return 1
    fi
    if [ -z "${PKTGEN_NIC_PCI:-}" ]; then
        echo -e "${RED}✗ Error: PKTGEN_NIC_PCI not configured${NC}"
        echo -e "  ${CYAN}→${NC} Run option 1 to configure NIC settings"
        return 1
    fi
    if [ -z "${L3FWD_NIC_PCI:-}" ]; then
        echo -e "${RED}✗ Error: L3FWD_NIC_PCI not configured${NC}"
        echo -e "  ${CYAN}→${NC} Run option 1 to configure NIC settings"
        return 1
    fi

    # Get duration from config or default
    PKTGEN_DURATION="${PKTGEN_DURATION:-10}"
    L3FWD_DURATION=$((PKTGEN_DURATION + 5))
    echo -e "${CYAN}PKTGEN duration: ${PKTGEN_DURATION} seconds${NC}"
    echo -e "${CYAN}L3FWD duration:  ${L3FWD_DURATION} seconds (PKTGEN + 5s)${NC}"
    echo ""

    # Create results directory
    mkdir -p "$SCRIPT_DIR/results"
    TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
    L3FWD_LOG="$SCRIPT_DIR/results/${TIMESTAMP}-simple-test.l3fwd"
    PKTGEN_LOG="$SCRIPT_DIR/results/${TIMESTAMP}-simple-test.pktgen"

    # Build L3FWD command from config (all values come from config files)
    L3FWD_BIN="$SCRIPT_DIR/dpdk/build/examples/dpdk-l3fwd"
    L3FWD_LCORES_ARG="${L3FWD_LCORES}"
    L3FWD_MEMCH_ARG="${L3FWD_MEMCH}"
    L3FWD_PORT_MASK_ARG="${L3FWD_PORT_MASK}"
    L3FWD_CONFIG_ARG="${L3FWD_CONFIG}"
    L3FWD_NIC_DEVARGS_ARG="${L3FWD_NIC_DEVARGS:-}"
    PKTGEN_MAC="${PKTGEN_NIC_MAC}"

    # Build PCI address with optional device args
    if [ -n "$L3FWD_NIC_DEVARGS_ARG" ]; then
        L3FWD_PCI_FULL="$L3FWD_NIC_PCI,$L3FWD_NIC_DEVARGS_ARG"
    else
        L3FWD_PCI_FULL="$L3FWD_NIC_PCI"
    fi

    echo -e "${YELLOW}[1/2]${NC} Starting L3FWD on ${GREEN}$L3FWD_NODE${NC} (auto-stops after ${L3FWD_DURATION}s)..."
    echo -e "  Binary: $L3FWD_BIN"
    echo -e "  EAL: $L3FWD_LCORES_ARG $L3FWD_MEMCH_ARG -a $L3FWD_PCI_FULL"
    echo -e "  Args: $L3FWD_PORT_MASK_ARG --config=\"$L3FWD_CONFIG_ARG\" --eth-dest=0,$PKTGEN_MAC"
    echo ""

    # Set up LD_LIBRARY_PATH for DPDK
    DPDK_ENV="LD_LIBRARY_PATH=$SCRIPT_DIR/dpdk/build/lib:$SCRIPT_DIR/dpdk/build/lib/x86_64-linux-gnu"

    # Start L3FWD on remote node via SSH with timeout
    ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$L3FWD_NODE" \
        "cd $SCRIPT_DIR && timeout ${L3FWD_DURATION} sudo -E $DPDK_ENV $L3FWD_BIN \
        $L3FWD_LCORES_ARG $L3FWD_MEMCH_ARG \
        -a $L3FWD_PCI_FULL \
        -- $L3FWD_PORT_MASK_ARG \
        --config=\"$L3FWD_CONFIG_ARG\" \
        --eth-dest=0,$PKTGEN_MAC" > "$L3FWD_LOG" 2>&1 &
    L3FWD_SSH_PID=$!

    # Wait for L3FWD to initialize
    sleep 3

    # Check if L3FWD started
    L3FWD_REMOTE_PID=$(ssh "$L3FWD_NODE" "pgrep -f 'dpdk-l3fwd'" 2>/dev/null || true)
    if [ -z "$L3FWD_REMOTE_PID" ]; then
        echo -e "${RED}✗ Failed to start L3FWD on $L3FWD_NODE${NC}"
        echo -e "  Check log: $L3FWD_LOG"
        kill $L3FWD_SSH_PID 2>/dev/null || true
        return 1
    fi
    echo -e "${GREEN}✓ L3FWD started (PID: $L3FWD_REMOTE_PID)${NC}"
    echo ""

    echo -e "${YELLOW}[2/2]${NC} Running PKTGEN on ${GREEN}$PKTGEN_NODE${NC} (local, ${PKTGEN_DURATION}s)..."
    echo ""

    # Run PKTGEN test (this will take PKTGEN_DURATION seconds)
    ./scripts/benchmark/run-simple-pktgen-test.sh 2>&1 | tee "$PKTGEN_LOG"
    PKTGEN_STATUS=$?

    echo ""
    echo -e "${CYAN}Waiting for L3FWD to auto-terminate...${NC}"

    # Wait for L3FWD SSH process to finish (timeout will kill it)
    wait $L3FWD_SSH_PID 2>/dev/null || true

    echo -e "${GREEN}✓ L3FWD stopped${NC}"
    echo ""

    echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}✓ Test completed!${NC}"
    echo -e "  L3FWD log:  $L3FWD_LOG"
    echo -e "  PKTGEN log: $PKTGEN_LOG"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
}

# Option 5: Run Full Benchmark (with L3FWD)
option_full_benchmark() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Full Benchmark (L3FWD + PKTGEN)${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
    echo ""

    # Read cluster config
    CLUSTER_CONFIG="$SCRIPT_DIR/cluster.config"
    if [ ! -f "$CLUSTER_CONFIG" ]; then
        echo -e "${RED}✗ Error: cluster.config not found${NC}"
        return 1
    fi

    PKTGEN_NODE=$(grep "^PKTGEN_NODE=" "$CLUSTER_CONFIG" | cut -d'=' -f2)
    L3FWD_NODE=$(grep "^L3FWD_NODE=" "$CLUSTER_CONFIG" | cut -d'=' -f2)

    echo -e "${CYAN}Cluster Configuration:${NC}"
    echo -e "  PKTGEN: ${GREEN}$PKTGEN_NODE${NC} (local) - Packet Generator"
    echo -e "  L3FWD:  ${GREEN}$L3FWD_NODE${NC} (remote) - Packet Forwarder"
    echo ""
    echo -e "${CYAN}Config: scripts/benchmark/test_config.py${NC}"
    echo -e "${CYAN}Results: results/${NC}"
    echo ""

    # Load system config for NIC addresses
    SYSTEM_CONFIG="$SCRIPT_DIR/config/system.config"
    if [ -f "$SYSTEM_CONFIG" ]; then
        source "$SYSTEM_CONFIG"
    fi

    # Check if system.config has required values
    if [ -z "${L3FWD_NIC_PCI:-}" ] || [ -z "${PKTGEN_NIC_MAC:-}" ]; then
        echo -e "${YELLOW}⚠ Warning: system.config may be incomplete${NC}"
        echo -e "  Run option 1 first to configure NIC settings"
        echo ""
    fi

    echo -e "${CYAN}The Python test script will manage L3FWD on $L3FWD_NODE automatically.${NC}"
    echo -e "${CYAN}Make sure test_config.py has correct cluster settings.${NC}"
    echo ""

    read -p "$(echo -e ${CYAN}Continue with benchmark? [y/N]:${NC} )" confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Benchmark cancelled.${NC}"
        return 0
    fi
    echo ""

    # Kill any existing DPDK processes on both nodes
    echo -e "${YELLOW}[1/3]${NC} Cleaning up existing DPDK processes..."
    sudo pkill -f 'pktgen' 2>/dev/null || true
    ssh "$L3FWD_NODE" "sudo pkill -f 'dpdk-l3fwd'" 2>/dev/null || true
    sleep 2
    echo -e "${GREEN}✓ Cleanup done${NC}"
    echo ""

    echo -e "${YELLOW}[2/3]${NC} Running benchmark..."
    echo ""

    # Run the full benchmark (Python script handles L3FWD + PKTGEN orchestration)
    cd scripts/benchmark && python3 run_test.py
    BENCHMARK_STATUS=$?

    echo ""
    echo -e "${YELLOW}[3/3]${NC} Final cleanup..."
    sudo pkill -f 'pktgen' 2>/dev/null || true
    ssh "$L3FWD_NODE" "sudo pkill -f 'dpdk-l3fwd'" 2>/dev/null || true
    echo -e "${GREEN}✓ Cleanup done${NC}"

    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
    if [ $BENCHMARK_STATUS -eq 0 ]; then
        echo -e "${GREEN}✓ Benchmark completed! Results saved to results/${NC}"
    else
        echo -e "${YELLOW}⚠ Benchmark finished with exit code: $BENCHMARK_STATUS${NC}"
    fi
    echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
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
