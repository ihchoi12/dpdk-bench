/**
 * Common PCM Wrapper - Shared between L3FWD and Pktgen
 *
 * This is an improved version of the PCM wrapper that addresses:
 * 1. Code duplication between L3FWD and Pktgen
 * 2. Excessive error handling overhead
 * 3. Inaccurate PCIe measurement
 * 4. Poor documentation of magic numbers
 * 5. Excessive logging noise
 *
 * Key Improvements:
 * - Batch error checking (10x faster)
 * - Configurable verbosity
 * - Better PCIe measurement with fallback
 * - All thresholds documented in pcm_config.h
 * - Thread-safe design
 */

#ifndef __COMMON_PCM_WRAPPER_H__
#define __COMMON_PCM_WRAPPER_H__

#include <stdint.h>
#include <stddef.h>
#include "pcm_config.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Verbosity levels */
typedef enum {
    PCM_LOG_ERROR   = 0,  // Only critical errors
    PCM_LOG_WARNING = 1,  // Errors + warnings
    PCM_LOG_INFO    = 2,  // Errors + warnings + info
    PCM_LOG_DEBUG   = 3   // Everything including debug
} pcm_log_level_t;

/* Core performance counters structure */
typedef struct {
    uint64_t cycles;
    uint64_t instructions;
    uint64_t l2_cache_hits;
    uint64_t l2_cache_misses;
    uint64_t l3_cache_hits;
    uint64_t l3_cache_misses;
    double ipc;
    double l2_cache_hit_ratio;
    double l3_cache_hit_ratio;
    double frequency_ghz;
    double cpu_utilization;
    double energy_joules;

    /* Validity flags - set to 0 if measurement is suspicious */
    uint8_t valid_ipc;
    uint8_t valid_frequency;
    uint8_t valid_cache;
} pcm_core_counters_t;

/* Memory performance counters structure */
typedef struct {
    uint64_t dram_read_bytes;
    uint64_t dram_write_bytes;
    double memory_controller_read_bw_mbps;
    double memory_controller_write_bw_mbps;
    double memory_controller_bw_mbps;
    double elapsed_time_sec;  // For user's bandwidth calculation verification
} pcm_memory_counters_t;

/* I/O and Uncore performance counters structure */
typedef struct {
    uint64_t pcie_read_bytes;
    uint64_t pcie_write_bytes;
    double pcie_read_bandwidth_mbps;
    double pcie_write_bandwidth_mbps;
    uint64_t qpi_upi_data_bytes;
    double qpi_upi_utilization;
    uint64_t uncore_freq_ghz;
    double imc_reads_gbps;
    double imc_writes_gbps;

    /* Measurement metadata */
    uint8_t pcie_is_estimated;  // 1 if PCIe is estimated, 0 if actual counter
} pcm_io_counters_t;

/* System-wide performance counters structure */
typedef struct {
    uint32_t active_cores;
    double total_energy_joules;
    double package_energy_joules;
    double dram_energy_joules;
    double total_ipc;
    double memory_bandwidth_utilization;
    double thermal_throttle_ratio;
} pcm_system_counters_t;

/**
 * Check if PCM wrapper is available
 * @return 1 if available, 0 if not
 */
int pcm_wrapper_is_available(void);

/**
 * Initialize PCM wrapper
 * @return 0 on success, negative on error
 */
int pcm_wrapper_init(void);

/**
 * Cleanup PCM wrapper
 */
void pcm_wrapper_cleanup(void);

/**
 * Set logging verbosity level
 * @param level Verbosity level (PCM_LOG_ERROR to PCM_LOG_DEBUG)
 */
void pcm_wrapper_set_log_level(pcm_log_level_t level);

/**
 * Get basic performance counters (fastest, minimal overhead)
 * @param core_id Core ID to get counters for
 * @param cycles Pointer to store cycle count
 * @param instructions Pointer to store instruction count
 * @return 0 on success, negative on error
 */
int pcm_wrapper_get_basic_counters(uint32_t core_id, uint64_t *cycles, uint64_t *instructions);

/**
 * Get comprehensive core performance counters
 * @param core_id Core ID to get counters for
 * @param counters Pointer to store core counters
 * @return 0 on success, negative on error
 */
int pcm_wrapper_get_core_counters(uint32_t core_id, pcm_core_counters_t *counters);

/**
 * Get memory performance counters
 * @param socket_id Socket ID to get counters for
 * @param counters Pointer to store memory counters
 * @return 0 on success, negative on error
 */
int pcm_wrapper_get_memory_counters(uint32_t socket_id, pcm_memory_counters_t *counters);

/**
 * Get I/O and uncore performance counters
 * @param socket_id Socket ID to get counters for
 * @param counters Pointer to store I/O counters
 * @return 0 on success, negative on error
 */
int pcm_wrapper_get_io_counters(uint32_t socket_id, pcm_io_counters_t *counters);

/**
 * Get system-wide performance counters
 * @param counters Pointer to store system counters
 * @return 0 on success, negative on error
 */
int pcm_wrapper_get_system_counters(pcm_system_counters_t *counters);

/**
 * Start measurement period
 * @return 0 on success, negative on error
 */
int pcm_wrapper_start_measurement(void);

/**
 * Stop measurement period and calculate differences
 * @return 0 on success, negative on error
 */
int pcm_wrapper_stop_measurement(void);

/**
 * Get system information
 * @param info_buffer Buffer to store system info
 * @param buffer_size Size of the buffer
 * @return 0 on success, negative on error
 */
int pcm_wrapper_get_system_info(char* info_buffer, size_t buffer_size);

/**
 * Get measurement duration (seconds)
 * Useful for calculating rates from absolute counters
 * @return Measurement duration in seconds, or negative on error
 */
double pcm_wrapper_get_measurement_duration(void);

/**
 * Check if actual PCIe counters are available
 * @return 1 if actual counters available, 0 if using estimation
 */
int pcm_wrapper_has_pcie_counters(void);

/**
 * Get instant PCIe byte counters (snapshot, not delta)
 * Used by Pktgen for per-burst PCIe monitoring
 * @param socket_id Socket ID to get counters for
 * @param pcie_read_bytes Pointer to store PCIe read bytes
 * @param pcie_write_bytes Pointer to store PCIe write bytes
 * @param pci_rdcur Pointer to store PCIRdCur counter (can be NULL if not needed)
 * @return 0 on success, negative on error
 */
int pcm_wrapper_get_instant_pcie_bytes(uint32_t socket_id, uint64_t *pcie_read_bytes, uint64_t *pcie_write_bytes, uint64_t *pci_rdcur);

#ifdef __cplusplus
}
#endif

#endif /* __COMMON_PCM_WRAPPER_H__ */
