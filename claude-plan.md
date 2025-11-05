# DPDK Adaptive Tuning Research Plan

## Project Goal
Systematically discover high-impact DPDK parameters and develop adaptive tuning strategies to optimize performance under dynamic conditions.

---

## Research Approach

**Bottom-up, Data-driven Strategy:**
1. Discover parameters one-by-one through systematic experiments
2. Quantify impact and identify tuning patterns for each
3. Test under dynamic/challenging scenarios
4. Build adaptive solution (complexity scales with need)

**Key Insight:**
Start with concrete findings, let the story emerge naturally from data, use ML only if simple approaches prove insufficient.

---

## CURRENT WORK: txqs_min_inline Producer-Consumer Analysis

**Goal:** Understand txqs_min_inline using producer-consumer model: measure TX queue depth to determine when CPU (producer) exceeds NIC (consumer) capacity.

**Hypothesis:** When TX queue utilization > threshold (e.g., 75%), NIC is bottleneck → inline mode helps by reducing NIC's PCIe read burden.

---

### Step 1: Understanding Current Pktgen Code (Week 1, Days 1-2)

#### 1.1 Locate TX Queue Monitoring Code
- [x] Find Pktgen's main TX loop
  - [x] Search for `rte_eth_tx_burst` in Pktgen source
  - [x] Identify file and function: `Pktgen-DPDK/app/pktgen.c:509`
  - [x] Document code location (file:line)
- [x] Find where port statistics are collected
  - [x] Search for `rte_eth_stats_get` usage
  - [x] Document current stats collection points: `pktgen-stats.c:498`
- [x] Check if TX queue info is already monitored
  - [x] Search for `rte_eth_tx_queue_info_get`
  - [x] Not found - we need to add it

#### 1.2 Review Pktgen Statistics Infrastructure
- [x] Understand Pktgen's stats output format
  - [x] Run Pktgen: Checked output from `print_pktgen_stats_summary()`
  - [x] Stats shown: Per-lcore RX/TX packets, rates, per-queue counts
  - [x] Missing: Queue depth/utilization
- [x] Find stats printing code
  - [x] Main function: `pktgen.c:1835` - `print_pktgen_stats_summary()`
  - [x] Stats collection: `pktgen-stats.c:498`
  - [x] Update frequency: ~1 second
- [x] Check if stats are logged to file
  - [x] Existing: PCIe logging, PCM logging
  - [x] Plan: Create `pktgen_tx_queue_log.c` for queue stats

**Deliverable 1.1-1.2:** Documentation of Pktgen code structure for stats collection ✅

---

### Step 2: Add TX Queue Depth Monitoring (Week 1, Days 3-4)

#### 2.1 Implement Queue Depth Collection
- [x] Add queue info monitoring to Pktgen
  - [x] Created `pktgen-txqueue.h` and `pktgen-txqueue.c`
  - [x] Implemented `pktgen_get_txqueue_info()`
  - [x] Calls `rte_eth_tx_queue_info_get()` for each TX queue
  - [x] Calculates utilization: `nb_used / nb_desc`
- [x] Integrate into main stats loop
  - [x] Added to `pktgen-stats.c:546-562`
  - [x] Runs every 1 second with other stats
  - [x] Added to meson.build

#### 2.2 Add Logging to File ⚠️
- [x] Create CSV logging function
  - [x] File format: `timestamp, port, queue, nb_desc, nb_used, utilization`
  - [x] Open log file at start: `/tmp/tx_queue_stats.csv`
  - [x] Append stats every 1 second
  - [x] Close on exit
- [x] Test logging
  - [x] Run short experiment (5 seconds)
  - [x] Verify CSV file created and readable: 169 lines (21 seconds × 8 queues + header)
  - [x] Data format correct
- [x] Debug and fix issues
  - [x] Fixed permission denied (changed to /tmp/)
  - [x] Fixed zero queue count (use l2p_get_txcnt instead of dev_info)
  - [x] Identified DPDK API limitation (nb_used not available)

