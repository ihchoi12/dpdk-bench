#!/usr/bin/env bash
# Display system information and update config/system.config
# This script serves dual purposes:
# 1. Show current system hardware configuration (like show_system_info.sh)
# 2. Auto-update config/system.config with detected values

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CONFIG_DIR="${REPO_ROOT}/config"
CONFIG_FILE="${CONFIG_DIR}/system.config"

# Create config directory if it doesn't exist
mkdir -p "$CONFIG_DIR"

# Create config file with header if it doesn't exist
if [ ! -f "$CONFIG_FILE" ]; then
    cat > "$CONFIG_FILE" << 'EOF'
# System Configuration
# This file contains machine-specific hardware configuration.
# Run 'make get-system-info' to auto-detect and update these values.
# Last updated: never

EOF
fi

# =============================================================================
# Helper Functions
# =============================================================================

update_config_value() {
    local key="$1"
    local value="$2"
    local config_file="$3"

    # Escape special characters in value for sed
    local escaped_value=$(echo "$value" | sed 's/[\/&]/\\&/g')

    # Update or append the key=value pair
    if grep -q "^${key}=" "$config_file" 2>/dev/null; then
        sed -i "s/^${key}=.*/${key}=${escaped_value}/" "$config_file"
    else
        echo "${key}=${escaped_value}" >> "$config_file"
    fi
}

# =============================================================================
# SYSTEM INFO
# =============================================================================

echo "=== SYSTEM INFO ==="

# Detect OS version
if [ -f /etc/os-release ]; then
  OS_NAME=$(grep '^PRETTY_NAME=' /etc/os-release | cut -d'"' -f2)
  echo "OS: $OS_NAME"
else
  OS_NAME=$(uname -s)
  echo "OS: $OS_NAME"
fi

# Detect Kernel version
KERNEL_VERSION=$(uname -r)
echo "Kernel: $KERNEL_VERSION"

# Detect Hostname
HOSTNAME=$(hostname)
echo "Hostname: $HOSTNAME"

# =============================================================================
# CPU INFO
# =============================================================================

echo ""
echo "=== CPU INFO ==="

# CPU model
CPU_MODEL=$(lscpu | grep 'Model name' | sed 's/Model name:\s*//' | xargs)
echo "CPU: $CPU_MODEL"

# CPU architecture
CPU_ARCH=$(gcc -march=native -Q --help=target 2>/dev/null | grep -- '-march=' | head -1 | awk '{print $2}' || echo "unknown")
echo "Arch: $CPU_ARCH"

# CPU topology
SOCKETS=$(lscpu | grep 'Socket(s):' | awk '{print $2}')
CORES_PER_SOCKET=$(lscpu | grep 'Core(s) per socket:' | awk '{print $4}')
THREADS_PER_CORE=$(lscpu | grep 'Thread(s) per core:' | awk '{print $4}')
PHYSICAL_CORES=$((SOCKETS * CORES_PER_SOCKET))
TOTAL_THREADS=$((PHYSICAL_CORES * THREADS_PER_CORE))

echo "Sockets: $SOCKETS × $CORES_PER_SOCKET cores = $PHYSICAL_CORES physical cores"
echo "Threads: $PHYSICAL_CORES cores × $THREADS_PER_CORE (HT) = $TOTAL_THREADS threads"

# NUMA nodes
NUMA_NODES=$(lscpu | grep 'NUMA node(s):' | awk '{print $3}')

# =============================================================================
# NUMA TOPOLOGY
# =============================================================================

echo ""
echo "=== NUMA TOPOLOGY ==="

