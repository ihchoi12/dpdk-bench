import os
import pandas as pd
import numpy as np

################## PATHS #####################
HOME = os.path.expanduser("~")
LOCAL = HOME.replace("/homes", "/local")
DPDK_BENCH_HOME = f'{HOME}/Autokernel/dpdk-bench'
DPDK_PATH = f'{DPDK_BENCH_HOME}/dpdk'
PKTGEN_PATH = f'{DPDK_BENCH_HOME}/Pktgen-DPDK'
RESULTS_PATH = f'{DPDK_BENCH_HOME}/results'
SCRIPTS_PATH = f'{DPDK_BENCH_HOME}/scripts'

################## CLUSTER CONFIG #####################
ALL_NODES = ['node7', 'node8']
PKTGEN_NODE = 'node7'
L3FWD_NODE = 'node8'
NODE7_IP = '10.0.1.7'
NODE7_MAC = '08:c0:eb:b6:cd:5d'
NODE8_IP = '10.0.1.8' 
NODE8_MAC = '08:c0:eb:b6:e8:05'


################## DPDK CONFIG #####################

def get_l3fwd_config(lcore_count):
    """Generate L3FWD configuration for given lcore count"""
    # L3FWD uses cores 1 to lcore_count (core 0 is main)
    lcores = f"-l 0-{lcore_count}"
    
    # Generate config string: (port,queue,lcore) for each working core
    config_parts = []
    for i in range(1, lcore_count + 1):
        queue_id = i - 1  # Queue starts from 0
        config_parts.append(f"(0,{queue_id},{i})")
    config = ",".join(config_parts)
    
    return {
        "binary_path": f"{DPDK_PATH}/build/examples/dpdk-l3fwd",
        "node": "node8", 
        "lcores": lcores,
        "memory_channels": "-n 4",
        "pci_address": "0000:31:00.1,txqs_min_inline=0",
        "port_mask": "-p 0x1",
        "config": config,
        "eth_dest": "08:c0:eb:b6:cd:5d"
    }

def get_pktgen_config(lcore_count):
    """Generate PKTGEN configuration for given lcore count"""
    # PKTGEN uses core 0 as main, then splits remaining cores into RX:TX
    # For lcore_count N: cores 0-(N) where core 0 is main, 1 to N/2 are RX, N/2+1 to N are TX
    lcores = f"-l 0-{lcore_count}"
    
    # Split cores for RX and TX (excluding core 0)
    rx_start = 1
    rx_end = lcore_count // 2
    tx_start = rx_end + 1 
    tx_end = lcore_count
    
    # Generate port_map: [RX_start-RX_end:TX_start-TX_end].port
    port_map = f"[{rx_start}-{rx_end}:{tx_start}-{tx_end}].0"
    
    return {
        "binary_path": f"{PKTGEN_PATH}/build/app/pktgen",
        "working_dir": f"{PKTGEN_PATH}",
        "node": "node7",
        "lcores": lcores,
        "memory_channels": "-n 4", 
        "pci_address": "0000:31:00.1,txqs_min_inline=0",
        "proc_type": "--proc-type auto",
        "file_prefix": "pktgen1",
        "port_map": port_map,
        "app_args": "-P -T",
        "script_file": "scripts/simple-tx-test.lua"
    }

# Default configurations (for backward compatibility)
L3FWD_CONFIG = get_l3fwd_config(4)  # Default to 4 lcores
PKTGEN_CONFIG = get_pktgen_config(14)  # Default to 14 lcores

################## TEST CONFIG #####################
PKTGEN_DURATION = 5  # Duration in seconds for pktgen transmission
PKTGEN_PACKET_SIZE = 64  # Packet size in bytes

# L3FWD Descriptor configuration
L3FWD_TX_DESC_VALUES = [1024] #[128, 512, 1024, 1024*2, 1024*4, 1024*8, 1024*16, 1024*32]  # L3FWD TX descriptor sizes
L3FWD_RX_DESC_VALUES = [1024]  # L3FWD RX descriptor sizes

# PKTGEN TX Descriptor configuration  
PKTGEN_TX_DESC_VALUES = [1024]  # PKTGEN TX descriptor sizes - simplified for testing

# LCORE test configuration  
# L3FWD LCORE configuration - can use any number of cores
L3FWD_LCORE_COUNTS = [2]  # L3FWD core counts to test
L3FWD_LCORE_VALUES = L3FWD_LCORE_COUNTS

# PKTGEN LCORE configuration - must use even numbers for balanced RX:TX splitting
PKTGEN_LCORE_COUNTS = [2, 4, 6, 8, 10, 12, 14]  # Even numbers only for balanced RX:TX splitting
PKTGEN_LCORE_VALUES = PKTGEN_LCORE_COUNTS

################## BUILD CONFIG #####################
LIBOS = 'dpdk'  # DPDK-based applications
# FEATURES = [
#     'high-performance',
#     'low-latency',
# ]


################## ENV VARS #####################
### DPDK ###
ENV = f'LD_LIBRARY_PATH={DPDK_PATH}/build/lib:{DPDK_PATH}/build/lib/x86_64-linux-gnu'
### DATA COLLECTION ###
DATA_PATH = f'{DPDK_BENCH_HOME}/results'

# Remove unused imports and configs

# commands
# python3 -u run_test.py 2>&1 | tee -a /homes/inho/Autokernel/dpdk-bench/results/experiment_history.txt
# python3 run_test.py build