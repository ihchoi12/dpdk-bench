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

    # Kill pktgen processes on node7
    node7_cmd = ['sudo pkill -f pktgen']
    node7 = pyrem.host.RemoteHost('node7')
    node7_task = node7.run(node7_cmd, quiet=False)
    
    # Kill dpdk-l3fwd more precisely - target the executable name only
    node8_cmd = ['sudo pkill dpdk-l3fwd']
    node8 = pyrem.host.RemoteHost('node8')
    node8_task = node8.run(node8_cmd, quiet=False)
    
    pyrem.task.Parallel([node7_task, node8_task], aggregate=True).start(wait=True)
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
    print(f'L3FWD command: {cmd}')
    pyrem.task.Parallel([task], aggregate=True).start(wait=False)
    time.sleep(3)
    # Format and print L3FWD command with line breaks for readability
    # cmd_formatted = cmd[0].replace(' && ', ' &&\n    ').replace(' -', '\n    -').replace(' --', '\n    --')
    # Remove multiple consecutive newlines and fix spacing
    # cmd_formatted = '\n    '.join(line.strip() for line in cmd_formatted.split('\n') if line.strip())
    # print(f'L3FWD command: {cmd}\n\n    {cmd_formatted}')
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
    print(f'PKTGEN command: {cmd}')
    pyrem.task.Parallel([task], aggregate=True).start(wait=True)
    
    # Format and print L3FWD command with line breaks for readability
    # cmd_formatted = cmd[0].replace(' && ', ' &&\n    ').replace(' -', '\n    -').replace(' --', '\n    --')
    # Remove multiple consecutive newlines and fix spacing
    # cmd_formatted = '\n    '.join(line.strip() for line in cmd_formatted.split('\n') if line.strip())
    # print(f'PKTGEN command: {cmd}\n\n    {cmd_formatted}')
    
    # time.sleep(3)

