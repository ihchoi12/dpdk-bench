#!/usr/bin/env python3
"""
DPDK Benchmark Test Runner
Runs l3fwd on node8 and pktgen on node7, saves results to files with pyrem
"""

import argparse
import os
import time
import math
import operator
import pyrem.host
import pyrem.task
from pyrem.host import RemoteHost
import pyrem
import sys
import glob

import numpy as np
import matplotlib.pyplot as plt
import matplotlib.ticker as tick
from math import factorial, exp
from datetime import datetime
import signal
import atexit
from os.path import exists

import subprocess
from cycler import cycler

import datetime
import pty


from test_config import *

final_result = ''
experiment_id = ''


def kill_procs():
    """Kill DPDK processes on all nodes"""
    cmd = ['sudo pkill -f dpdk-l3fwd ; \
            sudo pkill -f pktgen ']
    
    for node in ALL_NODES:
        host = pyrem.host.RemoteHost(node)
        task = host.run(cmd, quiet=False)
        pyrem.task.Parallel([task], aggregate=True).start(wait=True)
    
    print('KILLED LEGACY PROCESSES')

# Setup ARP tables
def setup_arp_tables():
    """Setup ARP tables on all nodes"""
    arp_task = []
    for node in ALL_NODES:
        host = pyrem.host.RemoteHost(node)
        cmd = [f'sudo arp -f {DPDK_BENCH_HOME}/scripts/arp_table']
        task = host.run(cmd, quiet=True)
        arp_task.append(task)
    pyrem.task.Parallel(arp_task, aggregate=True).start(wait=True)

def run_l3fwd():
    """Run l3fwd on node8"""
    global experiment_id
    print('RUNNING L3FWD on node8')
    
    host = pyrem.host.RemoteHost(L3FWD_CONFIG["node"])
    cmd = [f'cd {os.path.dirname(L3FWD_CONFIG["binary_path"])} && '
           f'sudo -E {ENV} ' 
           f'{L3FWD_CONFIG["binary_path"]} '
           f'{L3FWD_CONFIG["lcores"]} '
           f'{L3FWD_CONFIG["memory_channels"]} '
           f'-a {L3FWD_CONFIG["pci_address"]} '
           f'-- {L3FWD_CONFIG["port_mask"]} '
           f'--config="{L3FWD_CONFIG["config"]}" '
           f'--eth-dest=0,{L3FWD_CONFIG["eth_dest"]} '
           f'> {DATA_PATH}/{experiment_id}.l3fwd 2>&1']
    
    task = host.run(cmd, quiet=False)
    pyrem.task.Parallel([task], aggregate=True).start(wait=False)
    # Format and print L3FWD command with line breaks for readability
    cmd_formatted = cmd[0].replace(' && ', ' &&\n    ').replace(' -', '\n    -').replace(' --', '\n    --')
    # Remove multiple consecutive newlines and fix spacing
    cmd_formatted = '\n    '.join(line.strip() for line in cmd_formatted.split('\n') if line.strip())
    print(f'L3FWD command: {cmd}\n\n    {cmd_formatted}')
    # time.sleep(10)

def run_pktgen():
    """Run pktgen on node7"""
    global experiment_id
    print('RUNNING PKTGEN on node7')
    
    host = pyrem.host.RemoteHost(PKTGEN_CONFIG["node"])
    cmd = [f'cd {PKTGEN_CONFIG["working_dir"]} && '
           f'sudo -E {ENV} '
           f'{PKTGEN_CONFIG["binary_path"]} '
           f'{PKTGEN_CONFIG["lcores"]} '
           f'{PKTGEN_CONFIG["memory_channels"]} '
           f'-a {PKTGEN_CONFIG["pci_address"]} '
           f'{PKTGEN_CONFIG["proc_type"]} '
           f'--file-prefix={PKTGEN_CONFIG["file_prefix"]} '
           f'-- -m "{PKTGEN_CONFIG["port_map"]}" '
           f'{PKTGEN_CONFIG["app_args"]} '
           f'-f {PKTGEN_CONFIG["script_file"]} '
           f'> {DATA_PATH}/{experiment_id}.pktgen 2>&1']
    
    task = host.run(cmd, quiet=False)
    pyrem.task.Parallel([task], aggregate=True).start(wait=False)
    
    # Format and print L3FWD command with line breaks for readability
    cmd_formatted = cmd[0].replace(' && ', ' &&\n    ').replace(' -', '\n    -').replace(' --', '\n    --')
    # Remove multiple consecutive newlines and fix spacing
    cmd_formatted = '\n    '.join(line.strip() for line in cmd_formatted.split('\n') if line.strip())
    print(f'PKTGEN command: {cmd}\n\n    {cmd_formatted}')
    
    time.sleep(10)

