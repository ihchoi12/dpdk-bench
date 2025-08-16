#!/usr/bin/env bash
# Port Mapping Comparison Script
# This script runs all port mapping modes and compares the results

source "$(dirname "${BASH_SOURCE[0]}")/common-header.sh"

echo ">> Running port mapping comparison benchmark"
echo "   Testing modes: combined, split"
echo ""

# Array of modes to test
modes=("combined" "split")

# Run each mode
for mode in "${modes[@]}"; do
    echo "=== Running benchmark with $mode port mapping ==="
    ./scripts/benchmark-multi-core-tx-rate.sh "$mode"
    echo ""
    sleep 2
done

echo "=== Comparison completed ==="
echo "Results saved in results/ directory with timestamps"
echo ""
echo "To compare results, check the latest files:"
ls -la "${REPO_ROOT}/results/"*multi-core-tx-*.txt | tail -2

echo ""
echo "Quick performance summary:"
echo "Mode     | 1 Core | 2 Core | 4 Core | 6 Core | 8 Core"
echo "---------|--------|--------|--------|--------|--------"

for mode in "${modes[@]}"; do
    latest_file=$(ls -t "${REPO_ROOT}/results/"*multi-core-tx-${mode}.txt 2>/dev/null | head -1)
    if [ -f "$latest_file" ]; then
        # Disable exit on error for performance extraction
        set +e
        
        # Extract performance data based on actual core configurations
        if [ "$mode" = "combined" ]; then
            # Combined mode: extract 1st, 2nd, 4th, 6th, 8th lines (cores 1,2,4,6,8)
            perf1=$(grep -E '\|[0-9.]+$' "$latest_file" | sed -n '1p' | sed 's/.*|\([0-9.]*\)/\1/' || echo "N/A")
            perf2=$(grep -E '\|[0-9.]+$' "$latest_file" | sed -n '2p' | sed 's/.*|\([0-9.]*\)/\1/' || echo "N/A")
            perf4=$(grep -E '\|[0-9.]+$' "$latest_file" | sed -n '4p' | sed 's/.*|\([0-9.]*\)/\1/' || echo "N/A")
            perf6=$(grep -E '\|[0-9.]+$' "$latest_file" | sed -n '6p' | sed 's/.*|\([0-9.]*\)/\1/' || echo "N/A")
            perf8=$(grep -E '\|[0-9.]+$' "$latest_file" | sed -n '8p' | sed 's/.*|\([0-9.]*\)/\1/' || echo "N/A")
        elif [ "$mode" = "split" ]; then
            # Split mode: extract 1st, 2nd, 3rd, 4th lines (cores 2,4,6,8)
            perf1="N/A"  # Split mode doesn't test 1 core
            perf2=$(grep -E '\|[0-9.]+$' "$latest_file" | sed -n '1p' | sed 's/.*|\([0-9.]*\)/\1/' || echo "N/A")
            perf4=$(grep -E '\|[0-9.]+$' "$latest_file" | sed -n '2p' | sed 's/.*|\([0-9.]*\)/\1/' || echo "N/A")
            perf6=$(grep -E '\|[0-9.]+$' "$latest_file" | sed -n '3p' | sed 's/.*|\([0-9.]*\)/\1/' || echo "N/A")
            perf8=$(grep -E '\|[0-9.]+$' "$latest_file" | sed -n '4p' | sed 's/.*|\([0-9.]*\)/\1/' || echo "N/A")
        fi
        
        # Re-enable exit on error
        set -e
        
        printf "%-8s | %6s | %6s | %6s | %6s | %6s\n" "$mode" "$perf1" "$perf2" "$perf4" "$perf6" "$perf8"
    else
        printf "%-8s | %6s | %6s | %6s | %6s | %6s\n" "$mode" "N/A" "N/A" "N/A" "N/A" "N/A"
    fi
done