**Critical Finding:** Standard DPDK API does not expose queue depth (nb_used).
- Current logs show only static configuration (nb_desc=1024)
- Need alternative approach for queue utilization (see Step 2.4 below)

#### 2.3 Patch and Rebuild ✅
- [x] Rebuild Pktgen
  - [x] `make pktgen-rebuild` - Success
  - [x] Verify build succeeds - All tests pass
- [x] Test modified Pktgen
  - [x] Run basic test: `make run-pktgen-with-lua-script`
  - [x] Check that queue stats appear in output/log: `/tmp/tx_queue_stats.csv` created
- [ ] Create Pktgen patch (deferred until queue depth solution implemented)

#### 2.4 Address Queue Depth Limitation 🚧 (NEW)
**Problem:** `rte_eth_tx_queue_info_get()` does not provide runtime queue depth
**Options:**
1. **Option 1 (MLX5-specific):** Access driver internals (`elts_head - elts_tail`)
2. **Option 2 (DPDK patch):** Add `nb_used` field to `struct rte_eth_txq_info`
3. **Option 3 (Instrumentation):** Track descriptors in Pktgen TX path
4. **Option 4 (Proxy metrics):** Use PCIe bandwidth + TX rate as bottleneck indicators

**Decision needed:** Which approach to take?
- [ ] Option 4 is fastest - proceed with correlation analysis (next step)
- [ ] Option 1 or 2 for accurate queue depth measurement (future work)

**Deliverable 2.1-2.4:** Modified Pktgen with TX queue monitoring infrastructure ⚠️
**Status:** Infrastructure complete, but nb_used=0 due to API limitation

---

### Step 3: Systematic Experiments (Week 1 Day 5 - Week 2)

#### 3.1 Design Experiment Matrix
- [ ] Define test parameters
  - [ ] TX cores: [1, 2, 4, 8, 16]
  - [ ] Traffic rate: [1, 5, 10, 15, 20] Mpps (or max achievable)
  - [ ] Packet size: [64, 1500] bytes (start simple)
  - [ ] Inline values: [0, 8] (ON vs OFF)
- [ ] Calculate total experiments
  - [ ] 5 cores × 5 rates × 2 pkt_sizes × 2 inline = 100 experiments
  - [ ] 3 trials each = 300 runs
  - [ ] ~3 min each = 15 hours total
- [ ] Plan execution schedule
  - [ ] Run overnight/weekend
  - [ ] Monitor for failures

#### 3.2 Create Automation Script
- [ ] Write experiment runner script
  - [ ] `scripts/run_inline_experiments.sh`
  - [ ] Nested loops: cores, rates, packet sizes, inline values
  - [ ] For each config:
    - [ ] Update `pktgen.config` with parameters
    - [ ] Run Pktgen for 60 seconds
    - [ ] Collect: `tx_queue_stats.csv`, perf stats, throughput
    - [ ] Archive results: `results/inline_exp_<config>_<timestamp>/`
  - [ ] Retry logic for failures (up to 3 attempts)
  - [ ] Progress tracking (print "X/300 complete")
- [ ] Test automation
  - [ ] Dry run with 2-3 configs
  - [ ] Verify all data collected correctly
  - [ ] Check archive structure

#### 3.3 Execute Experiments
- [ ] Run Batch 1: cores=[1,2], all rates/sizes (60 runs)
  - [ ] Monitor first few runs manually
  - [ ] Check for issues
  - [ ] Let rest run unattended
- [ ] Run Batch 2: cores=[4,8], all rates/sizes (60 runs)
- [ ] Run Batch 3: cores=[16], all rates/sizes (30 runs)
- [ ] Run Batch 4: Repeat for statistical confidence (150 runs)

#### 3.4 Data Validation
- [ ] Check for missing data
  - [ ] List all result directories
  - [ ] Verify each has complete files
  - [ ] Identify failed experiments
- [ ] Re-run failures
  - [ ] Extract failed configs
  - [ ] Re-run manually or in batch
- [ ] Verify data quality
  - [ ] Check CSV files are not corrupted
  - [ ] Spot check values are reasonable
  - [ ] Calculate variance across trials

