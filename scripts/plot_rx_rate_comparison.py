#!/usr/bin/env python3
"""
L3FWD RX Rate Comparison Plotter
Compares RX rates between W/o inline TX vs With inline TX configurations
"""

import matplotlib.pyplot as plt
import numpy as np
import os
import sys

def parse_results_file(filepath):
    """Parse the benchmark results file and extract core counts and RX rates"""
    cores = []
    rx_rates = []
    
    try:
        with open(filepath, 'r') as f:
            for line in f:
                line = line.strip()
                # Skip comments and empty lines
                if line.startswith('#') or not line:
                    continue
                
                # Parse data lines: pktgen_config|l3fwd_Ncore|RX_rate|TX_rate
                parts = line.split('|')
                if len(parts) >= 3:
                    l3fwd_setup = parts[1]  # e.g., "l3fwd_1core"
                    rx_rate = float(parts[2])
                    
                    # Extract core count from "l3fwd_Ncore"
                    if l3fwd_setup.startswith('l3fwd_') and l3fwd_setup.endswith('core'):
                        core_str = l3fwd_setup[6:-4]  # Remove "l3fwd_" and "core"
                        core_count = int(core_str)
                        cores.append(core_count)
                        rx_rates.append(rx_rate)
    
    except Exception as e:
        print(f"Error parsing {filepath}: {e}")
        return [], []
    
    return cores, rx_rates

def create_comparison_plot(file1_path, file2_path, output_path):
    """Create comparison bar graph of RX rates"""
    
    # Parse both files
    cores1, rx_rates1 = parse_results_file(file1_path)
    cores2, rx_rates2 = parse_results_file(file2_path)
    
    if not cores1 or not cores2:
        print("Error: Could not parse data from input files")
        return False
    
    # Ensure both datasets have the same core counts
    cores1_set = set(cores1)
    cores2_set = set(cores2)
    common_cores = sorted(cores1_set & cores2_set)
    
    if not common_cores:
        print("Error: No common core counts found between the two files")
        return False
    
    # Create dictionaries for easy lookup
    rx1_dict = dict(zip(cores1, rx_rates1))
    rx2_dict = dict(zip(cores2, rx_rates2))
    
    # Extract data for common cores
    cores = common_cores
    rx_rates_without_inline = [rx1_dict[core] for core in cores]
    rx_rates_with_inline = [rx2_dict[core] for core in cores]
    
    # Create the plot
    plt.figure(figsize=(14, 8))
    
    # Set up bar positions
    x = np.arange(len(cores))
    width = 0.35
    
    # Create bars
    bars1 = plt.bar(x - width/2, rx_rates_without_inline, width, 
                   label='W/o inline TX', color='#2E86AB', alpha=0.8)
    bars2 = plt.bar(x + width/2, rx_rates_with_inline, width,
                   label='With inline TX', color='#A23B72', alpha=0.8)
    
    # Customize the plot
    plt.xlabel('L3FWD Core Count', fontsize=12, fontweight='bold')
    plt.ylabel('RX Rate (Mpps)', fontsize=12, fontweight='bold')
    plt.title('L3FWD RX Rate Comparison: W/o vs With Inline TX', 
              fontsize=14, fontweight='bold', pad=20)
    
    # Set x-axis
    plt.xticks(x, cores)
    plt.xlabel('L3FWD Core Count')
    
    # Add grid for better readability
    plt.grid(True, alpha=0.3, linestyle='--')
    
    # Add legend
    plt.legend(fontsize=11, loc='upper right')
    
    # Add value labels on bars
    def add_value_labels(bars, values):
        for bar, value in zip(bars, values):
            height = bar.get_height()
            plt.text(bar.get_x() + bar.get_width()/2., height + 0.1,
                    f'{value:.1f}', ha='center', va='bottom', fontsize=9)
    
    add_value_labels(bars1, rx_rates_without_inline)
    add_value_labels(bars2, rx_rates_with_inline)
    
    # Adjust y-axis to accommodate labels
    y_max = max(max(rx_rates_without_inline), max(rx_rates_with_inline))
    plt.ylim(0, y_max * 1.15)
    
    # Improve layout
    plt.tight_layout()
    
    # Save the plot
    plt.savefig(output_path, dpi=300, bbox_inches='tight', 
                facecolor='white', edgecolor='none')
    plt.close()
    
    print(f"Graph saved to: {output_path}")
    
    # Print summary statistics
    print("\n=== Summary Statistics ===")
    print(f"Core Range: {min(cores)} - {max(cores)}")
    print(f"W/o inline TX - Average RX: {np.mean(rx_rates_without_inline):.2f} Mpps")
    print(f"With inline TX - Average RX: {np.mean(rx_rates_with_inline):.2f} Mpps")
    print(f"Performance difference: {((np.mean(rx_rates_without_inline) / np.mean(rx_rates_with_inline) - 1) * 100):+.1f}%")
    
    return True

def main():
    # Get the script directory and repository root
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.dirname(script_dir)
    results_dir = os.path.join(repo_root, 'results')
    
    # Input files
    file1 = os.path.join(results_dir, '250816-225956-l3fwd-vs-pktgen.txt')  # W/o inline TX
    file2 = os.path.join(results_dir, '250816-230908-l3fwd-vs-pktgen.txt')  # With inline TX
    
    # Output file
    output_file = os.path.join(results_dir, 'l3fwd_rx_rate_comparison.png')
    
    # Check if input files exist
    if not os.path.exists(file1):
        print(f"Error: File not found: {file1}")
        return 1
    
    if not os.path.exists(file2):
        print(f"Error: File not found: {file2}")
        return 1
    
    # Create the comparison plot
    success = create_comparison_plot(file1, file2, output_file)
    
    if success:
        print("RX rate comparison graph created successfully!")
        return 0
    else:
        print("Failed to create comparison graph")
        return 1

if __name__ == "__main__":
    sys.exit(main())
