#!/bin/bash

echo "=== SYSTEM INFO ==="
# OS version
if [ -f /etc/os-release ]; then
  os_name=$(grep '^PRETTY_NAME=' /etc/os-release | cut -d'"' -f2)
  echo "OS: $os_name"
else
  echo "OS: $(uname -s)"
fi

# Kernel version
kernel_version=$(uname -r)
echo "Kernel: $kernel_version"

echo ""
echo "=== CPU INFO ==="
lscpu | grep 'Model name' | sed 's/Model name:/CPU:/'
gcc -march=native -Q --help=target 2>/dev/null | grep -- '-march=' | head -1 | awk '{print "Arch: " $2}'
sockets=$(lscpu | grep 'Socket(s):' | awk '{print $2}')
cores_per_socket=$(lscpu | grep 'Core(s) per socket:' | awk '{print $4}')
threads_per_core=$(lscpu | grep 'Thread(s) per core:' | awk '{print $4}')
physical_cores=$((sockets * cores_per_socket))
total_threads=$((physical_cores * threads_per_core))
echo "Sockets: $sockets × $cores_per_socket cores = $physical_cores physical cores"
echo "Threads: $physical_cores cores × $threads_per_core (HT) = $total_threads threads"

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
  if [ -n "${dpdk_ports[$pci_full]}" ]; then
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

    # Format IP info
    if [ -n "$ipv4" ]; then
      ip_info="IP: $ipv4"
    else
      ip_info="IP: none"
    fi

    # Format link status
    if [ "$link" = "yes" ] && [ -n "$speed" ] && [ "$speed" != "Unknown!" ]; then
      link_info="UP ($speed $duplex)"
    elif [ "$link" = "yes" ]; then
      link_info="UP (speed unknown)"
    else
      link_info="DOWN"
    fi

    echo "  Driver: kernel ($kernel_driver) | NUMA: $numa_node | Link: $link_info | $ip_info"
  else
    echo "  Driver: none | NUMA: $numa_node | Status: No interface detected"
  fi
  echo ""
done
