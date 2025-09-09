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
import re
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

def run_l3fwd(tx_desc_value=None):
    """Run l3fwd on node8"""
    global experiment_id
    print(f'RUNNING L3FWD on node8 with TX_DESC={tx_desc_value}')
    
    host = pyrem.host.RemoteHost(L3FWD_CONFIG["node"])
    
    # Build tx-queue-size argument if specified
    tx_queue_arg = ""
    if tx_desc_value:
        tx_queue_arg = f" --tx-queue-size={tx_desc_value}"
    
    cmd = [f'cd {os.path.dirname(L3FWD_CONFIG["binary_path"])} && '
           f'sudo -E {ENV} ' 
           f'{L3FWD_CONFIG["binary_path"]} '
           f'{L3FWD_CONFIG["lcores"]} '
           f'{L3FWD_CONFIG["memory_channels"]} '
           f'-a {L3FWD_CONFIG["pci_address"]} '
           f'-- {L3FWD_CONFIG["port_mask"]} '
           f'--config="{L3FWD_CONFIG["config"]}" '
           f'--eth-dest=0,{L3FWD_CONFIG["eth_dest"]}'
           f'{tx_queue_arg} '
           f'> {DATA_PATH}/{experiment_id}.l3fwd 2>&1']
    
    task = host.run(cmd, quiet=False)
    print(f'L3FWD command: {cmd}')
    pyrem.task.Parallel([task], aggregate=True).start(wait=False)
    time.sleep(3)

