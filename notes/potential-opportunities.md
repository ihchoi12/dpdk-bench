# DPDK Performance Optimization Opportunities

## 1. Mempool Single-Consumer/Single-Producer Optimization

**Current State**: Port-shared mempool with Multi-Consumer/Multi-Producer (MC/MP)
- `dpdk/lib/mbuf/rte_mbuf.c:249`: `rte_mempool_create_empty(..., 0)` - flags hardcoded to MC/MP
- `Pktgen-DPDK/app/l2p.h:45`: `struct rte_mempool *tx_mp` - one mempool per port, shared by multiple lcores
- `Pktgen-DPDK/app/l2p.c:161`: `port->tx_mp = l2p_pktmbuf_create(...)` - created once per port

**Issue**: Multiple TX cores access same mempool → atomic CAS operations (~20-50 cycles on contention)

**Opportunity**: Per-lcore mempool with Single-Consumer/Single-Producer (SC/SP)
- Change to: `struct rte_mempool *tx_mp[RTE_MAX_LCORE]` (per-lcore instead of per-port)
- Use flags: `RTE_MEMPOOL_F_SC_GET | RTE_MEMPOOL_F_SP_PUT`
- Non-atomic operations: ~5-10 cycles (2-5x faster on cache miss)

**Tradeoff**: Memory overhead (N lcores × mempool size vs 1 shared pool)

**Alternative**: Increase `MEMPOOL_CACHE_SIZE` from 256 to 512/1024 to improve cache hit rate and reduce global pool contention
