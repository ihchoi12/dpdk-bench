# DPDK Adaptive Tuning Research Plan

## Project Goal
Build an ML-driven adaptive DPDK tuning system that uses two-tier architecture (fast DT/SE + slow RL) to optimize performance under dynamic conditions.

---

## Phase 1: Characterization Study (Weeks 1-12)

### Milestone 1.1: Infrastructure Setup (Weeks 1-2)

#### 1.1.1 Automated Experiment Framework
- [ ] Extend `run_test.py` to support full config sweep
  - [ ] Add parameter grid: TX/RX desc sizes [128, 256, 512, 1024, 2048]
  - [ ] Add core counts [1, 2, 4, 8, 16]
  - [ ] Add batch size variations if applicable
  - [ ] Implement retry logic for failed experiments
- [ ] Create experiment queue manager
  - [ ] Save/resume capability for long-running experiments
  - [ ] Progress tracking and ETA calculation
  - [ ] Automatic result archival with metadata

#### 1.1.2 Enhanced Monitoring
- [ ] Integrate hardware metrics collection
  - [ ] PCIe bandwidth (read/write) via perf
  - [ ] LLC misses via perf
  - [ ] DRAM bandwidth via PCM
  - [ ] CPU utilization per core
- [ ] Create unified metrics logging
  - [ ] Single CSV output with all metrics
  - [ ] Timestamp synchronization across metrics
  - [ ] Validation checks for data consistency

#### 1.1.3 Workload Generation
- [ ] Implement basic workload patterns
  - [ ] Uniform 64B packets (small packet flood)
  - [ ] Uniform 1500B packets (large packets)
  - [ ] Bursty traffic pattern
  - [ ] Low rate (<1 Mpps)
  - [ ] High rate (>10 Mpps)
- [ ] Add realistic workloads
  - [ ] Mixed packet sizes (distribution from traces)
  - [ ] Request-response patterns (RPC-like)
  - [ ] Video streaming simulation
  - [ ] Key-value store traffic (memcached-like)
  - [ ] Web server traffic (nginx-like)

**Deliverable 1.1:** Automated framework ready to run 1000+ experiments unattended

---

### Milestone 1.2: Data Collection (Weeks 3-6)

#### 1.2.1 Experiment Execution Plan
- [ ] Define experiment matrix
  - [ ] 10-15 workloads × 125 configs = 1,250-1,875 experiments
  - [ ] Each experiment: 3 trials for statistical significance
  - [ ] Total: ~4,000 runs × 3 min = 200 hours (8-9 days)
- [ ] Schedule experiments
  - [ ] Run overnight/weekends
  - [ ] Monitor for failures
  - [ ] Collect logs for debugging

#### 1.2.2 Execute Experiments
- [ ] Run Week 1 batch (25% of workloads)
  - [ ] Quick sanity check on results
  - [ ] Adjust if major issues found
- [ ] Run Week 2 batch (25% of workloads)
- [ ] Run Week 3 batch (25% of workloads)
- [ ] Run Week 4 batch (25% of workloads)

#### 1.2.3 Data Validation
- [ ] Check for missing data points
- [ ] Identify and re-run failed experiments
- [ ] Validate metric ranges (outlier detection)
- [ ] Verify reproducibility (check variance across trials)

**Deliverable 1.2:** Complete dataset with ~4,000 experiment results

---

### Milestone 1.3: Data Analysis (Weeks 7-8)

#### 1.3.1 Performance Landscape Analysis
- [ ] Calculate dynamic range per workload
  - [ ] `ratio = max_perf / min_perf` for each workload
  - [ ] Identify workloads with high sensitivity (ratio > 2x)
  - [ ] Identify workloads with low sensitivity (ratio < 1.3x)
- [ ] Visualize performance heatmaps
  - [ ] 2D heatmaps: (descriptor_size, cores) → performance
  - [ ] 3D surface plots if needed
  - [ ] Per-workload and aggregate views

#### 1.3.2 Optimal Configuration Analysis
- [ ] Find optimal config for each workload
  - [ ] Extract top-3 configs per workload
  - [ ] Analyze diversity: are they all different?
  - [ ] Cluster analysis: do configs group by workload type?