def run_pktgen():
    """Run pktgen on node7"""
    global experiment_id
    print('RUNNING PKTGEN on node7')
    
    host = pyrem.host.RemoteHost(PKTGEN_CONFIG["node"])
    cmd = [f'cd {PKTGEN_CONFIG["working_dir"]} && '
           f'sudo -E {ENV} '
           f'PKTGEN_DURATION={PKTGEN_DURATION} '
           f'PKTGEN_PACKET_SIZE={PKTGEN_PACKET_SIZE} '
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

def parse_dpdk_results(experiment_id, tx_desc_value=None):
    """Parse DPDK test results from l3fwd and pktgen"""
    result_str = ''
    
    # Parse L3FWD results
    l3fwd_file = f'{DATA_PATH}/{experiment_id}.l3fwd'
    l3fwd_rx_pkts = 0
    l3fwd_tx_pkts = 0
    l3fwd_hw_rx_missed = 0
    l3fwd_l3_misses = 0
    l3fwd_l2_hit = 0
    l3fwd_l3_hit = 0
    l3fwd_dram_read = 0
    l3fwd_dram_write = 0
    l3fwd_read_bw = 0
    l3fwd_write_bw = 0
    l3fwd_status = 'unknown'
    
    if os.path.exists(l3fwd_file):
        try:
            with open(l3fwd_file, "r", encoding='utf-8', errors='ignore') as file:
                l3fwd_text = file.read()
                
            # Look for Total RX/TX packets in L3FWD Packet Statistics section only
            # Pattern: "Total    418860446    384005423                          8.3"
            # Look for the section between "L3FWD Packet Statistics Summary" and "====="
            packet_stats_pattern = r'L3FWD Packet Statistics Summary.*?Total\s+(\d+)\s+(\d+).*?====='
            packet_stats_match = re.search(packet_stats_pattern, l3fwd_text, re.DOTALL)
            if packet_stats_match:
                l3fwd_rx_pkts = int(packet_stats_match.group(1))
                l3fwd_tx_pkts = int(packet_stats_match.group(2))
                l3fwd_status = 'success'
                print(f"DEBUG L3FWD: Found L3FWD packet statistics Total: RX={l3fwd_rx_pkts}, TX={l3fwd_tx_pkts}")
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
                    
            # Extract Hardware RX Missed from L3FWD
            hw_rx_missed_match = re.search(r'Hardware RX Missed:\s+(\d+)', l3fwd_text)
            if hw_rx_missed_match:
                l3fwd_hw_rx_missed = int(hw_rx_missed_match.group(1))
                print(f"DEBUG L3FWD: Found Hardware RX Missed: {l3fwd_hw_rx_missed}")
                
            # Extract Intel PCM Core Performance Statistics from L3FWD
            pcm_core_pattern = r'Intel PCM Core Performance Statistics.*?Core\s+Cycles.*?Instructions.*?IPC.*?L3 Misses.*?L2 Hit%.*?L3 Hit%.*?Freq.*?CPU%.*?Energy.*?----.*?----.*?----.*?----.*?---------.*?------.*?------.*?----.*?----.*?------.*?(.*?)----.*?----.*?---------.*?------.*?------.*?----.*?----.*?------'
            pcm_match = re.search(pcm_core_pattern, l3fwd_text, re.DOTALL)
            l3fwd_l3_misses = 0
            l3fwd_l2_hit = 0
            l3fwd_l3_hit = 0
            
            if pcm_match:
                pcm_data = pcm_match.group(1)
                # Extract individual core stats (exclude core 0)
                core_lines = re.findall(r'(\d+)\s+\d+\s+\d+\s+[\d\.]+\s+(\d+)\s+([\d\.]+)\s+([\d\.]+)', pcm_data)
                
                l3fwd_cores = []  # cores excluding 0
                
                for core_id, l3_misses, l2_hit, l3_hit in core_lines:
                    core_num = int(core_id)
                    if core_num != 0:  # exclude core 0
                        l3fwd_cores.append((int(l3_misses), float(l2_hit), float(l3_hit)))
                
                if l3fwd_cores:
                    l3fwd_l3_misses = round(sum(x[0] for x in l3fwd_cores) / len(l3fwd_cores), 1)
                    l3fwd_l2_hit = round(sum(x[1] for x in l3fwd_cores) / len(l3fwd_cores), 1)
                    l3fwd_l3_hit = round(sum(x[2] for x in l3fwd_cores) / len(l3fwd_cores), 1)
                    
                print(f"DEBUG L3FWD: Active cores (excluding 0) - L3 Misses: {l3fwd_l3_misses}, L2 Hit%: {l3fwd_l2_hit}, L3 Hit%: {l3fwd_l3_hit}")
                
            # Extract Intel PCM Memory Performance Statistics - Socket 1 only  
            memory_start = l3fwd_text.find('Intel PCM Memory Performance Statistics')
            l3fwd_dram_read = 0
            l3fwd_dram_write = 0
            l3fwd_read_bw = 0
            l3fwd_write_bw = 0
            
            if memory_start != -1:
                # Look for the next section or end of memory section
                memory_end = l3fwd_text.find('Intel PCM I/O Performance Statistics', memory_start)
                if memory_end == -1:
                    memory_end = memory_start + 1000  # fallback
                
                memory_section = l3fwd_text[memory_start:memory_end]
                # Look for Socket 1 line: "1      849920       1364032      81.1       130.1      0.2      0        80.0"
                socket1_match = re.search(r'^1\s+(\d+)\s+(\d+)\s+([\d\.]+)\s+([\d\.]+)', memory_section, re.MULTILINE)
                if socket1_match:
                    l3fwd_dram_read = int(socket1_match.group(1))
                    l3fwd_dram_write = int(socket1_match.group(2))
                    l3fwd_read_bw = float(socket1_match.group(3))
                    l3fwd_write_bw = float(socket1_match.group(4))
                    print(f"DEBUG L3FWD: Socket 1 - DRAM Read: {l3fwd_dram_read}, DRAM Write: {l3fwd_dram_write}, Read BW: {l3fwd_read_bw}, Write BW: {l3fwd_write_bw}")
                else:
                    print(f"DEBUG L3FWD: Socket 1 memory data not found in section")
            else:
                print(f"DEBUG L3FWD: Intel PCM Memory Performance Statistics section not found")
                
            # Extract Intel PCM I/O Performance Statistics - Socket 1 only
            io_start = l3fwd_text.find('Intel PCM I/O Performance Statistics')
            l3fwd_pcie_read = 0
            l3fwd_pcie_write = 0
            l3fwd_pcie_read_bw = 0
            l3fwd_pcie_write_bw = 0
            
            if io_start != -1:
                # Look for the next section or end of I/O section
                io_end = l3fwd_text.find('Intel PCM System-Wide Statistics', io_start)
                if io_end == -1:
                    io_end = io_start + 1000  # fallback
                
                io_section = l3fwd_text[io_start:io_end]
                # Look for Socket 1 line: "1      288364       398784       27.5       38.0       0.0       0.09     0.12"
                socket1_io_match = re.search(r'^1\s+(\d+)\s+(\d+)\s+([\d\.]+)\s+([\d\.]+)', io_section, re.MULTILINE)
                if socket1_io_match:
                    l3fwd_pcie_read = int(socket1_io_match.group(1))
                    l3fwd_pcie_write = int(socket1_io_match.group(2))
                    l3fwd_pcie_read_bw = float(socket1_io_match.group(3))
                    l3fwd_pcie_write_bw = float(socket1_io_match.group(4))
                    print(f"DEBUG L3FWD: Socket 1 - PCIe Read: {l3fwd_pcie_read}, PCIe Write: {l3fwd_pcie_write}, PCIe R BW: {l3fwd_pcie_read_bw}, PCIe W BW: {l3fwd_pcie_write_bw}")
                else:
                    print(f"DEBUG L3FWD: Socket 1 I/O data not found in section")
            else:
                print(f"DEBUG L3FWD: Intel PCM I/O Performance Statistics section not found")
        except Exception as e:
            print(f"ERROR parsing L3FWD file {l3fwd_file}: {e}")
            l3fwd_status = 'error'
    
    # Parse Pktgen results  
    pktgen_file = f'{DATA_PATH}/{experiment_id}.pktgen'
    pktgen_rx_pkts = 0
    pktgen_tx_pkts = 0
    pktgen_hw_rx_missed = 0
    pktgen_rx_l3_misses = 0
    pktgen_rx_l2_hit = 0
    pktgen_rx_l3_hit = 0
    pktgen_tx_l3_misses = 0
    pktgen_tx_l2_hit = 0
    pktgen_tx_l3_hit = 0
    pktgen_dram_read = 0
    pktgen_dram_write = 0
    pktgen_read_bw = 0
    pktgen_write_bw = 0
    pktgen_status = 'unknown'
    
    if os.path.exists(pktgen_file):
        try:
            with open(pktgen_file, "r", encoding='utf-8', errors='ignore') as file:
                pktgen_text = file.read()
                
            # Look for Total RX/TX packets in PKTGEN Packet Statistics Summary section only
            # Pattern: "Total    384740568    611909280                          59.0"
            # Look for the section between "PKTGEN Packet Statistics Summary" and "====="
            packet_stats_pattern = r'PKTGEN Packet Statistics Summary.*?Total\s+(\d+)\s+(\d+).*?====='
            packet_stats_match = re.search(packet_stats_pattern, pktgen_text, re.DOTALL)
            if packet_stats_match:
                pktgen_rx_pkts = int(packet_stats_match.group(1))
                pktgen_tx_pkts = int(packet_stats_match.group(2))
                pktgen_status = 'success'
                print(f"DEBUG Pktgen: Found PKTGEN packet statistics Total: RX={pktgen_rx_pkts}, TX={pktgen_tx_pkts}")
            else:
                # If no Total line found, try to sum individual lcore stats
                # Pattern: "1        50349059     0            10.0       0.0        100.0"
                lcore_matches = re.findall(r'^\s*(\d+)\s+(\d+)\s+(\d+)\s+[\d\.]+\s+[\d\.]+\s+[\d\.]+', pktgen_text, re.MULTILINE)
                if lcore_matches:
                    # Remove duplicates by using unique lcore IDs (take last occurrence of each lcore)
                    lcore_dict = {}
                    for match in lcore_matches:
                        lcore_id = int(match[0])
                        lcore_dict[lcore_id] = (int(match[1]), int(match[2]))  # (RX, TX)
                    
                    pktgen_rx_pkts = sum(rx for rx, tx in lcore_dict.values())
                    pktgen_tx_pkts = sum(tx for rx, tx in lcore_dict.values())
                    pktgen_status = 'success'
                    print(f"DEBUG Pktgen: No Total line found, summed {len(lcore_dict)} unique lcore stats: RX={pktgen_rx_pkts}, TX={pktgen_tx_pkts}")
                elif 'Error' in pktgen_text or 'error' in pktgen_text:
                    pktgen_status = 'error'
                else:
                    pktgen_status = 'running'
                    print(f"DEBUG Pktgen: No Total or lcore lines found in {pktgen_file}")
                    # Debug: show first few lines to understand content
                    lines = pktgen_text.split('\n')[:10]
                    print(f"DEBUG Pktgen: First 10 lines: {lines}")
                    
            # Extract Hardware RX Missed from Pktgen
            hw_rx_missed_match = re.search(r'Hardware RX Missed:\s+(\d+)', pktgen_text)
            if hw_rx_missed_match:
                pktgen_hw_rx_missed = int(hw_rx_missed_match.group(1))
                print(f"DEBUG Pktgen: Found Hardware RX Missed: {pktgen_hw_rx_missed}")
                
            # Extract Intel PCM Core Performance Statistics from Pktgen
            pcm_core_pattern = r'Intel PCM Core Performance Statistics.*?Core\s+Cycles.*?Instructions.*?IPC.*?L3 Misses.*?L2 Hit%.*?L3 Hit%.*?Freq.*?CPU%.*?Energy.*?----.*?----.*?----.*?----.*?---------.*?------.*?------.*?----.*?----.*?------.*?(.*?)----.*?----.*?---------.*?------.*?------.*?----.*?----.*?------'
            pcm_match = re.search(pcm_core_pattern, pktgen_text, re.DOTALL)
            pktgen_rx_l3_misses = 0
            pktgen_rx_l2_hit = 0
            pktgen_rx_l3_hit = 0
            pktgen_tx_l3_misses = 0
            pktgen_tx_l2_hit = 0
            pktgen_tx_l3_hit = 0
            
            if pcm_match:
                pcm_data = pcm_match.group(1)
                # Extract individual core stats
                core_lines = re.findall(r'(\d+)\s+\d+\s+\d+\s+[\d\.]+\s+(\d+)\s+([\d\.]+)\s+([\d\.]+)', pcm_data)
                
                rx_cores = []  # cores 1-8 for RX
                tx_cores = []  # cores 9-15 for TX
                
                for core_id, l3_misses, l2_hit, l3_hit in core_lines:
                    core_num = int(core_id)
                    if 1 <= core_num <= 8:
                        rx_cores.append((int(l3_misses), float(l2_hit), float(l3_hit)))
                    elif 9 <= core_num <= 15:
                        tx_cores.append((int(l3_misses), float(l2_hit), float(l3_hit)))
                
                if rx_cores:
                    pktgen_rx_l3_misses = round(sum(x[0] for x in rx_cores) / len(rx_cores), 1)
                    pktgen_rx_l2_hit = round(sum(x[1] for x in rx_cores) / len(rx_cores), 1)
                    pktgen_rx_l3_hit = round(sum(x[2] for x in rx_cores) / len(rx_cores), 1)
                    
                if tx_cores:
                    pktgen_tx_l3_misses = round(sum(x[0] for x in tx_cores) / len(tx_cores), 1)
                    pktgen_tx_l2_hit = round(sum(x[1] for x in tx_cores) / len(tx_cores), 1)
                    pktgen_tx_l3_hit = round(sum(x[2] for x in tx_cores) / len(tx_cores), 1)
                    
                print(f"DEBUG Pktgen: RX cores (1-8) - L3 Misses: {pktgen_rx_l3_misses}, L2 Hit%: {pktgen_rx_l2_hit}, L3 Hit%: {pktgen_rx_l3_hit}")
                print(f"DEBUG Pktgen: TX cores (9-15) - L3 Misses: {pktgen_tx_l3_misses}, L2 Hit%: {pktgen_tx_l2_hit}, L3 Hit%: {pktgen_tx_l3_hit}")
                
            # Extract Intel PCM Memory Performance Statistics from Pktgen (Socket 1)
            # Extract Intel PCM Memory Performance Statistics - Socket 1 only
            memory_start = pktgen_text.find('Intel PCM Memory Performance Statistics')
            pktgen_dram_read = 0
            pktgen_dram_write = 0
            pktgen_read_bw = 0
            pktgen_write_bw = 0
            
            if memory_start != -1:
                # Look for the next section or end of memory section
                memory_end = pktgen_text.find('Intel PCM I/O Performance Statistics', memory_start)
                if memory_end == -1:
                    memory_end = memory_start + 1000  # fallback
                
                memory_section = pktgen_text[memory_start:memory_end]
                # Look for Socket 1 line: "1      849920       1364032      81.1       130.1      0.2      0        80.0"
                socket1_match = re.search(r'^1\s+(\d+)\s+(\d+)\s+([\d\.]+)\s+([\d\.]+)', memory_section, re.MULTILINE)
                if socket1_match:
                    pktgen_dram_read = int(socket1_match.group(1))
                    pktgen_dram_write = int(socket1_match.group(2))
                    pktgen_read_bw = float(socket1_match.group(3))
                    pktgen_write_bw = float(socket1_match.group(4))
                    print(f"DEBUG Pktgen: Socket 1 - DRAM Read: {pktgen_dram_read}, DRAM Write: {pktgen_dram_write}, Read BW: {pktgen_read_bw}, Write BW: {pktgen_write_bw}")
                else:
                    print(f"DEBUG Pktgen: Socket 1 memory data not found in section")
            else:
                print(f"DEBUG Pktgen: Intel PCM Memory Performance Statistics section not found")
                
            # Extract Intel PCM I/O Performance Statistics - Socket 1 only
            io_start = pktgen_text.find('Intel PCM I/O Performance Statistics')
            pktgen_pcie_read = 0
            pktgen_pcie_write = 0
            pktgen_pcie_read_bw = 0
            pktgen_pcie_write_bw = 0
            
            if io_start != -1:
                # Look for the next section or end of I/O section
                io_end = pktgen_text.find('Intel PCM System-Wide Statistics', io_start)
                if io_end == -1:
                    io_end = io_start + 1000  # fallback
                
                io_section = pktgen_text[io_start:io_end]
                # Look for Socket 1 line: "1      245856       392083       23.4       37.4       0.0       0.08     0.12"
                socket1_io_match = re.search(r'^1\s+(\d+)\s+(\d+)\s+([\d\.]+)\s+([\d\.]+)', io_section, re.MULTILINE)
                if socket1_io_match:
                    pktgen_pcie_read = int(socket1_io_match.group(1))
                    pktgen_pcie_write = int(socket1_io_match.group(2))
                    pktgen_pcie_read_bw = float(socket1_io_match.group(3))
                    pktgen_pcie_write_bw = float(socket1_io_match.group(4))
                    print(f"DEBUG Pktgen: Socket 1 - PCIe Read: {pktgen_pcie_read}, PCIe Write: {pktgen_pcie_write}, PCIe R BW: {pktgen_pcie_read_bw}, PCIe W BW: {pktgen_pcie_write_bw}")
                else:
                    print(f"DEBUG Pktgen: Socket 1 I/O data not found in section")
            else:
                print(f"DEBUG Pktgen: Intel PCM I/O Performance Statistics section not found")
        except Exception as e:
            print(f"ERROR parsing Pktgen file {pktgen_file}: {e}")
            pktgen_status = 'error'
    
    print(f"L3FWD: RX={l3fwd_rx_pkts:,} TX={l3fwd_tx_pkts:,} ({l3fwd_status})")
    print(f"Pktgen: RX={pktgen_rx_pkts:,} TX={pktgen_tx_pkts:,} ({pktgen_status})")
    
    # Convert packet counts to Mpps (Million packets per second)
    duration_sec = PKTGEN_DURATION
    pktgen_rx_rate = round(pktgen_rx_pkts / (duration_sec * 1_000_000), 3)
    pktgen_tx_rate = round(pktgen_tx_pkts / (duration_sec * 1_000_000), 3)
    l3fwd_rx_rate = round(l3fwd_rx_pkts / (duration_sec * 1_000_000), 3)
    l3fwd_tx_rate = round(l3fwd_tx_pkts / (duration_sec * 1_000_000), 3)
    
    # Calculate failure metrics in M pkts (Million packets)
    l3fwd_tx_fails = round((l3fwd_rx_pkts - l3fwd_tx_pkts) / 1_000_000, 3)
    pktgen_rx_fails = round((l3fwd_tx_pkts - pktgen_rx_pkts) / 1_000_000, 3)
    
    result_str += f'{experiment_id}, {PKTGEN_PACKET_SIZE}, {tx_desc_value}, {pktgen_rx_rate}, {pktgen_tx_rate}, {l3fwd_rx_rate}, {l3fwd_tx_rate}, {l3fwd_tx_fails}, {pktgen_rx_fails}, {pktgen_hw_rx_missed}, {l3fwd_hw_rx_missed}, {pktgen_rx_l3_misses}, {pktgen_rx_l2_hit}, {pktgen_rx_l3_hit}, {pktgen_tx_l3_misses}, {pktgen_tx_l2_hit}, {pktgen_tx_l3_hit}, {l3fwd_l3_misses}, {l3fwd_l2_hit}, {l3fwd_l3_hit}, {pktgen_dram_read}, {pktgen_dram_write}, {pktgen_read_bw}, {pktgen_write_bw}, {l3fwd_dram_read}, {l3fwd_dram_write}, {l3fwd_read_bw}, {l3fwd_write_bw}, {pktgen_pcie_read}, {pktgen_pcie_write}, {pktgen_pcie_read_bw}, {pktgen_pcie_write_bw}, {l3fwd_pcie_read}, {l3fwd_pcie_write}, {l3fwd_pcie_read_bw}, {l3fwd_pcie_write_bw}\n'
    return result_str

def run_eval():
    """Main DPDK evaluation function"""
    global experiment_id
    global final_result
    
    print("Starting DPDK TX Descriptor Tests")
    print(f"Testing TX descriptor values: {TX_DESC_VALUES}")
    
    for tx_desc_value in TX_DESC_VALUES:
        print(f'\n================ TESTING TX_DESC={tx_desc_value} =================')
        
        kill_procs()
        experiment_id = datetime.datetime.now().strftime('%Y%m%d-%H%M%S.%f')
        print(f'EXPTID: {experiment_id}')
        
        setup_arp_tables()
        
        # Run L3FWD with specific TX descriptor value
        run_l3fwd(tx_desc_value)
        
        # Run Pktgen
        run_pktgen()
        
        # Stop processes
        kill_procs()
        time.sleep(3)
        
        # Parse results
        print(f'================ {experiment_id} TEST COMPLETE =================')
        res = parse_dpdk_results(experiment_id, tx_desc_value)
        final_result = final_result + f'{res}'
        
        # Wait a bit between tests
        time.sleep(5)
    
        



def exiting():
    """Exit handler for cleanup"""
    global final_result
    print('EXITING')
    result_header = "experiment_id, pkt_size, tx_desc_value, pktgen_rx_rate, pktgen_tx_rate, l3fwd_rx_rate, l3fwd_tx_rate, l3fwd_tx_fails, pktgen_rx_fails, pktgen_hw_rx_missed, l3fwd_hw_rx_missed, pktgen_rx_l3_misses, pktgen_rx_l2_hit%, pktgen_rx_l3_hit%, pktgen_tx_l3_misses, pktgen_tx_l2_hit%, pktgen_tx_l3_hit%, l3fwd_l3_misses, l3fwd_l2_hit%, l3fwd_l3_hit%, pktgen_dram_read, pktgen_dram_write, pktgen_read_bw, pktgen_write_bw, l3fwd_dram_read, l3fwd_dram_write, l3fwd_read_bw, l3fwd_write_bw, pktgen_pcie_read, pktgen_pcie_write, pktgen_pcie_read_bw, pktgen_pcie_write_bw, l3fwd_pcie_read, l3fwd_pcie_write, l3fwd_pcie_read_bw, l3fwd_pcie_write_bw\n"
        
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