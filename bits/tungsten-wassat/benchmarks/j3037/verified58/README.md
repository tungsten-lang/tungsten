# Checking j3037_9_rggt_bm1 at 58 slots

Run `python3 verify.py` in the extracted directory. Python's standard library and a C++17 compiler are sufficient. The final verdict requires every branch to pass. Set `CXX` to select the compiler. The script regenerates two small clause lists in `replay/`.

## Why a CNF model would give a schedule

The checker reads the original DIMACS. Each real job has an exactly-one mode triple and a monotone chain of start thresholds. The first true threshold determines the start, including the boundary case in which every threshold is false. The checker verifies each clause that forces a job's chosen mode to be active in every occupied slot. A reverse-unit-propagation check establishes the boundary and precedence clauses for all starts and modes.

At any slot, running jobs must be pairwise incomparable in the precedence order. For every minimal resource-overloaded set of such jobs and modes, the checker either forces a negative root unit to be false by Horn propagation or independently refutes the simultaneous activity literals by unit propagation. For the two project-wide budgets, it constructs ternary decision diagrams over the jobs' mode selections from the input's Horn clauses. Every assignment that exceeds a budget forces a root the input forbids. Together these checks prove the direction needed for refutation. They do not require reconstructing a CNF model from a schedule.

## Why the event proof covers every schedule

All starts and durations are integral. Consider a feasible schedule minimizing the sum of starts. A job starting at a positive time with no simultaneous completion could move one slot earlier. Its predecessors have already finished and the jobs occupying that previous slot still occupy the start slot. Resource capacities therefore allow the move. Thus a feasible schedule has a representative starting jobs only at zero and at completion events.

At each such event the verifier enumerates every legal subset and mode choice, including starting nothing while other jobs run. It advances to the earliest outstanding completion. Once every job has been placed, the checker rejects the refutation. A branch can close in three ways.

- Earliest finishes exceed latest finishes along the precedence graph.
- A prior fully refuted event has exactly the same unstarted jobs and running jobs with identical modes and remaining durations. Its event time and consumed budgets are no greater. A feasible continuation here could be shifted to that earlier event.
- Integer prices show that unfinished work exceeds remaining capacity. The checker enumerates every renewable-feasible antichain pattern and computes the maximum sum of prices per slot. A precedence price charges a successor that starts by a threshold and credits its predecessor for finishing by the same threshold. The net charge on a feasible schedule is nonpositive. At an event, occupied slots before the event are known exactly and their price is deducted from the job total. For unstarted jobs the checker minimizes work over admissible starts and modes. Nonnegative multipliers for the two nonrenewable budgets give a lower bound on work for any feasible completion. A strict excess over the sum of the remaining slot maxima is a contradiction.

The ternary mode branches must be pairwise disjoint and their sizes must sum to all possible mode vectors. A trace gives one instruction per event-tree node. It directs the independent verifier to expand, check a timing contradiction, look up a dominated state, or validate a specific price profile. The verifier rejects an incomplete trace, an unused suffix, a false pruning claim or a feasible schedule. All price calculations used during replay are integral. The package includes the separate 59-slot schedule and checks its precedences, resources and makespan.