- [ ] Quantify configuration sensitivity
  - [ ] How much does perf drop with sub-optimal config?
  - [ ] What's the penalty for using "wrong" config?

#### 1.3.3 Pattern Discovery
- [ ] Feature correlation analysis
  - [ ] Correlation matrix: metrics vs performance
  - [ ] Identify key metrics (top 5-10)
  - [ ] Look for non-linear relationships
- [ ] Counter-intuitive pattern search
  - [ ] Example: "High LLC miss → small descriptor better"
  - [ ] Document and explain each finding
  - [ ] Validate across multiple workloads
- [ ] Interaction effects
  - [ ] Does descriptor size interact with core count?
  - [ ] Are there sweet spots or cliffs?

**Deliverable 1.3:** Analysis report with visualizations and insights

---

### Milestone 1.4: Simple Baseline Implementation (Weeks 9-10)

#### 1.4.1 Static Best Configuration
- [ ] Find best static config across all workloads
  - [ ] Metric: average performance or worst-case
  - [ ] Test on all workloads
  - [ ] Record performance gap vs optimal

#### 1.4.2 Simple Rule-Based System
- [ ] Design 3-5 simple rules
  - [ ] Based on top metrics (e.g., PCIe BW, LLC miss, pkt rate)
  - [ ] If-else structure
  - [ ] Threshold tuning via grid search
- [ ] Implement in Python/C
- [ ] Evaluate on all workloads
- [ ] Measure: avg performance, worst-case, variance

#### 1.4.3 Lookup Table
- [ ] Create lookup table (10-20 entries)
  - [ ] Key: workload fingerprint (top 3-5 metrics)
  - [ ] Value: best config
  - [ ] Nearest-neighbor matching for unseen workloads
- [ ] Test generalization
  - [ ] Train on 70% workloads
  - [ ] Test on 30% unseen workloads
  - [ ] Measure performance gap

#### 1.4.4 Linear Model
- [ ] Train linear regression
  - [ ] Input: hardware metrics (normalized)
  - [ ] Output: optimal config parameters
- [ ] Train decision tree (depth=5)
  - [ ] Compare with linear model
  - [ ] Measure accuracy and inference time
- [ ] Evaluate both models

**Deliverable 1.4:** 4 baseline implementations with performance comparison

---

### Milestone 1.5: Gap Analysis & Decision (Weeks 11-12)

#### 1.5.1 Quantitative Comparison
- [ ] Create comparison table
  - [ ] Rows: workloads
  - [ ] Columns: Static, Rules, Lookup, Linear, DT-5, Oracle
  - [ ] Metrics: Throughput (Mpps), gap vs optimal (%)
- [ ] Calculate aggregate metrics
  - [ ] Mean gap across workloads
  - [ ] Worst-case gap
  - [ ] Standard deviation
- [ ] Statistical significance testing
  - [ ] T-tests between baselines
  - [ ] Confidence intervals

#### 1.5.2 ML Justification Analysis
- [ ] Compute opportunity score
  - [ ] `opportunity = (oracle - best_baseline) / oracle`
  - [ ] If opportunity > 30% → ML strongly justified
  - [ ] If opportunity 15-30% → ML possibly justified
  - [ ] If opportunity < 15% → ML hard to justify
- [ ] Analyze failure modes of simple baselines
  - [ ] Which workloads do they fail on?
  - [ ] Why do they fail? (hypothesis)
  - [ ] Can rules be fixed easily?

#### 1.5.3 Write Characterization Report
- [ ] Executive summary (1 page)
  - [ ] Key findings
  - [ ] Go/No-go recommendation
  - [ ] Confidence level
- [ ] Detailed analysis (10-15 pages)
  - [ ] Experimental setup
  - [ ] Performance landscape
  - [ ] Baseline comparison
  - [ ] Pattern discovery
  - [ ] Counter-intuitive findings
  - [ ] Conclusion

#### 1.5.4 Decision Point
- [ ] Review report with advisor
- [ ] Make Go/No-go decision
  - [ ] **GO (opportunity >25%)**: Proceed to Phase 2 (ML system)
  - [ ] **MAYBE (15-25%)**: More investigation or pivot to hybrid
  - [ ] **NO-GO (<15%)**: Publish characterization or pivot entirely

