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
# L3FWD Configuration
L3FWD_CONFIG = {
    "binary_path": f"{DPDK_PATH}/build/examples/dpdk-l3fwd",
    "node": "node8",
    "duration": 30,
    "lcores": "-l 0-3",
    "memory_channels": "-n 4", 
    "pci_address": "0000:31:00.1,txqs_min_inline=0,txq_mpw_en=1,txq_inline_mpw=256",
    "port_mask": "-p 0x1",
    "config": "(0,0,0),(0,1,1),(0,2,2),(0,3,3)",
    "eth_dest": "08:c0:eb:b6:cd:5d"
}

# Pktgen Configuration  
PKTGEN_CONFIG = {
    "binary_path": f"{PKTGEN_PATH}/build/app/pktgen",
    "working_dir": f"{PKTGEN_PATH}",
    "node": "node7",
    "duration": 30,
    "lcores": "-l 0-15",
    "memory_channels": "-n 4",
    "pci_address": "0000:31:00.1,txqs_min_inline=0,txq_mpw_en=1,txq_inline_mpw=256",
    "proc_type": "--proc-type auto",
    "file_prefix": "pktgen1", 
    "port_map": "[1-8:9-15].0",
    "app_args": "-P -T",
    "script_file": "scripts/simple-tx-test.lua"
}

################## TEST CONFIG #####################
REPEAT_NUM = 1
PACKET_SIZES = [64, 128, 256, 512, 1024, 1518]  # Packet sizes to test
TRAFFIC_RATES = [1, 10, 25, 50, 75, 100]  # Percentage of line rate
TEST_DURATION = 30  # seconds per test

################## BUILD CONFIG #####################
LIBOS = 'dpdk'  # DPDK-based applications
FEATURES = [
    'high-performance',
    'low-latency',
]

################## TEST CONFIG #####################
NUM_BACKENDS = 12
SERVER_APP = 'http-server' # 'capy-proxy', 'https', 'capybara-switch' 'http-server', 'prism', 'redis-server', 'proxy-server'
TLS = 0
CLIENT_APP = 'caladan' # 'wrk', 'caladan', 'redis-bench'
# NUM_THREADS = [1] # for wrk load generator
REPEAT_NUM = 1

TCPDUMP = False
EVAL_LATENCY = True
EVAL_THROUGHPUT = True  
EVAL_PACKET_LOSS = True

################## ENV VARS #####################
### DPDK ###
ENV = f'LD_LIBRARY_PATH={DPDK_PATH}/build/lib:{DPDK_PATH}/build/lib/x86_64-linux-gnu'
### DATA COLLECTION ###
DATA_PATH = f'{HOME}/dpdk-bench-data'

# Remove unused imports and configs