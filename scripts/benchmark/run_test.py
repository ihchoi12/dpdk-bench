#!/usr/bin/env python3
"""
DPDK Benchmark Test Runner
Runs l3fwd and pktgen on configured cluster nodes, saves results to files with pyrem
Node configuration is defined in test_config.py CLUSTER CONFIG section
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

def fmt_count(n):
    """Format count: <1K as-is, ≥1K as K, ≥1M as M"""
    if n >= 1_000_000:
        return f"{n/1_000_000:.1f}M"
    elif n >= 1_000:
        return f"{n/1_000:.1f}K"
    return str(int(n))

def fmt_small_value(value, unit='M'):
    """Format small values with enough decimals to show first non-zero digit.
    For values >= 0.1, show 1 decimal. For smaller values, show up to first non-zero digit (rounded)."""
    if value == 0:
        return f"0{unit}"
    if value >= 0.1:
        return f"{value:.1f}{unit}"
    # Find first non-zero decimal place: e.g., 0.03 -> 2, 0.001 -> 3, 0.0004 -> 4
    decimals = -int(math.floor(math.log10(value)))
    decimals = min(decimals, 6)  # Cap at 6 decimal places
    return f"{value:.{decimals}f}{unit}"

def fmt_bw(value, unit='MB/s'):
    """Format bandwidth with unit, auto-convert to GB if ≥1000MB"""
    if unit == 'MB/s' and value >= 1000:
        return f"{value/1000:.2f}GB/s"
    elif unit == 'Gb/s' and value >= 1000:
        return f"{value/1000:.2f}Tb/s"
    return f"{value:.2f}{unit}"

def kill_procs():
    """Kill DPDK processes (pktgen locally, l3fwd remotely if configured)"""
    print('Killing processes...', end=' ', flush=True)
    subprocess.run(['sudo', 'pkill', '-f', 'pktgen'], check=False)
    if L3FWD_NODE:
        l3fwd_cmd = ['sudo pkill dpdk-l3fwd']
        l3fwd_host = pyrem.host.RemoteHost(L3FWD_NODE)
        l3fwd_task = l3fwd_host.run(l3fwd_cmd, quiet=False)
        pyrem.task.Parallel([l3fwd_task], aggregate=True).start(wait=True)
    print('DONE')

# Setup ARP tables
def setup_arp_tables():
    """Setup ARP tables (local for pktgen, remote for l3fwd if configured)"""
    # Setup ARP on local pktgen node
    print('Setting up local ARP table...')
    arp_file = f'{DPDK_BENCH_HOME}/scripts/arp_table'
    if os.path.exists(arp_file):
        subprocess.run(['sudo', 'arp', '-f', arp_file], check=False)

    # Setup ARP on remote L3FWD node if configured
    if L3FWD_NODE and L3FWD_NODE != PKTGEN_NODE:
        host = pyrem.host.RemoteHost(L3FWD_NODE)
        cmd = [f'sudo arp -f {DPDK_BENCH_HOME}/scripts/arp_table']
        task = host.run(cmd, quiet=True)
        pyrem.task.Parallel([task], aggregate=True).start(wait=True)

def run_l3fwd(tx_desc_value=None, rx_desc_value=None, l3fwd_config=None):
    """Run l3fwd on L3FWD node"""
    global experiment_id
    if not l3fwd_config:
        raise ValueError("l3fwd_config is required - use get_l3fwd_config()")

    config = l3fwd_config
    host = pyrem.host.RemoteHost(config["node"])
    
    # Build tx-queue-size and rx-queue-size arguments if specified
    tx_queue_arg = ""
    rx_queue_arg = ""
    if tx_desc_value:
        tx_queue_arg = f" --tx-queue-size={tx_desc_value}"
    if rx_desc_value:
        rx_queue_arg = f" --rx-queue-size={rx_desc_value}"
    
    cmd = [f'cd {os.path.dirname(config["binary_path"])} && '
           f'sudo -E {ENV} ' 
           f'{config["binary_path"]} '
           f'{config["lcores"]} '
           f'{config["memory_channels"]} '
           f'-a {config["pci_address"]} '
           f'-- {config["port_mask"]} '
           f'--config="{config["config"]}" '
           f'--eth-dest=0,{config["eth_dest"]}'
           f'{tx_queue_arg}'
           f'{rx_queue_arg} '
           f'> {DATA_PATH}/{experiment_id}.l3fwd 2>&1']
    
    task = host.run(cmd, quiet=False)
    print(f'L3FWD command: {cmd}')
    pyrem.task.Parallel([task], aggregate=True).start(wait=False)
    time.sleep(3)

def run_pktgen(tx_desc_value=None, pktgen_config=None):
    """Run pktgen locally"""
    global experiment_id
    if not pktgen_config:
        raise ValueError("pktgen_config is required - use get_pktgen_config()")

    config = pktgen_config

    # Build TX descriptor argument if specified
    # Note: --txd is an application option, goes after -- separator
    tx_desc_arg = ""
    if tx_desc_value and tx_desc_value != 1024:  # Only add if different from default
        tx_desc_arg = f" --txd={tx_desc_value}"

    # Build command string
    cmd_str = (f'cd {config["working_dir"]} && '
               f'sudo -E {ENV} '
               f'ENABLE_PCM=0 '  # PCM disabled by default
               f'PKTGEN_DURATION={PKTGEN_DURATION} '
               f'PKTGEN_PACKET_SIZE={PKTGEN_PACKET_SIZE} '
               f'{config["binary_path"]} '
               f'{config["lcores"]} '
               f'{config["memory_channels"]} '
               f'-a {config["pci_address"]} '
               f'{config["proc_type"]} '
               f'--file-prefix={config["file_prefix"]} '
               f'-- -m "{config["port_map"]}" '
               f'{config["app_args"]}'
               f'{tx_desc_arg} '
               f'-f {config["script_file"]} '
               f'> {DATA_PATH}/{experiment_id}.pktgen 2>&1')

    print(f'PKTGEN command: {cmd_str}')

    # Run locally using subprocess
    result = subprocess.run(cmd_str, shell=True, check=False)
    if result.returncode != 0:
        print(f'PKTGEN exited with code {result.returncode}')

def run_pktgen_with_perf(tx_desc_value=None, pktgen_config=None):
    """Run pktgen locally and start profilers (perf/pcm/neohost) based on configuration"""
    global experiment_id
    if not pktgen_config:
        raise ValueError("pktgen_config is required - use get_pktgen_config()")

    config = pktgen_config

    # Build list of enabled profilers
    enabled_profilers = []
    if ENABLE_PERF:
        enabled_profilers.append('perf')
    if ENABLE_PCM:
        enabled_profilers.append('pcm')
    if ENABLE_NEOHOST:
        enabled_profilers.append('neohost')

    profilers_str = '+'.join(enabled_profilers) if enabled_profilers else 'none'
    print(f'Running pktgen with profilers: {profilers_str}')

    # Build TX descriptor argument if specified
    tx_desc_arg = ""
    if tx_desc_value and tx_desc_value != 1024:
        tx_desc_arg = f" --txd={tx_desc_value}"

    # Extract PCI address (remove devargs like ",txqs_min_inline=0")
    pci_address = config["pci_address"].split(',')[0]

    # Build pktgen command (runs in background)
    pktgen_cmd = (f'cd {config["working_dir"]} && '
                  f'sudo -E {ENV} '
                  f'ENABLE_PCM=0 '  # PCM disabled by default
                  f'PKTGEN_DURATION={PKTGEN_DURATION} '
                  f'PKTGEN_PACKET_SIZE={PKTGEN_PACKET_SIZE} '
                  f'{config["binary_path"]} '
                  f'{config["lcores"]} '
                  f'{config["memory_channels"]} '
                  f'-a {config["pci_address"]} '
                  f'{config["proc_type"]} '
                  f'--file-prefix={config["file_prefix"]} '
                  f'-- -m "{config["port_map"]}" '
                  f'{config["app_args"]}'
                  f'{tx_desc_arg} '
                  f'-f {config["script_file"]} '
                  f'> {DATA_PATH}/{experiment_id}.pktgen 2>&1 & '
                  f'PKTGEN_PID=$!; ')

    # Add initial warmup delay
    pktgen_cmd += f'sleep {WARMUP_DELAY}; '

    # Add perf monitoring if enabled
    if ENABLE_PERF:
        # Build event and metric lists from config
        perf_args = []
        if PERF_EVENTS:
            perf_args.append(f'-e {",".join(PERF_EVENTS)}')

        perf_args_str = ' '.join(perf_args)
        pktgen_cmd += (f'sudo timeout {PERF_DURATION} perf stat '
                       f'{perf_args_str} '
                       f'-I 1000 -a --per-socket '
                       f'> {DATA_PATH}/{experiment_id}.perf 2>&1; ')

    # Add PCM monitoring if enabled
    if ENABLE_PCM:
        pktgen_cmd += f'sleep {TOOL_INTERVAL}; '
        pktgen_cmd += (f'sudo timeout {PCM_DURATION} {DPDK_BENCH_HOME}/pcm/build/bin/pcm-pcie -B -e '
                       f'> {DATA_PATH}/{experiment_id}.pcm-pcie 2>&1; ')

    # Add NeoHost monitoring if enabled
    if ENABLE_NEOHOST:
        # Check if neohost is available
        neohost_python = f'{DPDK_BENCH_HOME}/neohost/miniconda3/envs/py27/bin/python'
        neohost_sdk = f'{DPDK_BENCH_HOME}/neohost/sdk/opt/neohost/sdk/get_device_performance_counters.py'

        if os.path.exists(neohost_python) and os.path.exists(neohost_sdk):
            pktgen_cmd += f'sleep {TOOL_INTERVAL}; '
            pktgen_cmd += (f'sudo timeout {NEOHOST_DURATION} {neohost_python} '
                           f'{neohost_sdk} '
                           f'--dev-uid={pci_address} --get-analysis --run-loop 2>&1 | '
                           f'sed "s/\\x1b\\[[0-9;]*m//g" '
                           f'> {DATA_PATH}/{experiment_id}.neohost; ')
        else:
            print(f'WARNING: NeoHost enabled but not available at {neohost_python}')

    # Wait for pktgen to finish
    pktgen_cmd += f'wait $PKTGEN_PID 2>/dev/null'

    print(f'PKTGEN+PROFILERS command (duration={PKTGEN_DURATION}s): {pktgen_cmd[:]}...')

    # Run locally using subprocess
    result = subprocess.run(pktgen_cmd, shell=True, check=False)
    if result.returncode != 0:
        print(f'PKTGEN+PROFILERS exited with code {result.returncode}')

def parse_perf_pktgen_results(experiment_id, txqs_min_inline, pktgen_tx_desc_value, pktgen_lcore_count):
    """Parse pktgen and perf stat results"""
    result_str = ''

    # Parse Pktgen results for TX rate
    pktgen_file = f'{DATA_PATH}/{experiment_id}.pktgen'
    pktgen_tx_pkts = 0
    pktgen_tx_rate = 0
    pktgen_status = 'unknown'

    if os.path.exists(pktgen_file):
        try:
            with open(pktgen_file, "r", encoding='utf-8', errors='ignore') as file:
                pktgen_text = file.read()

            # Look for Total TX packets in PKTGEN Packet Statistics Summary
            packet_stats_pattern = r'PKTGEN Packet Statistics Summary.*?Total\s+\d+\s+(\d+).*?====='
            packet_stats_match = re.search(packet_stats_pattern, pktgen_text, re.DOTALL)
            if packet_stats_match:
                pktgen_tx_pkts = int(packet_stats_match.group(1))
                pktgen_status = 'success'
                print(f"DEBUG Pktgen: Found TX packets: {pktgen_tx_pkts}")
            else:
                # Try to sum individual lcore TX stats
                lcore_matches = re.findall(r'^\s*(\d+)\s+\d+\s+(\d+)\s+', pktgen_text, re.MULTILINE)
                if lcore_matches:
                    lcore_dict = {}
                    for match in lcore_matches:
                        lcore_id = int(match[0])
                        lcore_dict[lcore_id] = int(match[1])  # TX
                    pktgen_tx_pkts = sum(lcore_dict.values())
                    pktgen_status = 'success'
                    print(f"DEBUG Pktgen: Summed {len(lcore_dict)} lcore TX stats: {pktgen_tx_pkts}")
                else:
                    pktgen_status = 'error'
                    print(f"DEBUG Pktgen: No TX packet data found")

        except Exception as e:
            print(f"ERROR parsing Pktgen file {pktgen_file}: {e}")
            pktgen_status = 'error'

    # Calculate TX rate (Mpps)
    duration_sec = PKTGEN_DURATION
    pktgen_tx_rate = round(pktgen_tx_pkts / (duration_sec * 1_000_000), 3) if pktgen_tx_pkts > 0 else 0

    # Parse perf stat results dynamically based on config
    perf_file = f'{DATA_PATH}/{experiment_id}.perf'
    # Initialize perf_results with all items from config (default to 0)
    perf_results = {item: 0 for item in PERF_EVENTS}

    if os.path.exists(perf_file):
        try:
            with open(perf_file, "r", encoding='utf-8', errors='ignore') as file:
                perf_text = file.read()

            lines = perf_text.strip().split('\n')
            timestamp_data = {}

            for line in lines:
                # Match pattern for count events: timestamp socket cpus value event_name
                # Example: "1.001096320 S0       32            571,500      LLC-load-misses"
                match_count = re.match(r'\s*([\d\.]+)\s+S\d+\s+\d+\s+([\d,]+)\s+(\S+?)(?:\s|$)', line)
                if match_count:
                    timestamp = match_count.group(1)
                    value_str = match_count.group(2)
                    event = match_count.group(3)

                    # Skip lines with percentage or other non-event patterns
                    if '%' not in event and not event.startswith('#'):
                        try:
                            value_count = int(value_str.replace(',', ''))
                            if timestamp not in timestamp_data:
                                timestamp_data[timestamp] = {}
                            timestamp_data[timestamp][event] = value_count
                        except ValueError:
                            pass

                # Match pattern for bandwidth metrics: timestamp socket cpus value event #    XXX.X MB/s  metric_name
                # Example: "1.001096320 S0        1          2,513,972      UNC_CHA_REQUESTS.WRITES_LOCAL    #    160.9 MB/s  llc_miss_local_memory_bandwidth_write"
                match_bw = re.match(r'\s*([\d\.]+)\s+S\d+\s+\d+\s+([\d,]+)\s+\S+\s+#\s+([\d\.]+)\s+MB/s\s+(\S+)', line)
                if match_bw:
                    timestamp = match_bw.group(1)
                    bandwidth_mbs = float(match_bw.group(3))
                    metric = match_bw.group(4)

                    if timestamp not in timestamp_data:
                        timestamp_data[timestamp] = {}
                    timestamp_data[timestamp][metric] = bandwidth_mbs

            # Collect values per event/metric from config
            all_perf_items = PERF_EVENTS
            event_values = {item: [] for item in all_perf_items}

            for timestamp, events in timestamp_data.items():
                for item in all_perf_items:
                    if item in events:
                        event_values[item].append(events[item])

            # Calculate averages (skip first 2 samples for warm-up)
            def avg_skip_first_n(values, n=2):
                filtered = values[n:] if len(values) > n else values
                return round(sum(filtered) / len(filtered), 3) if filtered else 0

            # Store results in dictionary
            for item in all_perf_items:
                perf_results[item] = avg_skip_first_n(event_values[item])

            # Print debug info
            if event_values.get(all_perf_items[0] if all_perf_items else None):
                print(f"DEBUG Perf: Found {len(event_values[all_perf_items[0]])} samples")
            for item in all_perf_items:
                if perf_results[item] > 0:
                    print(f"DEBUG Perf: {item} = {perf_results[item]:,}")

        except Exception as e:
            print(f"ERROR parsing perf file {perf_file}: {e}")

    # Parse pcm-pcie results (with -B -e options: includes Total/Miss/Hit rows)
    pcm_file = f'{DATA_PATH}/{experiment_id}.pcm-pcie'
    pcm_pcie_rdcur_total = 0
    pcm_pcie_rdcur_miss = 0
    pcm_pcie_ddio_miss_rate = 0
    pcm_pcie_rd_mb = 0
    pcm_pcie_wr_mb = 0

    if os.path.exists(pcm_file):
        try:
            with open(pcm_file, "r", encoding='utf-8', errors='ignore') as file:
                pcm_text = file.read()

            # Parse pcm-pcie output - dynamic column detection
            # Format varies by machine, but always has: Skt | PCIRdCur | ... | PCIe Rd (B) | PCIe Wr (B)
            lines = pcm_text.strip().split('\n')

            # Helper functions to parse values with K/M/G suffixes
            def parse_count(s):
                s = s.strip()
                if 'K' in s:
                    return float(s.replace('K', '').strip()) * 1000
                elif 'M' in s:
                    return float(s.replace('M', '').strip()) * 1000000
                elif 'G' in s:
                    return float(s.replace('G', '').strip()) * 1000000000
                else:
                    try:
                        return float(s)
                    except:
                        return 0

            def parse_bytes(s):
                s = s.strip()
                if 'K' in s:
                    return float(s.replace('K', '').strip()) * 1024
                elif 'M' in s:
                    return float(s.replace('M', '').strip()) * 1024 * 1024
                elif 'G' in s:
                    return float(s.replace('G', '').strip()) * 1024 * 1024 * 1024
                else:
                    try:
                        return float(s)
                    except:
                        return 0

            # Find header line to determine column indices
            header_cols = None
            rdcur_idx = None
            pcie_rd_idx = None
            pcie_wr_idx = None

            for line in lines:
                if 'Skt' in line and 'PCIRdCur' in line and 'PCIe Rd (B)' in line:
                    # Split header by | to get column names
                    header_cols = [col.strip() for col in line.split('|')]
                    for i, col in enumerate(header_cols):
                        if col == 'PCIRdCur':
                            rdcur_idx = i
                        elif col == 'PCIe Rd (B)':
                            pcie_rd_idx = i
                        elif col == 'PCIe Wr (B)':
                            pcie_wr_idx = i
                    break

            if rdcur_idx is None or pcie_rd_idx is None or pcie_wr_idx is None:
                print(f"DEBUG PCM: Could not find required columns in header")
            else:
                # With -e option, output has (Total), (Miss), (Hit) rows
                rdcur_total_values = []
                rdcur_miss_values = []
                rd_bytes_values = []
                wr_bytes_values = []

                for line in lines:
                    # Skip header and separator lines
                    if 'Skt' in line or '---' in line or not line.strip():
                        continue

                    # Check if this is a data line (starts with socket number or *)
                    # Only use Socket 0 data (where NIC is connected)
                    socket_match = re.match(r'^\s*(\d+)\s+', line)
                    if socket_match:
                        socket_num = int(socket_match.group(1))
                        if socket_num != 0:
                            continue  # Skip non-Socket 0 data

                        # Determine row type: (Total), (Miss), (Hit), or Aggregate
                        is_total = '(Total)' in line or '(Aggregate)' in line
                        is_miss = '(Miss)' in line

                        # Extract all "number + optional K/M/G" patterns
                        value_pattern = r'(\d+(?:\.\d+)?)\s*([KMG]?)'
                        matches = re.findall(value_pattern, line)

                        # Combine number with unit
                        values = []
                        for num, unit in matches:
                            values.append(num + unit if unit else num)

                        if len(values) >= max(rdcur_idx, pcie_rd_idx, pcie_wr_idx) + 1:
                            try:
                                rdcur = parse_count(values[rdcur_idx])
                                rd_bytes = parse_bytes(values[pcie_rd_idx])
                                wr_bytes = parse_bytes(values[pcie_wr_idx])

                                if is_total:
                                    rdcur_total_values.append(rdcur)
                                    rd_bytes_values.append(rd_bytes)
                                    wr_bytes_values.append(wr_bytes)
                                elif is_miss:
                                    rdcur_miss_values.append(rdcur)
                            except Exception as e:
                                # Skip malformed lines
                                pass

                if rdcur_total_values:
                    # Skip first 2 samples for warm-up
                    total_filtered = rdcur_total_values[2:] if len(rdcur_total_values) > 2 else rdcur_total_values
                    miss_filtered = rdcur_miss_values[2:] if len(rdcur_miss_values) > 2 else rdcur_miss_values
                    rd_bytes_filtered = rd_bytes_values[2:] if len(rd_bytes_values) > 2 else rd_bytes_values
                    wr_bytes_filtered = wr_bytes_values[2:] if len(wr_bytes_values) > 2 else wr_bytes_values

                    # Calculate averages
                    pcm_pcie_rdcur_total = round(sum(total_filtered) / len(total_filtered) / 1000000, 3) if total_filtered else 0
                    pcm_pcie_rdcur_miss = round(sum(miss_filtered) / len(miss_filtered) / 1000000, 3) if miss_filtered else 0
                    pcm_pcie_rd_mb = round(sum(rd_bytes_filtered) / len(rd_bytes_filtered) / (1024 * 1024), 3) if rd_bytes_filtered else 0
                    pcm_pcie_wr_mb = round(sum(wr_bytes_filtered) / len(wr_bytes_filtered) / (1024 * 1024), 3) if wr_bytes_filtered else 0

                    # Calculate DDIO miss rate
                    if pcm_pcie_rdcur_total > 0:
                        pcm_pcie_ddio_miss_rate = round((pcm_pcie_rdcur_miss / pcm_pcie_rdcur_total) * 100, 2)

                    print(f"DEBUG PCM: Found {len(rdcur_total_values)} Socket 0 samples (using {len(total_filtered)} after skipping first 2)")
                    print(f"DEBUG PCM: PCIRdCur Total: {pcm_pcie_rdcur_total}M, Miss: {pcm_pcie_rdcur_miss}M, DDIO Miss Rate: {pcm_pcie_ddio_miss_rate}%")
                    print(f"DEBUG PCM: PCIe Rd: {pcm_pcie_rd_mb} MB, PCIe Wr: {pcm_pcie_wr_mb} MB")
                else:
                    print(f"DEBUG PCM: No data found")

        except Exception as e:
            print(f"ERROR parsing PCM file {pcm_file}: {e}")

    # Parse neohost results
    neohost_file = f'{DATA_PATH}/{experiment_id}.neohost'
    neohost_outbound_stalled_reads = 0
    neohost_pcie_inbound_bw = 0
    neohost_pcie_outbound_bw = 0

    if os.path.exists(neohost_file):
        try:
            with open(neohost_file, "r", encoding='utf-8', errors='ignore') as file:
                neohost_text = file.read()

            lines = neohost_text.strip().split('\n')
            outbound_stalled_reads_values = []
            pcie_inbound_bw_values = []
            pcie_outbound_bw_values = []

            for line in lines:
                # Parse "Outbound Stalled Reads" from Counter section
                # Format: || Outbound Stalled Reads                                    || 0               ||
                if 'Outbound Stalled Reads' in line and '||' in line:
                    match = re.search(r'\|\|\s*Outbound Stalled Reads\s*\|\|\s*([\d,]+)\s*\|\|', line)
                    if match:
                        value = int(match.group(1).replace(',', ''))
                        outbound_stalled_reads_values.append(value)

                # Parse "PCIe Inbound Used BW" from Performance Analysis section
                # Format: ||| PCIe Inbound Used BW                || 8.8684        [Gb/s]             ||
                if 'PCIe Inbound Used BW' in line and '|||' in line:
                    match = re.search(r'\|\|\|\s*PCIe Inbound Used BW\s*\|\|\s*([\d,\.]+)\s*\[Gb/s\]', line)
                    if match:
                        value = float(match.group(1).replace(',', ''))
                        pcie_inbound_bw_values.append(value)

                # Parse "PCIe Outbound Used BW" from Performance Analysis section
                # Format: ||| PCIe Outbound Used BW               || 0.6274        [Gb/s]             ||
                if 'PCIe Outbound Used BW' in line and '|||' in line:
                    match = re.search(r'\|\|\|\s*PCIe Outbound Used BW\s*\|\|\s*([\d,\.]+)\s*\[Gb/s\]', line)
                    if match:
                        value = float(match.group(1).replace(',', ''))
                        pcie_outbound_bw_values.append(value)

            # Skip first 2 samples for warm-up
            if outbound_stalled_reads_values:
                filtered = outbound_stalled_reads_values[2:] if len(outbound_stalled_reads_values) > 2 else outbound_stalled_reads_values
                neohost_outbound_stalled_reads = round(sum(filtered) / len(filtered), 3) if filtered else 0
            if pcie_inbound_bw_values:
                filtered = pcie_inbound_bw_values[2:] if len(pcie_inbound_bw_values) > 2 else pcie_inbound_bw_values
                neohost_pcie_inbound_bw = round(sum(filtered) / len(filtered), 3) if filtered else 0
            if pcie_outbound_bw_values:
                filtered = pcie_outbound_bw_values[2:] if len(pcie_outbound_bw_values) > 2 else pcie_outbound_bw_values
                neohost_pcie_outbound_bw = round(sum(filtered) / len(filtered), 3) if filtered else 0

            if outbound_stalled_reads_values or pcie_inbound_bw_values or pcie_outbound_bw_values:
                total_samples = max(len(outbound_stalled_reads_values), len(pcie_inbound_bw_values), len(pcie_outbound_bw_values))
                used_samples = max(len(outbound_stalled_reads_values[2:]) if len(outbound_stalled_reads_values) > 2 else len(outbound_stalled_reads_values),
                                   len(pcie_inbound_bw_values[2:]) if len(pcie_inbound_bw_values) > 2 else len(pcie_inbound_bw_values),
                                   len(pcie_outbound_bw_values[2:]) if len(pcie_outbound_bw_values) > 2 else len(pcie_outbound_bw_values))
                print(f"DEBUG Neohost: Found {total_samples} samples (using {used_samples} after skipping first 2)")
                print(f"DEBUG Neohost: Outbound Stalled Reads: {neohost_outbound_stalled_reads}, PCIe Inbound BW: {neohost_pcie_inbound_bw} Gb/s, PCIe Outbound BW: {neohost_pcie_outbound_bw} Gb/s")
            else:
                print(f"DEBUG Neohost: No data found")

        except Exception as e:
            print(f"ERROR parsing Neohost file {neohost_file}: {e}")

    print(f"Pktgen: TX={pktgen_tx_pkts:,} TX_rate={pktgen_tx_rate} Mpps ({pktgen_status})")

    # Print perf results
    if perf_results:
        print("Perf results:")
        for item, value in perf_results.items():
            if value > 0:
                print(f"  {item} = {value:,}")

    print(f"PCM: PCIRdCur Total={pcm_pcie_rdcur_total}M, Miss={pcm_pcie_rdcur_miss}M, DDIO Miss Rate={pcm_pcie_ddio_miss_rate}%, PCIe Rd={pcm_pcie_rd_mb}MB, Wr={pcm_pcie_wr_mb}MB")
    print(f"Neohost: Outbound Stalled Reads={neohost_outbound_stalled_reads}, PCIe Inbound BW={neohost_pcie_inbound_bw} Gb/s, PCIe Outbound BW={neohost_pcie_outbound_bw} Gb/s")

    # Build CSV row dynamically with formatted values
    tx_cores = pktgen_lcore_count
    csv_values = [experiment_id, txqs_min_inline, tx_cores, pktgen_tx_desc_value, f"{pktgen_tx_rate}Mpps"]

    # Add perf values in config order (formatted) - only if ENABLE_PERF is True
    if ENABLE_PERF:
        for item in PERF_EVENTS:
            val = perf_results.get(item, 0)
            csv_values.append(fmt_count(val))

    # Add PCM values (formatted) - includes DDIO miss rate from pcm-pcie -e
    csv_values.append(f"{pcm_pcie_rdcur_total:.1f}M")
    csv_values.append(fmt_small_value(pcm_pcie_rdcur_miss, 'M'))
    csv_values.append(f"{pcm_pcie_ddio_miss_rate:.2f}%")
    csv_values.append(fmt_bw(pcm_pcie_rd_mb, 'MB/s'))
    csv_values.append(fmt_bw(pcm_pcie_wr_mb, 'MB/s'))

    # Add Neohost values (formatted)
    csv_values.append(fmt_count(neohost_outbound_stalled_reads))
    csv_values.append(fmt_bw(neohost_pcie_inbound_bw, 'Gb/s'))
    csv_values.append(fmt_bw(neohost_pcie_outbound_bw, 'Gb/s'))

    result_str += ', '.join(map(str, csv_values)) + '\n'

    return result_str

def parse_dpdk_results(experiment_id, l3fwd_tx_desc_value=None, l3fwd_rx_desc_value=None, pktgen_tx_desc_value=None, l3fwd_lcore_count=None, pktgen_lcore_count=None):
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
    l3fwd_dram_read_bw = 0
    l3fwd_dram_write_bw = 0
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
            l3fwd_dram_read_bw = 0
            l3fwd_dram_write_bw = 0
            
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
                    l3fwd_dram_read_bw = float(socket1_match.group(3))
                    l3fwd_dram_write_bw = float(socket1_match.group(4))
                    print(f"DEBUG L3FWD: Socket 1 - DRAM Read: {l3fwd_dram_read}, DRAM Write: {l3fwd_dram_write}, Read BW: {l3fwd_dram_read_bw}, Write BW: {l3fwd_dram_write_bw}")
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
    pktgen_dram_read_bw = 0
    pktgen_dram_write_bw = 0
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
            pktgen_dram_read_bw = 0
            pktgen_dram_write_bw = 0
            
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
                    pktgen_dram_read_bw = float(socket1_match.group(3))
                    pktgen_dram_write_bw = float(socket1_match.group(4))
                    print(f"DEBUG Pktgen: Socket 1 - DRAM Read: {pktgen_dram_read}, DRAM Write: {pktgen_dram_write}, Read BW: {pktgen_dram_read_bw}, Write BW: {pktgen_dram_write_bw}")
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
    
    result_str += f'{experiment_id}, {PKTGEN_PACKET_SIZE}, {l3fwd_tx_desc_value}, {l3fwd_rx_desc_value}, {pktgen_tx_desc_value}, {l3fwd_lcore_count}, {pktgen_lcore_count}, {pktgen_rx_rate}, {pktgen_tx_rate}, {pktgen_rx_fails}, {l3fwd_rx_rate}, {l3fwd_tx_rate}, {l3fwd_tx_fails}, {pktgen_hw_rx_missed}, {l3fwd_hw_rx_missed}, {pktgen_rx_l3_misses}, {pktgen_rx_l2_hit}, {pktgen_rx_l3_hit}, {pktgen_tx_l3_misses}, {pktgen_tx_l2_hit}, {pktgen_tx_l3_hit}, {l3fwd_l3_misses}, {l3fwd_l2_hit}, {l3fwd_l3_hit}, {pktgen_dram_read}, {pktgen_dram_write}, {pktgen_dram_read_bw}, {pktgen_dram_write_bw}, {l3fwd_dram_read}, {l3fwd_dram_write}, {l3fwd_dram_read_bw}, {l3fwd_dram_write_bw}, {pktgen_pcie_read}, {pktgen_pcie_write}, {pktgen_pcie_read_bw}, {pktgen_pcie_write_bw}, {l3fwd_pcie_read}, {l3fwd_pcie_write}, {l3fwd_pcie_read_bw}, {l3fwd_pcie_write_bw}\n'
    return result_str

def run_eval():
    """Main DPDK evaluation function - Pktgen only with perf monitoring"""
    global experiment_id
    global final_result

    # Build profiler list
    enabled_profilers = []
    if ENABLE_PERF:
        enabled_profilers.append('PERF')
    if ENABLE_PCM:
        enabled_profilers.append('PCM')
    if ENABLE_NEOHOST:
        enabled_profilers.append('NEOHOST')
    profilers_str = '+'.join(enabled_profilers) if enabled_profilers else 'NONE'

    print("Starting DPDK Pktgen Tests with Profiling")
    print(f"Enabled profilers: {profilers_str}")
    print(f"Testing PKTGEN TX descriptor values: {PKTGEN_TX_DESC_VALUES}")
    print(f"Testing PKTGEN LCORE counts: {PKTGEN_TX_CORE_VALUES}")
    print(f"Total duration: {PKTGEN_DURATION} seconds (warmup: {WARMUP_DELAY}s, interval: {TOOL_INTERVAL}s)")

    # Extract txqs_min_inline from pktgen config
    # Assuming format: "0000:31:00.1,txqs_min_inline=0"
    pktgen_config_default = get_pktgen_config(2)  # Get any config to extract pci_address
    pci_match = re.search(r'txqs_min_inline=(\d+)', pktgen_config_default["pci_address"])
    txqs_min_inline = int(pci_match.group(1)) if pci_match else 8

    for pktgen_lcore_count in PKTGEN_TX_CORE_VALUES:
        for pktgen_tx_desc_value in PKTGEN_TX_DESC_VALUES:
            print(f'\n================ TESTING PKTGEN_LCORE={pktgen_lcore_count}, PKTGEN_TX_DESC={pktgen_tx_desc_value} =================')

            kill_procs()
            experiment_id = datetime.datetime.now().strftime('%Y%m%d-%H%M%S.%f')
            print(f'EXPTID: {experiment_id}')

            setup_arp_tables()

            # Generate pktgen configuration for current lcore count
            pktgen_config = get_pktgen_config(pktgen_lcore_count)

            print(f'PKTGEN Config: lcores={pktgen_config["lcores"]}, port_map="{pktgen_config["port_map"]}"')
            print(f'txqs_min_inline={txqs_min_inline}, TX_DESC={pktgen_tx_desc_value}')

            # Run Pktgen with perf monitoring
            run_pktgen_with_perf(pktgen_tx_desc_value, pktgen_config)

            # Stop processes
            kill_procs()
            time.sleep(3)

            # Parse results
            print(f'================ {experiment_id} TEST COMPLETE =================')
            res = parse_perf_pktgen_results(experiment_id, txqs_min_inline, pktgen_tx_desc_value, pktgen_lcore_count)
            final_result = final_result + f'{res}'

            # Wait a bit between tests
            time.sleep(5)
    
        



def exiting():
    """Exit handler for cleanup"""
    global final_result
    print('EXITING')
    # Build CSV header dynamically based on config
    header_parts = ["EXPTID", "txqs_min_inline", "# TX cores", "DEFAULT_RX/TX_DESC", "TX rate (Mpps)"]

    # Add perf event/metric headers with units from config - only if ENABLE_PERF is True
    if ENABLE_PERF:
        for item in PERF_EVENTS:
            unit = PERF_UNITS.get(item, 'count')
            header_parts.append(f"{item} ({unit})")

    # Add PCM headers (includes DDIO miss rate from pcm-pcie -e)
    header_parts.extend(["PCIRdCur Total (M)", "PCIRdCur Miss (M)", "DDIO Miss Rate (%)",
                         "PCIe Rd (MB)", "PCIe Wr (MB)"])

    # Add Neohost headers
    header_parts.extend(["Outbound Stalled Reads", "PCIe Inbound Used BW (Gb/s)", "PCIe Outbound Used BW (Gb/s)"])

    result_header = ", ".join(header_parts) + "\n"

    print(f'\n\n\n\n\n{result_header}')
    print(final_result)
    with open(f'{DATA_PATH}/dpdk_perf_results.txt', "w") as file:
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

    if L3FWD_NODE:
        print(f"L3FWD Node: {L3FWD_NODE} (remote)")
    else:
        print(f"L3FWD Node: disabled")
    print(f"Pktgen Node: {PKTGEN_NODE} (local)")
    print(f"Data Path: {DATA_PATH}")
    run_eval()