**Deliverable 1.5:** Characterization report + Go/No-go decision

---

## Phase 2: ML System Design (Weeks 13-20)

*Note: This phase only proceeds if Phase 1 shows GO decision*

### Milestone 2.1: RL Agent Development (Weeks 13-15)

#### 2.1.1 Environment Setup
- [ ] Define RL environment
  - [ ] State space: hardware metrics (normalized)
  - [ ] Action space: config parameters (discretized)
  - [ ] Reward: throughput or normalized performance
- [ ] Implement gym-like interface
  - [ ] `reset()`: initialize DPDK with random config
  - [ ] `step(action)`: apply config, measure performance
  - [ ] `observe()`: collect hardware metrics
- [ ] Create training loop
  - [ ] Episode length: 100-1000 steps
  - [ ] Workload changes every N steps

#### 2.1.2 RL Algorithm Selection
- [ ] Implement baseline RL algorithms
  - [ ] Q-learning or DQN
  - [ ] PPO (Proximal Policy Optimization)
  - [ ] DDPG or TD3 (if continuous actions)
- [ ] Train on collected dataset
  - [ ] Offline RL or online fine-tuning
  - [ ] Hyperparameter tuning
- [ ] Evaluate convergence
  - [ ] Learning curves
  - [ ] Sample efficiency
  - [ ] Final performance vs oracle

#### 2.1.3 RL Agent Validation
- [ ] Test on training workloads
  - [ ] Should match or exceed best baseline
- [ ] Test on unseen workloads
  - [ ] Generalization capability
  - [ ] Zero-shot performance
- [ ] Measure inference time
  - [ ] Should be ~1-10 ms (too slow for data plane)

**Deliverable 2.1:** Trained RL agent with >30% improvement over best baseline

---

### Milestone 2.2: Knowledge Distillation (Weeks 16-17)

#### 2.2.1 Distillation Method Selection
- [ ] Implement distillation approaches
  - [ ] Imitation learning (behavioral cloning)
  - [ ] VIPER-style iterative distillation
  - [ ] Direct tree extraction from Q-values
- [ ] Compare distillation quality
  - [ ] Accuracy: how well DT matches RL policy
  - [ ] Compactness: tree depth, node count
  - [ ] Inference speed: measure latency

#### 2.2.2 Decision Tree Optimization
- [ ] Tune tree hyperparameters
  - [ ] Max depth: try [5, 10, 15, 20]
  - [ ] Min samples per leaf
  - [ ] Feature selection (top-K metrics)
- [ ] Measure accuracy-speed trade-off
  - [ ] Accuracy vs oracle
  - [ ] Inference time (target: <100 ns)
- [ ] Generate C code from tree
  - [ ] Compile to inline function
  - [ ] Benchmark in DPDK data plane

#### 2.2.3 Symbolic Expression (Optional)
- [ ] Try symbolic regression
  - [ ] Tools: gplearn, PySR, or eureqa
  - [ ] Goal: compact expression (10-20 terms)
- [ ] Compare with DT
  - [ ] Accuracy
  - [ ] Inference speed
  - [ ] Interpretability

**Deliverable 2.2:** Distilled DT/SE with <100 ns inference, >80% RL accuracy

---

### Milestone 2.3: Two-Tier Architecture (Weeks 18-20)

#### 2.3.1 Fast Path Implementation
- [ ] Integrate DT into DPDK
  - [ ] C implementation of decision tree
  - [ ] Inline in packet processing loop
  - [ ] Measure overhead (should be negligible)
- [ ] Implement novelty detection
  - [ ] Confidence threshold on DT predictions
  - [ ] Distance metric in state space
  - [ ] Trigger: low confidence → fallback

#### 2.3.2 Slow Path Implementation
- [ ] Background RL training thread
  - [ ] Collect metrics in circular buffer
  - [ ] Periodic training (every N minutes)
  - [ ] Checkpointing and logging
- [ ] Distillation pipeline
  - [ ] Trigger: after X training episodes
  - [ ] Generate new DT from updated RL
  - [ ] Validate new DT quality

#### 2.3.3 Safe Update Protocol
- [ ] Implement atomic DT swap
  - [ ] Lock-free data structure or RCU-like mechanism
  - [ ] No disruption to data plane