def parse_dpdk_results(experiment_id):
    """Parse DPDK test results from l3fwd and pktgen"""
    import re
    result_str = ''
    
    # Parse L3FWD results
    l3fwd_file = f'{DATA_PATH}/{experiment_id}.l3fwd'
    l3fwd_throughput = 0
    l3fwd_status = 'unknown'
    
    if os.path.exists(l3fwd_file):
        with open(l3fwd_file, "r") as file:
            l3fwd_text = file.read()
            
        # Look for packet forwarding rate
        rate_match = re.search(r'(\d+\.?\d*)\s*Mpps', l3fwd_text)
        if rate_match:
            l3fwd_throughput = float(rate_match.group(1))
            l3fwd_status = 'success'
        elif 'Error' in l3fwd_text or 'error' in l3fwd_text:
            l3fwd_status = 'error'
        else:
            l3fwd_status = 'running'
    
    # Parse Pktgen results  
    pktgen_file = f'{DATA_PATH}/{experiment_id}.pktgen'
    pktgen_throughput = 0
    pktgen_status = 'unknown'
    
    if os.path.exists(pktgen_file):
        with open(pktgen_file, "r") as file:
            pktgen_text = file.read()
            
        # Look for transmission rate
        rate_match = re.search(r'Tx:\s*(\d+\.?\d*)\s*Mpps', pktgen_text)
        if rate_match:
            pktgen_throughput = float(rate_match.group(1))
            pktgen_status = 'success'
        elif 'Error' in pktgen_text or 'error' in pktgen_text:
            pktgen_status = 'error'
        else:
            pktgen_status = 'running'
    
    print(f"L3FWD: {l3fwd_throughput} Mpps ({l3fwd_status})")
    print(f"Pktgen: {pktgen_throughput} Mpps ({pktgen_status})")
    
    result_str += f'{experiment_id}, {l3fwd_throughput}, {pktgen_throughput}, {l3fwd_status}, {pktgen_status}\n'
    return result_str

def run_eval():
    """Main DPDK evaluation function"""
    global experiment_id
    global final_result
    
    kill_procs()
    experiment_id = datetime.datetime.now().strftime('%Y%m%d-%H%M%S.%f')
    print(f'================ RUNNING DPDK TEST =================')
    print(f'EXPTID: {experiment_id}')
    
    setup_arp_tables()
    
    # Run L3FWD
    run_l3fwd()
    
    # Run Pktgen
    run_pktgen()
    
    # Wait for test duration
    print(f'Running test for {TEST_DURATION} seconds...')
    time.sleep(TEST_DURATION)
    
    # Stop processes
    kill_procs()
    
    # Parse results
    print(f'================ {experiment_id} TEST COMPLETE =================')
    res = parse_dpdk_results(experiment_id)
    final_result = final_result + f'{res}'
    
        
    time.sleep(2)  # Brief pause between tests



def exiting():
    """Exit handler for cleanup"""
    global final_result
    print('EXITING')
    result_header = "experiment_id, l3fwd_mpps, pktgen_mpps, l3fwd_status, pktgen_status\n"
        
    print(f'\n\n\n\n\n{result_header}')
    print(final_result)
    with open(f'{DATA_PATH}/dpdk_benchmark_results.txt', "w") as file:
        file.write(f'{result_header}')
        file.write(final_result)
    kill_procs()


def run_compile():
    """Compile DPDK applications"""
    print("Building DPDK applications...")
    
    # Build DPDK
    dpdk_build = os.system(f"cd {DPDK_PATH} && meson build && ninja -C build")
    if dpdk_build != 0:
        print("DPDK build failed")
        return dpdk_build
    
    # Build Pktgen
    pktgen_build = os.system(f"cd {PKTGEN_PATH} && meson build && ninja -C build")
    if pktgen_build != 0:
        print("Pktgen build failed")
        return pktgen_build
        
    print("Build completed successfully")
    return 0


if __name__ == '__main__':
    # Create data directory if it doesn't exist
    os.makedirs(DATA_PATH, exist_ok=True)
    os.makedirs(RESULTS_PATH, exist_ok=True)
    
    if len(sys.argv) > 1 and sys.argv[1] == 'build':
        exit(run_compile())
    
    atexit.register(exiting)
    
    print("Starting DPDK Benchmark Tests")
    print(f"L3FWD Node: {L3FWD_CONFIG['node']}")
    print(f"Pktgen Node: {PKTGEN_CONFIG['node']}")
    print(f"Test Duration: {TEST_DURATION} seconds")
    print(f"Data Path: {DATA_PATH}")
    run_eval()
    kill_procs()