**Deliverable 3.1-3.4:** Complete dataset (~300 experiment results)

---

### Step 4: Data Analysis (Week 2-3)

#### 4.1 Data Aggregation
- [ ] Write analysis script
  - [ ] `scripts/analyze_inline_experiments.py`
  - [ ] Load all CSV files
  - [ ] Parse experiment config from directory names
  - [ ] Aggregate into single DataFrame
- [ ] Calculate metrics per config
  - [ ] Mean queue_util (over 60 second run)
  - [ ] Mean throughput
  - [ ] Mean PCIe read BW
  - [ ] Mean CPU utilization
- [ ] Compute inline benefit
  - [ ] For each (cores, rate, pkt_size):
    - [ ] `benefit = (throughput_inline0 - throughput_inline8) / throughput_inline8`
    - [ ] `queue_delta = queue_util_inline8 - queue_util_inline0`

#### 4.2 Correlation Analysis
- [ ] Plot: Queue Utilization vs Inline Benefit
  - [ ] X-axis: queue_util (with inline=8, i.e., OFF)
  - [ ] Y-axis: inline benefit (% improvement)
  - [ ] Color by: cores, rate, or pkt_size
  - [ ] Add trend line
  - [ ] Save: `results/plots/queue_vs_benefit.png`
- [ ] Find threshold
  - [ ] Identify queue_util value where benefit > 0
  - [ ] e.g., "benefit > 5% when queue_util > 75%"
  - [ ] Calculate correlation coefficient
- [ ] Statistical analysis
  - [ ] T-test: benefit with high queue vs low queue
  - [ ] Confidence intervals

#### 4.3 Visualizations
- [ ] Create heatmaps
  - [ ] (cores, rate) → queue_util (inline OFF)
  - [ ] (cores, rate) → inline benefit
  - [ ] Save as PNG
- [ ] Time series plots
  - [ ] Example experiments showing queue_util over time
  - [ ] Compare inline ON vs OFF
  - [ ] Annotate with throughput
- [ ] Summary table
  - [ ] Per (cores, rate): queue_util, benefit, decision
  - [ ] Export as CSV and LaTeX table

**Deliverable 4.1-4.3:** Analysis results with visualizations

---

### Step 5: Rule Extraction (Week 3)

#### 5.1 Derive Decision Rule
- [ ] Based on data, define threshold
  - [ ] e.g., "If queue_util > 70%, use inline=0"
  - [ ] Justify with data (correlation, benefit)
- [ ] Test rule accuracy
  - [ ] Apply rule to all experiments
  - [ ] Measure: % of cases where rule predicts benefit correctly
  - [ ] Target: >90% accuracy
- [ ] Refine if needed
  - [ ] If accuracy low, try different threshold
  - [ ] Consider multi-dimensional rule (queue + CPU util)

#### 5.2 Validate on Held-Out Data
- [ ] Split data: 70% training, 30% test
  - [ ] Derive threshold on training set
  - [ ] Test accuracy on test set
- [ ] Measure performance
  - [ ] Precision, recall, F1 score
  - [ ] Confusion matrix
- [ ] Compare with baselines
  - [ ] Baseline 1: Always inline=8 (default)
  - [ ] Baseline 2: Always inline=0
  - [ ] Baseline 3: cores < 8 → inline=0 (simple rule)
  - [ ] Our rule: queue-based

#### 5.3 Document Findings
- [ ] Write mini-report (5-7 pages)
  - [ ] **Introduction**: txqs_min_inline importance
  - [ ] **Background**: Inline mode mechanism
  - [ ] **Methodology**: Producer-consumer model, experiments
  - [ ] **Results**:
    - [ ] Queue utilization patterns
    - [ ] Correlation with benefit
    - [ ] Threshold derivation
  - [ ] **Discussion**: When and why inline helps
  - [ ] **Conclusion**: Rule and its accuracy
- [ ] Create presentation slides (10-15 slides)
  - [ ] For lab meeting or advisor update
  - [ ] Key plots and findings

**Deliverable 5.1-5.3:** Decision rule + validation + mini-report