- [ ] Validation before deployment
  - [ ] Test new DT on shadow traffic
  - [ ] Rollback if performance degrades
- [ ] Fallback to safe default
  - [ ] Pre-characterized conservative config
  - [ ] Used during learning or failures

**Deliverable 2.3:** Working two-tier system with online learning

---

## Phase 3: Evaluation (Weeks 21-28)

### Milestone 3.1: Microbenchmarks (Weeks 21-22)

#### 3.1.1 Inference Latency
- [ ] Measure DT inference time
  - [ ] Median, p99, p999
  - [ ] Variance across different inputs
- [ ] Compare with baselines
  - [ ] Static: 0 ns
  - [ ] Lookup table: ~50 ns
  - [ ] Linear model: ~20 ns
  - [ ] Full RL: ~5 ms
  - [ ] Our DT: target <100 ns

#### 3.1.2 Decision Quality
- [ ] Measure accuracy
  - [ ] % of decisions matching oracle
  - [ ] % within 5% of optimal performance
- [ ] Test on known workloads
- [ ] Test on unseen workloads

#### 3.1.3 Overhead Analysis
- [ ] CPU overhead
  - [ ] % CPU for monitoring
  - [ ] % CPU for background training
  - [ ] Total system overhead
- [ ] Memory overhead
  - [ ] DT size
  - [ ] Monitoring buffer size
  - [ ] Training data storage

**Deliverable 3.1:** Microbenchmark results showing <100 ns inference, <1% overhead

---

### Milestone 3.2: End-to-End Evaluation (Weeks 23-25)

#### 3.2.1 Static Workload Performance
- [ ] Test on all workloads from Phase 1
  - [ ] Throughput (Mpps)
  - [ ] Latency (p50, p99, p999)
  - [ ] CPU efficiency
- [ ] Compare with all baselines
  - [ ] Static best
  - [ ] Simple rules
  - [ ] Lookup table
  - [ ] Linear model
  - [ ] Oracle (upper bound)
- [ ] Statistical analysis
  - [ ] Mean improvement
  - [ ] Worst-case performance
  - [ ] Confidence intervals

#### 3.2.2 Dynamic Workload Adaptation
- [ ] Test workload transitions
  - [ ] Switch between workloads every 5-10 minutes
  - [ ] Measure adaptation time
  - [ ] Measure performance during learning
- [ ] Test novel workloads
  - [ ] Introduce completely new workload
  - [ ] Measure zero-shot performance
  - [ ] Measure time to converge
- [ ] Safety validation
  - [ ] Does fallback work?
  - [ ] Performance never below baseline?

#### 3.2.3 Long-Running Stability
- [ ] Run 24-hour test
  - [ ] Multiple workload changes
  - [ ] Monitor for memory leaks
  - [ ] Monitor for performance drift
- [ ] Measure cumulative regret
  - [ ] Total performance loss vs oracle
  - [ ] Amortized adaptation cost

**Deliverable 3.2:** End-to-end results showing >30% improvement, <5min adaptation

---

### Milestone 3.3: Ablation Studies (Weeks 26-27)

#### 3.3.1 Component Analysis
- [ ] Test without novelty detection
  - [ ] How often does DT fail?
  - [ ] Performance impact
- [ ] Test without background learning
  - [ ] Static DT (no updates)
  - [ ] Performance on shifting workloads
- [ ] Test with different distillation frequencies
  - [ ] Every 1 min vs 10 min vs 1 hour
  - [ ] Trade-off: freshness vs overhead

#### 3.3.2 Hyperparameter Sensitivity
- [ ] Vary DT depth [5, 10, 15, 20]
  - [ ] Accuracy vs speed trade-off
- [ ] Vary confidence threshold [0.7, 0.8, 0.9, 0.95]
  - [ ] False positive/negative rates
- [ ] Vary training frequency
  - [ ] Impact on adaptation speed

#### 3.3.3 Generalization Testing
- [ ] Test on different hardware
  - [ ] Different NIC (if available)
  - [ ] Different CPU generation
  - [ ] Transfer learning capability
- [ ] Test on different DPDK versions
- [ ] Test with interference (co-located apps)

