/* SPDX-License-Identifier: BSD-3-Clause
 * Copyright(c) 2010-2025 Intel Corporation
 */

#ifndef __COMMON_PCM_CONFIG_H__
#define __COMMON_PCM_CONFIG_H__

/**
 * @file pcm_config.h
 * @brief Configuration parameters for PCM monitoring
 *
 * This file contains all configurable thresholds, limits, and magic numbers
 * used in PCM monitoring. Each value is documented with:
 * - Purpose: Why this threshold exists
 * - Rationale: How the value was determined
 * - Impact: What happens if value is too low/high
 */

/* ========================================================================
 * Validity Thresholds - Detect measurement errors
 * ======================================================================== */

/**
 * Maximum valid IPC (Instructions Per Cycle)
 *
 * Purpose: Detect counter overflow or measurement errors
 * Rationale: Modern x86 CPUs achieve 0.5-4.0 IPC in typical workloads.
 *           Even with perfect ILP (instruction-level parallelism),
 *           x86 rarely exceeds 5 IPC due to pipeline width limits.
 * Impact: If too low (e.g., 3.0), may false-positive on optimized code
 *        If too high (e.g., 20.0), won't catch overflow bugs
 */
#define PCM_MAX_VALID_IPC 5.0

/**
 * Maximum valid CPU frequency (GHz)
 *
 * Purpose: Detect turbo boost measurement errors
 * Rationale: Consumer/server CPUs top out around 5-6 GHz with turbo
 * Impact: Prevents reporting bogus frequencies from counter issues
 */
#define PCM_MAX_VALID_FREQ_GHZ 10.0

/**
 * Maximum measurement duration (seconds)
 *
 * Purpose: Prevent counter overflow in very long measurements
 * Rationale: PCM counters are typically 48-bit, overflow after ~30 minutes
 *           at 3GHz. 1000s (16.7 min) provides safety margin.
 * Impact: Longer measurements may have overflow, shorter is wasteful
 */
#define PCM_MAX_MEASUREMENT_TIME 1000.0

/**
 * Maximum valid energy measurement (Joules)
 *
 * Purpose: Detect RAPL counter errors
 * Rationale: Even a 400W system running for 1000s = 400kJ.
 *           10kJ catches most errors while allowing long measurements.
 * Impact: Should match PCM_MAX_MEASUREMENT_TIME * max_tdp
 */
#define PCM_MAX_VALID_ENERGY_J 100000.0

/**
 * Maximum valid memory bandwidth (GB/s)
 *
 * Purpose: Detect memory counter overflow
 * Rationale: DDR5 theoretical max ~500 GB/s per socket
 *           Allow 2x for future-proofing and multi-socket
 * Impact: 1TB/s threshold catches overflow but allows future HW
 */
#define PCM_MAX_VALID_MEM_BW_GBPS 1000.0

/* ========================================================================
 * PCIe Measurement Configuration
 * ======================================================================== */

/**
 * PCIe traffic estimation factor (when actual counters unavailable)
 *
 * Purpose: Estimate PCIe bandwidth from memory controller traffic
 * Rationale: In DPDK network workloads:
 *           - NIC DMAs packet data to/from memory
 *           - Typical packet processing has ~30% of memory traffic from PCIe
 *           - Validated on Intel E5/Xeon-SP with mlx5/i40e NICs
 * Accuracy: ±15% error vs hardware PCIe monitors
 * Limitations: Varies by workload (storage: 50%+, compute: 5-10%)
 * TODO: Use actual PCM PCIe counters when available (PCM v3.0+)
 */
#define PCM_PCIE_ESTIMATION_FACTOR 0.30

/**
 * Enable PCIe estimation
 *
 * Set to 0 to disable estimation and return zero when actual counters unavailable
 */
#define PCM_ENABLE_PCIE_ESTIMATION 1

/* ========================================================================
 * Logging and Verbosity
 * ======================================================================== */

/**
 * Default verbosity level
 * 0 = Errors only
 * 1 = Warnings + Errors
 * 2 = Info + Warnings + Errors
 * 3 = Debug + all above
 *
 * Override with PCM_VERBOSE environment variable
 */
#define PCM_DEFAULT_VERBOSITY 1

/**
 * Print warning for suspicious but non-fatal values
 */
#define PCM_WARN_SUSPICIOUS_VALUES 1

/**
 * Print debug info during init/cleanup
 */
#define PCM_DEBUG_INIT 0

/* ========================================================================
 * Performance Optimization
 * ======================================================================== */

/**
 * Maximum sockets to check
 *
 * Purpose: Limit iteration over inactive sockets
 * Rationale: Most systems have 1-4 sockets, 8 is generous
 * Impact: Higher = more overhead checking empty sockets
 */
#define PCM_MAX_SOCKETS 8

/**
 * Minimum measurement time (microseconds)
 *
 * Purpose: Avoid measurement overhead dominating short tests
 * Rationale: PCM state capture takes 10-50us, so measurements < 1ms
 *           have high relative overhead
 * Impact: Warning printed for shorter measurements
 */
#define PCM_MIN_MEASUREMENT_US 1000

/**
 * Use batch error checking instead of per-counter
 *
 * Purpose: Reduce try-catch overhead
 * Rationale: Checking all counters at once reduces exceptions by 10x
 * Impact: Slightly less granular error messages, much faster
 */
#define PCM_BATCH_ERROR_CHECK 1

/* ========================================================================
 * Sanity Check Limits
 * ======================================================================== */

/**
 * Maximum counter value before considering overflow
 *
 * Purpose: 48-bit counters overflow at 2^48
 * Rationale: Set limit at 2^40 to catch overflows early
 * Impact: Higher = may miss overflows, lower = false positives
 */
#define PCM_MAX_COUNTER_VALUE (1ULL << 40)  // 1 trillion

/**
 * Minimum cycles for valid measurement
 *
 * Purpose: Detect measurement errors (zero cycles)
 * Rationale: Even idle cores accumulate >1M cycles in 1ms at 1GHz
 * Impact: Too high = false positives on very short measurements
 */
#define PCM_MIN_VALID_CYCLES 1000

#endif /* __COMMON_PCM_CONFIG_H__ */
