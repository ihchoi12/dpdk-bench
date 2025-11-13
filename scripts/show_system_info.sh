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
lscpu | grep "NUMA node[0-9]" | while read line; do
  node=$(echo $line | awk '{print $1 " " $2}' | sed 's/://')
  cpus=$(echo $line | awk '{print $NF}')
  echo "$node: $cpus"
done

echo ""
echo "=== NIC DEVICES ==="
lspci | grep -i ethernet

echo ""
echo "=== NETWORK PORT STATUS ==="
for dev in $(ls /sys/class/net/ | grep -v lo); do
  speed=$(ethtool $dev 2>/dev/null | grep "Speed:" | awk '{print $2}')
  duplex=$(ethtool $dev 2>/dev/null | grep "Duplex:" | awk '{print $2}')
  link=$(ethtool $dev 2>/dev/null | grep "Link detected:" | awk '{print $3}')
  if [ -n "$speed" ] && [ "$speed" != "Unknown!" ]; then
    pci_addr=$(ethtool -i $dev 2>/dev/null | grep "bus-info:" | awk '{print $2}')
    numa_node=$(cat /sys/class/net/$dev/device/numa_node 2>/dev/null || echo "N/A")
    echo "$dev ($pci_addr): $speed $duplex (Link: $link, NUMA: $numa_node)"
  fi
done