---

### Step 6: Integration & Next Steps (Week 3-4)

#### 6.1 Update Pktgen Config
- [ ] Add adaptive inline logic (manual for now)
  - [ ] Script to measure queue_util in real-time
  - [ ] Suggest inline value based on rule
  - [ ] (Actual dynamic change requires restart, but can guide config)
- [ ] Document how to use
  - [ ] README section on inline tuning
  - [ ] Example commands

#### 6.2 Commit and Archive
- [ ] Commit Pktgen changes
  - [ ] Update `build/pktgen.patch` with queue monitoring code
  - [ ] Git commit with message
- [ ] Archive all data
  - [ ] Compress experiment results: `tar -czf inline_experiments.tar.gz results/inline_exp_*`
  - [ ] Store analysis scripts and notebooks
  - [ ] Backup to external storage
- [ ] Update `claude-plan.md`
  - [ ] Check off completed tasks
  - [ ] Note key findings in "Important Findings" section

#### 6.3 Prepare for Next Parameter
- [ ] Identify next parameter to study
  - [ ] Based on `pktgen_parameters.default` review
  - [ ] Likely candidate: TX/RX descriptor sizes
- [ ] Plan similar methodology
  - [ ] What metrics to monitor?
  - [ ] What is the hypothesis?
  - [ ] Experiment design

**Deliverable 6.1-6.3:** Completed txqs_min_inline study, ready for next parameter

---

## CHECKPOINT: Review Before Proceeding

**After completing Steps 1-6, review:**
- [ ] Do we have clear evidence that queue-based rule works?
- [ ] Is the rule simple and practical?
- [ ] Is the improvement significant (>10%)?
- [ ] Can we write a strong paper section on this?

**If YES to all:** Proceed to next parameter (Descriptor sizes)
**If NO:** Iterate on analysis or pivot approach

---

## Phase 1: Parameter Discovery & Characterization (Weeks 4-15)

### Milestone 1.1: Infrastructure Setup (Week 1)

#### 1.1.1 Experiment Automation
- [ ] Enhance `run_test.py` for parameter sweeps
  - [ ] Support arbitrary DPDK device arguments (-a parameters)
  - [ ] Configurable parameter ranges
  - [ ] Automatic retry on failures
  - [ ] Result archival with full metadata
- [ ] Create parameter exploration framework
  - [ ] Template for testing new parameters
  - [ ] Automated result parsing
  - [ ] Statistical analysis utilities

#### 1.1.2 Monitoring Integration
- [ ] Hardware metrics collection
  - [ ] PCIe bandwidth (read/write) - already using perf
  - [ ] LLC misses
  - [ ] DRAM bandwidth via PCM
  - [ ] CPU utilization per core
- [ ] Unified logging
  - [ ] CSV format with all metrics
  - [ ] Timestamp alignment
  - [ ] Validation checks

#### 1.1.3 Workload Library
- [ ] Basic workloads (start simple)
  - [ ] Uniform 64B packets
  - [ ] Uniform 1500B packets
  - [ ] Low rate (~1 Mpps)
  - [ ] High rate (~10+ Mpps)
  - [ ] Bursty traffic
- [ ] Add more workloads as needed

**Deliverable 1.1:** Automated framework for systematic parameter exploration

---

### Milestone 1.2: txqs_min_inline Deep Dive (Weeks 2-3)

**Goal:** Fully understand txqs_min_inline behavior (already started)

#### 1.2.1 Complete txqs_min_inline Experiments
- [ ] Systematic sweep
  - [ ] Values: 0, 8, 16, 32, 64, 128 (and maybe more)
  - [ ] Core counts: 1, 2, 4, 8, 16
  - [ ] Packet sizes: 64B, 256B, 512B, 1500B
  - [ ] 3 trials each for statistical confidence
- [ ] Measure all metrics
  - [ ] Throughput (Mpps)
  - [ ] PCIe read/write bandwidth
  - [ ] CPU utilization
  - [ ] Latency (if possible)