while IFS= read -r line; do
  node=$(echo $line | awk '{print $1 " " $2}' | sed 's/://')
  cpus=$(echo $line | awk '{print $NF}')
  echo "$node CPUs: $cpus"

  # Show HT pairs
  echo -n "  HT pairs:"

  # Expand CPU range (e.g., 0-39 -> 0 1 2 ... 39)
  cpu_list=""
  for range in $(echo $cpus | tr ',' ' '); do
    if [[ $range == *-* ]]; then
      start=$(echo $range | cut -d'-' -f1)
      end=$(echo $range | cut -d'-' -f2)
      cpu_list="$cpu_list $(seq $start $end)"
    else
      cpu_list="$cpu_list $range"
    fi
  done

  # Track seen CPUs
  seen_cpus=""
  for cpu in $cpu_list; do
    # Skip if already seen
    if echo " $seen_cpus " | grep -q " $cpu "; then
      continue
    fi

    # Get sibling list
    sibling=$(cat /sys/devices/system/cpu/cpu$cpu/topology/thread_siblings_list 2>/dev/null)
    if [ -n "$sibling" ]; then
      echo -n " [$sibling]"
      # Mark all siblings as seen
      for s in $(echo $sibling | tr ',' ' '); do
        seen_cpus="$seen_cpus $s"
      done
    fi
  done
  echo ""
done < <(lscpu | grep "NUMA node[0-9]")

# =============================================================================
# NETWORK INTERFACES
# =============================================================================

echo ""
echo "=== NETWORK INTERFACES ==="

# Get DPDK-bound devices info
declare -A dpdk_ports
if [ -f "./dpdk/usertools/dpdk-devbind.py" ]; then
  while read line; do
    if echo "$line" | grep -q "0000:" && echo "$line" | grep -qE "drv=(vfio-pci|uio_pci_generic|igb_uio)"; then
      pci=$(echo $line | awk '{print $1}')
      driver=$(echo $line | grep -o "drv=[^ ]*" | cut -d= -f2)
      dpdk_ports[$pci]=$driver
    fi
  done < <(./dpdk/usertools/dpdk-devbind.py --status 2>/dev/null | awk '/Network devices using DPDK-compatible driver/,/^$/')
fi

# Track NIC info for selection
PKTGEN_NIC_NAME=""
PKTGEN_NIC_PCI=""
PKTGEN_NIC_MAC=""
PKTGEN_NIC_IP=""
PKTGEN_NIC_NUMA=""
PKTGEN_NIC_DRIVER=""
PKTGEN_NIC_SPEED=""
PKTGEN_NIC_MODEL=""
max_speed=0

