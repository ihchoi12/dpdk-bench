#!/bin/bash
# run with sudo

# Load MSR kernel module for PCM (Performance Counter Monitor)
echo "Loading MSR kernel module..."
modprobe msr
if [ $? -eq 0 ]; then
    echo "MSR module loaded successfully"
else
    echo "Warning: Failed to load MSR module. PCM monitoring may not work."
fi

# Disable NMI watchdog to free up hardware PMU counter for PCM
echo "Disabling NMI watchdog for PCM..."
sysctl -w kernel.nmi_watchdog=0

# Reserve huge pages
echo "Reserving huge pages..."
for n in /sys/devices/system/node/node*; do
    echo 5192 > ${n}/hugepages/hugepages-2048kB/nr_hugepages
done

echo ""
echo "Hugepage status:"
cat /proc/meminfo | grep Huge