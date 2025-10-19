/* SPDX-License-Identifier: BSD-3-Clause
 * Copyright(c) 2025 Autokernel Project
 */

#ifndef _AK_DEBUG_LOG_H_
#define _AK_DEBUG_LOG_H_

#ifdef __cplusplus
extern "C" {
#endif

/* Include necessary headers for logging */
#include <stdio.h>

/**
 * @file
 * 
 * Autokernel (AK) Debug Logging System
 * 
 * This provides a unified debug logging interface for both DPDK and Pktgen
 * components. Debug logs are enabled when RTE_LIBRTE_ETHDEV_DEBUG is defined.
 */

#ifdef RTE_LIBRTE_ETHDEV_DEBUG

/**
 * AK_DEBUG_LOG - General debug logging macro
 * @param level - Log level (e.g., INFO, NOTICE, DEBUG)
 * @param logtype - Log type/component identifier
 * @param ... - Format string and arguments (printf-style)
 */
#ifndef RTE_LOG
/* If RTE_LOG is not available (non-DPDK context), use fprintf */
#define AK_DEBUG_LOG(level, logtype, ...) \
	do { \
		fprintf(stderr, "[AK_DEBUG_%s:%s] ", #level, #logtype); \
		fprintf(stderr, __VA_ARGS__); \
		fprintf(stderr, "\n"); \
		fflush(stderr); \
	} while (0)
#else
/* Use DPDK's RTE_LOG when available */
#define AK_DEBUG_LOG(level, logtype, ...) \
	RTE_LOG(level, logtype, __VA_ARGS__)
#endif

/**
 * AK_DEBUG_LOG_LINE - Simple line-based debug logging
 * @param level - Log level (e.g., INFO, NOTICE, DEBUG)
 * @param ... - Format string and arguments (printf-style)
 */
#ifndef RTE_LOG_LINE
/* If RTE_LOG_LINE is not available, use fprintf */
#define AK_DEBUG_LOG_LINE(level, ...) \
	do { \
		fprintf(stderr, "[AK_DEBUG_%s] ", #level); \
		fprintf(stderr, __VA_ARGS__); \
		fprintf(stderr, "\n"); \
		fflush(stderr); \
	} while (0)
#else
/* Use DPDK's RTE_LOG_LINE when available */
#define AK_DEBUG_LOG_LINE(level, ...) \
	RTE_LOG_LINE(level, ETHDEV, "" __VA_ARGS__)
#endif

/**
 * AK_DEBUG_LOG_PKTGEN - Pktgen-specific debug logging
 * @param ... - Format string and arguments (printf-style)
 */
#define AK_DEBUG_LOG_PKTGEN(...) \
	do { \
		fprintf(stderr, "[PKTGEN] "); \
		fprintf(stderr, __VA_ARGS__); \
		fprintf(stderr, "\n"); \
		fflush(stderr); \
	} while (0)

/**
 * AK_DEBUG_LOG_L3FWD - L3FWD-specific debug logging
 * @param ... - Format string and arguments (printf-style)
 */
#define AK_DEBUG_LOG_L3FWD(...) \
	do { \
		fprintf(stderr, "[L3FWD] "); \
		fprintf(stderr, __VA_ARGS__); \
		fprintf(stderr, "\n"); \
		fflush(stderr); \
	} while (0)

#else /* RTE_LIBRTE_ETHDEV_DEBUG not defined */

/* All debug macros become no-ops when debug is disabled */
#define AK_DEBUG_LOG(level, logtype, ...) do { } while (0)
#define AK_DEBUG_LOG_LINE(level, ...) do { } while (0)
#define AK_DEBUG_LOG_PKTGEN(...) do { } while (0)
#define AK_DEBUG_LOG_L3FWD(...) do { } while (0)

#endif /* RTE_LIBRTE_ETHDEV_DEBUG */

#ifdef __cplusplus
}
#endif

#endif /* _AK_DEBUG_LOG_H_ */