#### 1.2.2 Analysis
- [ ] Create performance heatmaps
  - [ ] (cores, txqs_min_inline) → throughput
  - [ ] (cores, txqs_min_inline) → PCIe BW
- [ ] Identify patterns
  - [ ] When does inline mode help? (condition: cores < X and PCIe read limited)
  - [ ] When does it hurt? (overhead without benefit)
  - [ ] Optimal values for different scenarios
- [ ] Quantify impact
  - [ ] Best case improvement: X%
  - [ ] Worst case degradation: Y%
  - [ ] Average benefit: Z%

#### 1.2.3 Document Findings
- [ ] Write mini-report (3-5 pages)
  - [ ] Background on txqs_min_inline
  - [ ] Experimental setup
  - [ ] Results and analysis
  - [ ] Tuning guidelines discovered
- [ ] Create tuning rule
  - [ ] e.g., "if cores < 8 and pcie_read > threshold: use inline=0"

**Deliverable 1.2:** Complete txqs_min_inline characterization + tuning rule

---

### Milestone 1.3: TX/RX Descriptor Sizes (Weeks 4-5)

**Goal:** Understand descriptor ring size impact

#### 1.3.1 Descriptor Size Experiments
- [ ] Parameter sweep
  - [ ] TX desc: 128, 256, 512, 1024, 2048
  - [ ] RX desc: 128, 256, 512, 1024, 2048
  - [ ] Test key workloads (4-5 patterns)
  - [ ] Vary traffic rates
- [ ] Measure impact
  - [ ] Throughput
  - [ ] Packet drops
  - [ ] Memory usage
  - [ ] Cache effects (LLC miss rate)

#### 1.3.2 Analysis
- [ ] Find sweet spots
  - [ ] Small descriptors: when good? (cache-friendly, low latency)
  - [ ] Large descriptors: when good? (burst handling)
  - [ ] Trade-offs quantified
- [ ] Interaction with txqs_min_inline
  - [ ] Test combinations
  - [ ] Are they independent or coupled?
- [ ] Counter-intuitive findings?
  - [ ] e.g., "High LLC miss → smaller descriptor better" (cache thrashing)

#### 1.3.3 Document
- [ ] Mini-report on descriptor sizing
- [ ] Tuning rules extracted

**Deliverable 1.3:** Descriptor size characterization + tuning rules

---

### Milestone 1.4: Additional Parameters (Weeks 6-10)

**Goal:** Systematically test remaining high-impact parameters

#### 1.4.1 Identify Candidate Parameters
- [ ] Review `pktgen_parameters.default`
- [ ] Research DPDK/MLX5 documentation
- [ ] Prioritize by likely impact:
  - [ ] Batch/burst size
  - [ ] Prefetch settings
  - [ ] Queue depth
  - [ ] Interrupt coalescing
  - [ ] Memory pool size
  - [ ] (Add more as discovered)

#### 1.4.2 Test Each Parameter (2 weeks per parameter)
For each high-priority parameter:
- [ ] Parameter 3: ___________
  - [ ] Design experiments
  - [ ] Run systematic sweep
  - [ ] Analyze results
  - [ ] Extract tuning rules
  - [ ] Document findings

- [ ] Parameter 4: ___________
  - [ ] (Same process)

- [ ] Parameter 5: ___________
  - [ ] (Same process)

**Goal:** Test 3-5 additional parameters (pick most impactful)

#### 1.4.3 Cross-Parameter Interactions
- [ ] Test key combinations
  - [ ] Do parameters interact? (non-linear effects)
  - [ ] Are there emergent behaviors?
- [ ] Build interaction matrix
  - [ ] Which combinations matter
  - [ ] Which are independent

**Deliverable 1.4:** Characterization of 3-5+ parameters, tuning rules for each

---

### Milestone 1.5: Synthesis & Rule Compilation (Week 11-12)

#### 1.5.1 Compile All Findings
- [ ] Aggregate all parameter studies
- [ ] Create unified tuning guideline document
- [ ] Identify most impactful parameters (rank by impact)

