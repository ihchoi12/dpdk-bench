#!/bin/bash

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
echo "=== NIC DEVICES ==="
lspci | grep -i ethernet

echo ""
echo "=== NETWORK PORT STATUS ==="
echo "Kernel driver:"
for dev in $(ls /sys/class/net/ 2>/dev/null | grep -v lo); do
  speed=$(ethtool $dev 2>/dev/null | grep "Speed:" | awk '{print $2}')
  duplex=$(ethtool $dev 2>/dev/null | grep "Duplex:" | awk '{print $2}')
  link=$(ethtool $dev 2>/dev/null | grep "Link detected:" | awk '{print $3}')
  if [ -n "$speed" ] && [ "$speed" != "Unknown!" ]; then
    pci_addr=$(ethtool -i $dev 2>/dev/null | grep "bus-info:" | awk '{print $2}')
    numa_node=$(cat /sys/class/net/$dev/device/numa_node 2>/dev/null || echo "N/A")
    echo "  $dev ($pci_addr): $speed $duplex (Link: $link, NUMA: $numa_node)"
  fi
done

echo ""
echo "DPDK driver:"
# Check for DPDK-bound devices and temporarily unbind to get link speed
if [ -f "./dpdk/usertools/dpdk-devbind.py" ]; then
  dpdk_devs=$(./dpdk/usertools/dpdk-devbind.py --status 2>/dev/null | awk '/Network devices using DPDK-compatible driver/,/^$/' | grep "0000:" | grep -E "drv=(vfio-pci|uio_pci_generic|igb_uio)")
  if [ -n "$dpdk_devs" ]; then
    echo "$dpdk_devs" | while read line; do
      pci=$(echo $line | awk '{print $1}')
      desc=$(echo $line | cut -d"'" -f2)
      driver=$(echo $line | grep -o "drv=[^ ]*" | cut -d= -f2)
      unused=$(echo $line | grep -o "unused=[^ ]*" | cut -d= -f2 | cut -d, -f1)
      numa=$(echo $line | grep -o "numa_node=[0-9]*" | cut -d= -f2)

      echo -n "  $pci ($desc): "

      # Temporarily unbind from DPDK to check link speed
      sudo ./dpdk/usertools/dpdk-devbind.py --bind=$unused $pci 2>/dev/null
      sleep 0.5

      # Find interface name and get link speed
      iface=$(ls /sys/bus/pci/devices/$pci/net/ 2>/dev/null | head -1)
      if [ -n "$iface" ]; then
        sudo ip link set $iface up 2>/dev/null
        sleep 1
        link_speed=$(ethtool $iface 2>/dev/null | grep "Speed:" | awk '{print $2}')
        link_status=$(ethtool $iface 2>/dev/null | grep "Link detected:" | awk '{print $3}')
        echo -n "$link_speed (Link: $link_status) "
        sudo ip link set $iface down 2>/dev/null
      else
        echo -n "N/A "
      fi

      # Re-bind to DPDK
      sudo ./dpdk/usertools/dpdk-devbind.py --bind=$driver $pci 2>/dev/null

      echo "driver=$driver NUMA=$numa"
    done
  else
    echo "  (none)"
  fi
else
  echo "  (dpdk-devbind.py not found)"
fi