def parse_dpdk_results(experiment_id):
    """Parse DPDK test results from l3fwd and pktgen"""
    import re
    result_str = ''
    
    # Parse L3FWD results
    l3fwd_file = f'{DATA_PATH}/{experiment_id}.l3fwd'
    l3fwd_rx_pkts = 0
    l3fwd_tx_pkts = 0
    l3fwd_status = 'unknown'
    
    if os.path.exists(l3fwd_file):
        try:
            with open(l3fwd_file, "r", encoding='utf-8', errors='ignore') as file:
                l3fwd_text = file.read()
            
            # Remove ANSI escape sequences and control characters that might interfere
            import re
            ansi_escape = re.compile(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')
            l3fwd_text = ansi_escape.sub('', l3fwd_text)
            control_chars = re.compile(r'[\x00-\x1F\x7F-\x9F]')
            l3fwd_text = control_chars.sub('', l3fwd_text)
                
            # Look for Total RX/TX packets in L3FWD output
            # Pattern: "Total    344052981    256861708"
            total_matches = re.findall(r'Total\s+(\d+)\s+(\d+)', l3fwd_text)
            if total_matches:
                # Use the last occurrence (most recent stats)
                l3fwd_rx_pkts = int(total_matches[-1][0])
                l3fwd_tx_pkts = int(total_matches[-1][1])
                l3fwd_status = 'success'
                print(f"DEBUG L3FWD: Found {len(total_matches)} Total lines, using last one: RX={l3fwd_rx_pkts}, TX={l3fwd_tx_pkts}")
            else:
                # If no Total line found, try to sum individual lcore stats
                # Pattern: "0        83098188     64865061     7.7        6.0        21.9"
                lcore_matches = re.findall(r'^\s*(\d+)\s+(\d+)\s+(\d+)\s+[\d\.]+\s+[\d\.]+\s+[\d\.]+', l3fwd_text, re.MULTILINE)
                if lcore_matches:
                    # Remove duplicates by using unique lcore IDs (take last occurrence of each lcore)
                    lcore_dict = {}
                    for match in lcore_matches:
                        lcore_id = int(match[0])
                        lcore_dict[lcore_id] = (int(match[1]), int(match[2]))  # (RX, TX)
                    
                    l3fwd_rx_pkts = sum(rx for rx, tx in lcore_dict.values())
                    l3fwd_tx_pkts = sum(tx for rx, tx in lcore_dict.values())
                    l3fwd_status = 'success'
                    print(f"DEBUG L3FWD: No Total line found, summed {len(lcore_dict)} unique lcore stats: RX={l3fwd_rx_pkts}, TX={l3fwd_tx_pkts}")
                elif 'Error' in l3fwd_text or 'error' in l3fwd_text:
                    l3fwd_status = 'error'
                else:
                    l3fwd_status = 'running'
                    print(f"DEBUG L3FWD: No Total or lcore lines found in {l3fwd_file}")
                    # Debug: show first few lines to understand content
                    lines = l3fwd_text.split('\n')[:10]
                    print(f"DEBUG L3FWD: First 10 lines: {lines}")
        except Exception as e:
            print(f"ERROR parsing L3FWD file {l3fwd_file}: {e}")
            l3fwd_status = 'error'
    
    # Parse Pktgen results  
    pktgen_file = f'{DATA_PATH}/{experiment_id}.pktgen'
    pktgen_rx_pkts = 0
    pktgen_tx_pkts = 0
    pktgen_status = 'unknown'
    
    if os.path.exists(pktgen_file):
        try:
            with open(pktgen_file, "r", encoding='utf-8', errors='ignore') as file:
                pktgen_text = file.read()
                
            # Look for Total RX/TX packets in Pktgen output
            # Pattern: "Total    257710936    623995552"
            total_matches = re.findall(r'Total\s+(\d+)\s+(\d+)', pktgen_text)
            if total_matches:
                # Use the last occurrence (most recent stats)
                pktgen_rx_pkts = int(total_matches[-1][0])
                pktgen_tx_pkts = int(total_matches[-1][1])
                pktgen_status = 'success'
                print(f"DEBUG Pktgen: Found {len(total_matches)} Total lines, using last one: RX={pktgen_rx_pkts}, TX={pktgen_tx_pkts}")
            elif 'Error' in pktgen_text or 'error' in pktgen_text:
                pktgen_status = 'error'
            else:
                pktgen_status = 'running'
                print(f"DEBUG Pktgen: No Total line found in {pktgen_file}")
        except Exception as e:
            print(f"ERROR parsing Pktgen file {pktgen_file}: {e}")
            pktgen_status = 'error'
    
    print(f"L3FWD: RX={l3fwd_rx_pkts:,} TX={l3fwd_tx_pkts:,} ({l3fwd_status})")
    print(f"Pktgen: RX={pktgen_rx_pkts:,} TX={pktgen_tx_pkts:,} ({pktgen_status})")
    
    result_str += f'{experiment_id}, {l3fwd_rx_pkts}, {l3fwd_tx_pkts}, {pktgen_rx_pkts}, {pktgen_tx_pkts}, {l3fwd_status}, {pktgen_status}\n'
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
    
    
    # Stop processes
    kill_procs()
    time.sleep(3)
    # Parse results
    print(f'================ {experiment_id} TEST COMPLETE =================')
    res = parse_dpdk_results(experiment_id)
    final_result = final_result + f'{res}'
    
        



def exiting():
    """Exit handler for cleanup"""
    global final_result
    print('EXITING')
    result_header = "experiment_id, l3fwd_rx_pkts, l3fwd_tx_pkts, pktgen_rx_pkts, pktgen_tx_pkts, l3fwd_status, pktgen_status\n"
        
    print(f'\n\n\n\n\n{result_header}')
    print(final_result)
    with open(f'{DATA_PATH}/dpdk_benchmark_results.txt', "w") as file:
        file.write(f'{result_header}')
        file.write(final_result)


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
    print(f"Data Path: {DATA_PATH}")
    run_eval()