#### 1.5.2 Build Simple Rule-Based Tuner
- [ ] Implement static rules from all discoveries
  - [ ] If-else logic based on conditions
  - [ ] Example: "if cores < 8: inline=0; if LLC_miss > X: small_desc"
- [ ] Test rule-based tuner
  - [ ] Apply to all tested workloads
  - [ ] Measure performance vs default config
  - [ ] Quantify improvement

#### 1.5.3 Write Phase 1 Report
- [ ] Comprehensive document (15-20 pages)
  - [ ] Introduction: parameter tuning importance
  - [ ] Methodology: systematic exploration
  - [ ] Per-parameter findings (one section each)
  - [ ] Cross-parameter interactions
  - [ ] Tuning rules derived
  - [ ] Simple rule-based tuner results
  - [ ] Limitations of static rules (preview Phase 2)

**Deliverable 1.5:** Phase 1 report + rule-based tuner

---

## Phase 2: Dynamic Scenarios & Limitations (Weeks 13-20)

**Goal:** Show when static rules fail, motivate adaptive approach

### Milestone 2.1: Dynamic Workload Testing (Weeks 13-15)

#### 2.1.1 Workload Shifts
- [ ] Design workload transition experiments
  - [ ] Sudden traffic rate changes (1 Mpps → 10 Mpps)
  - [ ] Packet size shifts (64B → 1500B)
  - [ ] Traffic pattern changes (uniform → bursty)
- [ ] Test static config behavior
  - [ ] How much does performance degrade?
  - [ ] Can single config handle all cases?
- [ ] Measure adaptation need
  - [ ] Optimal config per phase
  - [ ] Performance gap with static config

#### 2.1.2 Resource Contention
- [ ] Co-located application interference
  - [ ] Run memory-intensive app alongside DPDK
  - [ ] Run CPU-intensive app
  - [ ] Run I/O-intensive app
- [ ] Measure impact on DPDK
  - [ ] Throughput degradation
  - [ ] Resource metrics (PCIe BW, cache, memory)
  - [ ] Does optimal config change under contention?

#### 2.1.3 Hardware Variation
- [ ] Test on different hardware (if available)
  - [ ] Different NIC models
  - [ ] Different CPU generations
  - [ ] Different memory configurations
- [ ] Measure portability
  - [ ] Do tuning rules transfer?
  - [ ] Or are they hardware-specific?

**Deliverable 2.1:** Evidence that dynamic conditions require adaptive tuning

---

### Milestone 2.2: Static Rule Limitations (Weeks 16-17)

#### 2.2.1 Failure Case Collection
- [ ] Document where static rules fail
  - [ ] Specific scenarios identified
  - [ ] Performance gap quantified
  - [ ] Root cause analysis
- [ ] Categorize failure modes
  - [ ] Threshold sensitivity
  - [ ] Missing context
  - [ ] Complex interactions

#### 2.2.2 Quantify Opportunity
- [ ] Measure dynamic range
  - [ ] Best possible performance (oracle with perfect config)
  - [ ] Static rule performance
  - [ ] Gap = opportunity for adaptation
- [ ] Calculate adaptation benefit
  - [ ] If adaptive system could switch configs perfectly
  - [ ] How much improvement possible?
  - [ ] Is it worth the complexity?

**Deliverable 2.2:** Clear motivation for adaptive tuning (quantified gap)

---

### Milestone 2.3: Lookup Table Baseline (Weeks 18-19)

#### 2.3.1 Build Lookup Table System
- [ ] Design workload fingerprinting
  - [ ] Key metrics: PCIe BW, packet rate, LLC miss, etc.
  - [ ] Normalize and hash to fingerprint
- [ ] Create lookup table
  - [ ] Entry: (fingerprint → optimal config)
  - [ ] Populated from Phase 1 experiments
  - [ ] 20-50 entries
- [ ] Implement nearest-neighbor matching
  - [ ] For unseen workloads
  - [ ] Distance metric in feature space

#### 2.3.2 Test Lookup Table
- [ ] Test on known workloads (should be good)
- [ ] Test on unseen workloads (generalization)
- [ ] Test on dynamic scenarios (adaptation speed?)
- [ ] Measure performance
  - [ ] Accuracy vs oracle
  - [ ] Better than static rules?
  - [ ] Where does it fail?