# Process each Ethernet NIC
lspci | grep -i ethernet | while read line; do
  pci_short=$(echo "$line" | awk '{print $1}')
  pci_full="0000:$pci_short"
  desc=$(echo "$line" | cut -d: -f3- | sed 's/^ *//')

  # Find interface name
  iface=$(ls /sys/bus/pci/devices/$pci_full/net/ 2>/dev/null | head -1)

  # Get NUMA node
  numa_node=$(cat /sys/bus/pci/devices/$pci_full/numa_node 2>/dev/null || echo "N/A")

  # Print header
  if [ -n "$iface" ]; then
    echo "$pci_full ($iface) - $desc"
  else
    echo "$pci_full (no interface) - $desc"
  fi

  # Check if DPDK-bound
  if [ -n "${dpdk_ports[$pci_full]:-}" ]; then
    # DPDK-bound device
    driver="${dpdk_ports[$pci_full]}"
    echo "  Driver: DPDK ($driver) | NUMA: $numa_node | Status: Bound to DPDK (link info unavailable)"
  elif [ -n "$iface" ]; then
    # Kernel driver
    kernel_driver=$(ethtool -i $iface 2>/dev/null | grep "driver:" | awk '{print $2}')
    speed=$(ethtool $iface 2>/dev/null | grep "Speed:" | awk '{print $2}')
    duplex=$(ethtool $iface 2>/dev/null | grep "Duplex:" | awk '{print $2}')
    link=$(ethtool $iface 2>/dev/null | grep "Link detected:" | awk '{print $3}')
    ipv4=$(ip -4 addr show $iface 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
    mac=$(cat /sys/class/net/$iface/address 2>/dev/null)

    # Format IP info
    if [ -n "$ipv4" ]; then
      ip_info="IP: $ipv4"
    else
      ip_info="IP: none"
    fi

    # Format MAC info
    if [ -n "$mac" ]; then
      mac_info="MAC: $mac"
    else
      mac_info="MAC: unknown"
    fi

    # Format link status
    if [ "$link" = "yes" ] && [ -n "$speed" ] && [ "$speed" != "Unknown!" ]; then
      link_info="UP ($speed $duplex)"
    elif [ "$link" = "yes" ]; then
      link_info="UP (speed unknown)"
    else
      link_info="DOWN"
    fi

    echo "  Driver: kernel ($kernel_driver) | NUMA: $numa_node | Link: $link_info | $ip_info | $mac_info"

    # Track for primary NIC selection (convert speed to Mbps)
    speed_mbps=0
    if [[ "$speed" =~ ([0-9]+)Mb/s ]]; then
      speed_mbps=${BASH_REMATCH[1]}
    elif [[ "$speed" =~ ([0-9]+)Gb/s ]]; then
      speed_mbps=$((${BASH_REMATCH[1]} * 1000))
    fi

    # Write to temp file (subshell workaround)
    echo "$iface|$pci_full|$mac|$ipv4|$numa_node|$kernel_driver|$speed_mbps|$desc" >> /tmp/nic_info_$$.tmp
  else
    echo "  Driver: none | NUMA: $numa_node | Status: No interface detected"
  fi
  echo ""
done

# Interactive NIC selection
if [ -f /tmp/nic_info_$$.tmp ]; then
    # Count available NICs
    nic_count=$(wc -l < /tmp/nic_info_$$.tmp)

    if [ "$nic_count" -eq 0 ]; then
        echo "No NICs found!"
        rm -f /tmp/nic_info_$$.tmp
    elif [ "$nic_count" -eq 1 ]; then
        # Only one NIC, auto-select
        IFS='|' read -r PKTGEN_NIC_NAME PKTGEN_NIC_PCI PKTGEN_NIC_MAC PKTGEN_NIC_IP PKTGEN_NIC_NUMA PKTGEN_NIC_DRIVER PKTGEN_NIC_SPEED PKTGEN_NIC_MODEL < /tmp/nic_info_$$.tmp
        echo "==> Only one NIC available, auto-selected: $PKTGEN_NIC_NAME ($PKTGEN_NIC_PCI)"
        rm -f /tmp/nic_info_$$.tmp
    else
        # Multiple NICs, let user choose
        echo ""
        echo "=== SELECT NIC FOR PKTGEN ==="
        echo ""

        # Display numbered list
        idx=1
        while IFS='|' read -r iface pci mac ip numa driver speed desc; do
            speed_display="${speed}Mbps"
            if [ "$speed" -ge 1000 ]; then
                speed_display="$((speed/1000))Gbps"
            fi
            ip_display="${ip:-none}"
            echo "  $idx) $iface ($pci)"
            echo "     $desc"
            echo "     Speed: $speed_display | MAC: $mac | IP: $ip_display"
            echo ""
            idx=$((idx + 1))
        done < /tmp/nic_info_$$.tmp

        # Get user selection
        while true; do
            read -p "Select NIC [1-$nic_count]: " selection
            if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "$nic_count" ]; then
                break
            fi
            echo "Invalid selection. Please enter a number between 1 and $nic_count."
        done

        # Read selected NIC
        selected_line=$(sed -n "${selection}p" /tmp/nic_info_$$.tmp)
        IFS='|' read -r PKTGEN_NIC_NAME PKTGEN_NIC_PCI PKTGEN_NIC_MAC PKTGEN_NIC_IP PKTGEN_NIC_NUMA PKTGEN_NIC_DRIVER PKTGEN_NIC_SPEED PKTGEN_NIC_MODEL <<< "$selected_line"

        echo "==> Selected: $PKTGEN_NIC_NAME ($PKTGEN_NIC_PCI)"
        rm -f /tmp/nic_info_$$.tmp
    fi

    # Update NIC info in config
    if [ -n "$PKTGEN_NIC_NAME" ]; then
        update_config_value "PKTGEN_NIC_PCI" "$PKTGEN_NIC_PCI" "$CONFIG_FILE"
        update_config_value "PKTGEN_NIC_MAC" "$PKTGEN_NIC_MAC" "$CONFIG_FILE"
        update_config_value "PKTGEN_NIC_IP" "$PKTGEN_NIC_IP" "$CONFIG_FILE"
    fi
fi

# Update timestamp
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
sed -i "s/^# Last updated:.*$/# Last updated: $TIMESTAMP/" "$CONFIG_FILE"

echo ""
echo "Configuration updated: $CONFIG_FILE"
