#!/bin/bash
# run with sudo

# reserve huge pages
for n in /sys/devices/system/node/node*; do
echo 5192 > ${n}/hugepages/hugepages-2048kB/nr_hugepages
done

cat /proc/meminfo | grep Huge