#### 2.3.3 Analyze Limitations
- [ ] Document failure cases
  - [ ] Nearest neighbor gives wrong config
  - [ ] Interpolation issues
  - [ ] Non-linear decision boundaries
- [ ] This motivates ML (if true)

**Deliverable 2.3:** Lookup table baseline + documented limitations

---

### Milestone 2.4: Phase 2 Report & Decision (Week 20)

#### 2.4.1 Write Phase 2 Report
- [ ] Dynamic scenario results
- [ ] Static rule limitations
- [ ] Lookup table evaluation
- [ ] Gap analysis: opportunity for improvement

#### 2.4.2 Decision Point
- [ ] Review findings
  - [ ] Is gap significant? (>20-30%)
  - [ ] Are failure cases common?
  - [ ] Is adaptive system justified?
- [ ] Make decision:
  - [ ] **Option A**: Gap large → proceed to ML-based adaptive system (Phase 3)
  - [ ] **Option B**: Gap small → publish characterization + simple rules
  - [ ] **Option C**: Hybrid approach → extended lookup table or heuristic refinement

**Deliverable 2.4:** Phase 2 report + Go/No-go decision for ML system

---

## Phase 3: Adaptive System (Weeks 21-32)

*Note: Only proceed if Phase 2 shows significant gap and clear need*

### Milestone 3.1: System Design (Weeks 21-22)

#### 3.1.1 Architecture Selection
Based on Phase 2 findings, choose approach:

- [ ] **Option A: Enhanced Heuristics**
  - If gap is moderate (15-25%)
  - Refine rules with more conditions
  - Add adaptive thresholds

- [ ] **Option B: ML-based (Two-Tier)**
  - If gap is large (>25%) and patterns complex
  - Fast path: Decision tree (distilled)
  - Slow path: RL/learning

- [ ] **Option C: Hybrid**
  - Fast path: Simple rules (common cases)
  - Slow path: ML or lookup (rare cases)

#### 3.1.2 Implementation Plan
- [ ] Define interfaces
- [ ] Design monitoring/control loop
- [ ] Plan integration with DPDK

**Deliverable 3.1:** Detailed design document

---

### Milestone 3.2: Implementation (Weeks 23-27)

#### 3.2.1 Core System
- [ ] Implement monitoring infrastructure
- [ ] Implement decision-making component
- [ ] Implement config application mechanism
- [ ] Safety mechanisms (fallback, validation)

#### 3.2.2 Learning Component (if ML approach)
- [ ] Train initial model on Phase 1+2 data
- [ ] Implement online learning (if applicable)
- [ ] Distillation to fast model (if applicable)

#### 3.2.3 Integration
- [ ] Integrate with DPDK
- [ ] Testing and debugging
- [ ] Performance validation

**Deliverable 3.2:** Working adaptive tuning system

---

### Milestone 3.3: Evaluation (Weeks 28-30)

#### 3.3.1 Performance Evaluation
- [ ] Test on all Phase 1 workloads
- [ ] Test on Phase 2 dynamic scenarios
- [ ] Test on new workloads (generalization)
- [ ] Measure:
  - [ ] Throughput improvement vs baselines
  - [ ] Adaptation speed
  - [ ] Overhead
  - [ ] Stability

#### 3.3.2 Comparison with Baselines
- [ ] Static best config
- [ ] Simple rules (Phase 1)
- [ ] Lookup table (Phase 2)
- [ ] Oracle (upper bound)
- [ ] Adaptive system (ours)

#### 3.3.3 Ablation Studies
- [ ] Which components matter most?
- [ ] Sensitivity to parameters
- [ ] Failure mode analysis

**Deliverable 3.3:** Comprehensive evaluation results

---

### Milestone 3.4: Paper Writing (Weeks 31-32)

#### 3.4.1 Paper Structure (NSDI-style)
- [ ] Abstract
- [ ] Introduction
  - [ ] Motivation: DPDK tuning is important but complex
  - [ ] Challenges: many parameters, dynamic conditions
  - [ ] Our approach: systematic discovery → adaptive solution
