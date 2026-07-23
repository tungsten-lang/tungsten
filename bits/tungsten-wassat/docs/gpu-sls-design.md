# E3: GPU-parallel SLS — design

2026-07-22. Hard gate satisfied first: the CPU engine passed the Phase 2
statistical gate (uf250 100/100 on first seeds, 4 bmc kernels, 0 invalid
models), so it now serves as the correctness oracle for the GPU version.

## Shape: many simple walkers, not one clever one

The CPU engine (CCAnr-family) is one sophisticated walker: configuration
checking, clause weighting, a goodvar stack — all serially dependent state.
None of that parallelizes cleanly, and warp divergence would eat the
sophistication. The GPU design is the opposite trade, standard for GPU SLS:
**hundreds of independent WalkSAT/SKC walkers**, one per thread, each with
its own assignment, clause state, and PRNG stream over a shared read-only
formula. The CPU walker stays the quality engine; the GPU buys breadth
(seed diversity) per watt.

Divergence from the CPU algorithm is deliberate and documented: walkers use
WalkSAT/SKC (random unsatisfied clause; with probability p a random member,
else the minimum-break member) with per-walker true-count + critical-var
bookkeeping — no scores, no weights, no CC. Correctness never depends on
the heuristic: every model is verified against the original formula.

## Kernels

Two `@gpu fn` kernels, MSL emitted by the compiler as the build's sidecar
(`bin/wassat.metal`), compiled at runtime via `metal_compile_source`:

- `wassat_sls_gpu_init` — per-walker seeded random assignment (xorshift
  from `mix(seed, walker_id)`), per-walker true-literal counts, critical
  variables, and the unsatisfied-clause list. Device-side so init is
  O(formula) per walker in parallel, not O(walkers x formula) on the host.
- `wassat_sls_gpu_walk` — one bounded CHUNK of flips per walker per
  dispatch. GPU kernels must terminate; unbounded search lives on the host
  as a dispatch loop. Inside a chunk each walker: picks a random
  unsatisfied clause from its list, chooses noise-or-min-break, flips, and
  incrementally maintains satc/crit/unsat-list exactly like the CPU engine
  minus scores. Every 256 flips it polls the shared `found` flag and
  retires early if another walker won.

## Termination and model extraction

`ctrl[0]` is the found flag, `ctrl[1]` the winning walker id. A walker
reaching zero unsatisfied clauses writes both (plain stores; the race is
benign — any winner is a winner, and the host re-checks `uc[wid] == 0` and
then verifies the extracted assignment against the ORIGINAL formula before
reporting, the same output-integrity bar as every other engine). The host
dispatch loop: init once, then walk-chunks until found or the flip budget
is exhausted; between dispatches it reads `ctrl` (buffers are unified
memory; dispatch is synchronous).

## Memory layout

Formula buffers (shared, read-only, i32): literal arena + clause offsets +
lengths, intrusive occurrence lists. Per-walker buffers partitioned by
walker id: assignment (nvars+1), satc (ncl), crit (ncl), unsat list + slots
(ncl each), rng (i64), unsat count. Footprint ~ (nvars + 4*ncl) * 4B *
walkers: uf250 at 256 walkers ~ 4.6 MB; preprocessed bmc kernels less.
Instances are fed through the same `--pre` path as the CPU engine
(preprocessed kernel in, reconstruction + verification after) — the
structured shell that stalls local search is stripped before the GPU sees
the formula.

## Determinism

Deterministic per (seed, walkers, chunk size): fixed per-walker streams,
fixed dispatch schedule. The WINNER may vary across GPU schedulers only in
who writes `ctrl` first when two walkers finish in the same chunk; the
reported model is always re-verified, so scheduler nondeterminism can
affect which valid model is printed, never validity.

## Gate (differential vs the CPU oracle)

`benchmarks/sls_gpu_gate.py`: on a fixed instance sample (uf250 subset +
the bmc kernels the CPU gate solved), the GPU engine must return models on
the instances the CPU engine solves, and every model must validate against
the original formula in the harness. Trajectories are not compared —
different algorithms — only satisfiability capability and model validity.

## Out of scope (recorded)

Cross-walker communication (sharing best assignments), device-side
restarts with weight carryover, and multi-GPU are future work; the CUDA
sidecar (`TUNGSTEN_GPU_DIALECTS=cuda`) is emitted but untested here.