**Deliverable 3.3:** Ablation study results + sensitivity analysis

---

### Milestone 3.4: Write Paper (Week 28)

#### 3.4.1 Paper Structure
- [ ] Abstract (200 words)
  - [ ] Problem, approach, key results
- [ ] Introduction (2 pages)
  - [ ] Motivation
  - [ ] Challenges
  - [ ] Our approach
  - [ ] Contributions
- [ ] Background (1.5 pages)
  - [ ] DPDK overview
  - [ ] Parameter tuning challenges
  - [ ] Why existing approaches fail
- [ ] Design (3 pages)
  - [ ] Two-tier architecture
  - [ ] Fast path (DT/SE)
  - [ ] Slow path (RL + distillation)
  - [ ] Safety mechanisms
- [ ] Implementation (2 pages)
  - [ ] DPDK integration
  - [ ] RL training details
  - [ ] Distillation method
- [ ] Evaluation (4 pages)
  - [ ] Experimental setup
  - [ ] Microbenchmarks
  - [ ] End-to-end results
  - [ ] Comparison with baselines
  - [ ] Ablation studies
- [ ] Related Work (1.5 pages)
- [ ] Discussion & Future Work (1 page)
- [ ] Conclusion (0.5 pages)

#### 3.4.2 Figures & Tables
- [ ] Architecture diagram
- [ ] Performance comparison graphs
- [ ] Adaptation timeline
- [ ] Baseline comparison table
- [ ] Overhead breakdown

**Deliverable 3.4:** Draft paper ready for advisor review

---

## Phase 4: Submission & Revision (Weeks 29-32)

### Milestone 4.1: Internal Review
- [ ] Advisor review
- [ ] Lab meeting presentation
- [ ] Incorporate feedback
- [ ] Polish writing

### Milestone 4.2: NSDI Submission
- [ ] Check submission deadline
- [ ] Prepare artifacts (code, data)
- [ ] Write cover letter
- [ ] Submit before deadline

### Milestone 4.3: Rebuttal (if needed)
- [ ] Read reviews carefully
- [ ] Prepare rebuttal document
- [ ] Run additional experiments if needed
- [ ] Submit rebuttal

---

## Success Criteria

### Minimum Viable (for NSDI submission):
- [ ] Characterization study complete (50+ workloads)
- [ ] ML improvement >25% over best simple baseline
- [ ] DT inference <500 ns
- [ ] End-to-end system working
- [ ] Adaptation time <10 minutes

### Target (for Strong Accept):
- [ ] ML improvement >35% over best simple baseline
- [ ] DT inference <100 ns
- [ ] Adaptation time <5 minutes
- [ ] Counter-intuitive patterns discovered and explained
- [ ] Generalization across hardware platforms

### Stretch Goals:
- [ ] Theoretical convergence guarantee
- [ ] Formal proof of safety
- [ ] Open-source release
- [ ] Industry adoption interest

---

## Risk Mitigation

### Risk 1: Simple baseline too strong
**Mitigation:** Pivot to characterization paper or hybrid approach

### Risk 2: Distillation quality poor
**Mitigation:** Use hybrid (DT for common cases, fallback to RL)

### Risk 3: Time overrun
**Mitigation:** Parallelize experiments, reduce scope if needed

### Risk 4: Hardware unavailable
**Mitigation:** Use simulation or cloud resources

---

## Resources Needed

### Compute:
- [ ] 2-node DPDK cluster (node7, node8)
- [ ] 24/7 access for 3 months
- [ ] Backup hardware (in case of failures)

### Software:
- [ ] Python ML libraries (sklearn, pytorch, stable-baselines3)
- [ ] Distillation tools (custom implementation)
- [ ] Visualization (matplotlib, seaborn)

### Human:
- [ ] Weekly advisor meetings
- [ ] Feedback from systems researchers
- [ ] Writing assistance (optional)

---

## Notes

- Update this plan as we progress
- Check off items as completed
- Add notes/findings under each item
- Adjust timeline if needed (be realistic!)
- Document all decisions and rationale

---

**Last Updated:** 2025-10-31
**Status:** Phase 1 ready to start
**Next Action:** Begin Milestone 1.1.1 (Automated Experiment Framework)