- [ ] Background
  - [ ] DPDK overview
  - [ ] Parameter tuning challenges
- [ ] Parameter Characterization (Phase 1)
  - [ ] Methodology
  - [ ] Per-parameter findings (highlight key insights)
  - [ ] Cross-parameter interactions
  - [ ] Simple rules extracted
- [ ] Dynamic Scenarios & Limitations (Phase 2)
  - [ ] Dynamic workload behavior
  - [ ] When static rules fail
  - [ ] Quantified opportunity
- [ ] Adaptive System Design (Phase 3, if applicable)
  - [ ] Architecture
  - [ ] Implementation
  - [ ] Safety mechanisms
- [ ] Evaluation
  - [ ] Experimental setup
  - [ ] Performance results
  - [ ] Comparison with baselines
  - [ ] Ablation studies
- [ ] Related Work
- [ ] Discussion & Limitations
- [ ] Conclusion

#### 3.4.2 Figures & Tables
- [ ] Parameter impact heatmaps
- [ ] Dynamic scenario timelines
- [ ] Performance comparison graphs
- [ ] Baseline comparison table
- [ ] Ablation study results

**Deliverable 3.4:** Draft paper ready for submission

---

## Success Criteria

### Minimum Viable (publishable result):
- [ ] 5+ parameters characterized with clear impact quantified
- [ ] Simple tuning rules derived and validated
- [ ] Dynamic scenarios showing adaptation need
- [ ] Evidence that problem is non-trivial

### Target (strong paper):
- [ ] 8+ parameters characterized
- [ ] Counter-intuitive findings (e.g., cache thrashing effect)
- [ ] Clear failure cases for static approaches
- [ ] Working adaptive system with >25% improvement
- [ ] Generalization across workloads/hardware

### Stretch Goals:
- [ ] Theoretical insights (why certain patterns emerge)
- [ ] Framework applicable beyond DPDK
- [ ] Open-source release with community adoption

---

## Risk Mitigation

### Risk 1: Parameters have little impact
**Mitigation:** We already know txqs_min_inline matters; pick parameters carefully based on documentation/experience

### Risk 2: Static rules sufficient
**Mitigation:** Still publishable as characterization study; shows when complexity NOT needed (also valuable)

### Risk 3: Too many parameters to test
**Mitigation:** Focus on top 5-8 most impactful; depth over breadth

### Risk 4: Hardware access issues
**Mitigation:** Efficient experiment design; batch overnight runs

---

## Resources Needed

### Hardware:
- [ ] 2-node DPDK cluster (node7, node8) - already have
- [ ] Stable access for 6-8 months
- [ ] Backup plan if hardware fails

### Software:
- [ ] Current setup (DPDK, Pktgen, PCM) - already have
- [ ] Python analysis tools - already have
- [ ] ML libraries (if Phase 3 goes ML route) - install later

### Time:
- [ ] ~8 months for full project
- [ ] Can publish after Phase 1+2 if needed (characterization paper)
- [ ] Phase 3 is optional enhancement

---

## Notes & Tracking

### Current Status
- **Completed:**
  - [x] Initial txqs_min_inline exploration (partial)
  - [x] Identified PCIe read bottleneck scenario

- **In Progress:**
  - [ ] Complete txqs_min_inline characterization

- **Next Actions:**
  1. Finish txqs_min_inline experiments (Milestone 1.2)
  2. Document findings
  3. Move to descriptor sizes

### Key Decisions Made
- 2025-10-31: Switched from "big ML plan" to "bottom-up parameter discovery"
  - Rationale: More concrete, incremental, story emerges from data

### Important Findings
- txqs_min_inline=0 helps when cores < 8 and PCIe read limited
- (Add more as discovered)

---

**Last Updated:** 2025-10-31
**Current Phase:** Phase 1 - Parameter Discovery
**Current Milestone:** 1.1 Infrastructure Setup
**Next Milestone:** 1.2 txqs_min_inline Deep Dive
