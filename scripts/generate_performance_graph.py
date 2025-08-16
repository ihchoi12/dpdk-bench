#!/usr/bin/env python3
"""
DPDK Port Mapping Performance Comparison Graph Generator
Generates a bar chart comparing TX rates between combined and split port mapping modes.
"""

import matplotlib.pyplot as plt
import numpy as np
import re
import os
import sys

def parse_result_file(filepath):
    """Parse benchmark result file and extract TX rates."""
    tx_rates = {}
    
    if not os.path.exists(filepath):
        print(f"Warning: File {filepath} not found")
        return tx_rates
    
    with open(filepath, 'r') as f:
        for line in f:
            # Skip comment lines
            if line.startswith('#') or not line.strip():
                continue
            
            # Extract core count and TX rate
            # Look for pattern like "-l 0-N" and "|TX_rate"
            core_match = re.search(r'-l 0-(\d+)', line)
            rate_match = re.search(r'\|([0-9.]+)$', line)
            
            if core_match and rate_match:
                cores = int(core_match.group(1))
                tx_rate = float(rate_match.group(1))
                tx_rates[cores] = tx_rate
    
    return tx_rates

def main():
    # File paths
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.dirname(script_dir)
    results_dir = os.path.join(repo_root, 'results')
    
    # Find the latest result files
    combined_file = os.path.join(results_dir, '250816-011153-multi-core-tx-combined.txt')
    split_file = os.path.join(results_dir, '250816-011801-multi-core-tx-split.txt')
    
    # Parse result files
    print("Parsing benchmark result files...")
    combined_data = parse_result_file(combined_file)
    split_data = parse_result_file(split_file)
    
    if not combined_data and not split_data:
        print("Error: No valid data found in result files")
        sys.exit(1)
    
    print(f"Combined data points: {len(combined_data)}")
    print(f"Split data points: {len(split_data)}")
    
    # Prepare data for plotting
    cores_range = range(1, 16)  # 1 to 15 cores
    combined_rates = []
    split_rates = []
    
    for cores in cores_range:
        # For combined mode: use actual data or 0 if not available
        combined_rates.append(combined_data.get(cores, 0))
        
        # For split mode: only even numbers have data, odd numbers are 0
        if cores % 2 == 0 and cores in split_data:
            split_rates.append(split_data[cores])
        else:
            split_rates.append(0)
    
    # Create the bar chart
    plt.figure(figsize=(14, 8))
    
    x = np.arange(len(cores_range))  # Label locations
    width = 0.35  # Width of bars
    
    # Create bars
    bars1 = plt.bar(x - width/2, combined_rates, width, label='RX/TX Combined', 
                    color='#2E86AB', alpha=0.8, edgecolor='black', linewidth=0.5)
    bars2 = plt.bar(x + width/2, split_rates, width, label='RX/TX Split', 
                    color='#A23B72', alpha=0.8, edgecolor='black', linewidth=0.5)
    
    # Customize the chart
    plt.xlabel('Number of CPU Cores', fontsize=12, fontweight='bold')
    plt.ylabel('TX Rate (Mpps)', fontsize=12, fontweight='bold')
    plt.title('DPDK Port Mapping Performance Comparison\nCombined vs Split RX/TX Processing', 
              fontsize=14, fontweight='bold', pad=20)
    
    # Set x-axis
    plt.xticks(x, [str(i) for i in cores_range])
    plt.xlim(-0.6, len(cores_range) - 0.4)
    
    # Set y-axis
    max_rate = max(max(combined_rates), max(split_rates))
    plt.ylim(0, max_rate * 1.1)
    
    # Add value labels on bars
    def add_value_labels(bars, rates):
        for bar, rate in zip(bars, rates):
            if rate > 0:  # Only add label if there's a value
                height = bar.get_height()
                plt.text(bar.get_x() + bar.get_width()/2., height + max_rate * 0.01,
                        f'{rate:.1f}', ha='center', va='bottom', fontsize=9, 
                        fontweight='bold')
    
    add_value_labels(bars1, combined_rates)
    add_value_labels(bars2, split_rates)
    
    # Add legend
    plt.legend(loc='upper left', fontsize=11, framealpha=0.9)
    
    # Add grid for better readability
    plt.grid(axis='y', alpha=0.3, linestyle='--')
    
    # Add annotation for split mode
    plt.text(0.98, 0.02, 'Note: Split mode only supports even number of cores', 
             transform=plt.gca().transAxes, ha='right', va='bottom', 
             fontsize=9, style='italic', color='gray')
    
    # Tight layout
    plt.tight_layout()
    
    # Save the plot
    output_file = os.path.join(results_dir, 'port_mapping_performance_comparison.png')
    plt.savefig(output_file, dpi=300, bbox_inches='tight', facecolor='white')
    
    print(f"Graph saved to: {output_file}")
    
    # Show summary
    print("\nPerformance Summary:")
    print("=" * 50)
    print("Cores | Combined (Mpps) | Split (Mpps) | Ratio")
    print("-" * 50)
    for i, cores in enumerate(cores_range):
        combined_val = combined_rates[i]
        split_val = split_rates[i]
        if combined_val > 0 and split_val > 0:
            ratio = split_val / combined_val
            print(f"{cores:5d} | {combined_val:11.1f} | {split_val:9.1f} | {ratio:5.2f}")
        elif combined_val > 0:
            print(f"{cores:5d} | {combined_val:11.1f} | {'N/A':>9} | {'N/A':>5}")
    
    # Find peak performance
    peak_combined_idx = np.argmax(combined_rates)
    peak_combined_cores = cores_range[peak_combined_idx]
    peak_combined_rate = combined_rates[peak_combined_idx]
    
    peak_split_rate = max(split_rates)
    peak_split_idx = split_rates.index(peak_split_rate) if peak_split_rate > 0 else -1
    peak_split_cores = cores_range[peak_split_idx] if peak_split_idx >= 0 else 0
    
    print(f"\nPeak Performance:")
    print(f"Combined: {peak_combined_rate:.1f} Mpps at {peak_combined_cores} cores")
    if peak_split_rate > 0:
        print(f"Split: {peak_split_rate:.1f} Mpps at {peak_split_cores} cores")
        print(f"Split efficiency: {peak_split_rate/peak_combined_rate*100:.1f}% of combined peak")

if __name__ == "__main__":
    main()
