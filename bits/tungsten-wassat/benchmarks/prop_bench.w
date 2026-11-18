# One solver, one thread, a conflict budget: the CDCL core on an original
# DIMACS input, with no portfolio or specialists around it. Build --release.
# Arguments: input.cnf conflicts [seconds] [raw|light|heavy] [ticks]. With a
# seconds limit the budget is spent in slices of 5,000 conflicts until the
# verdict, the budget (0 = unlimited) or the limit. With a ticks limit
# (millions; seconds 0) the search stops at the first conflict past it,
# which makes "solved within the limit" independent of machine load. `raw`
# (the default) searches the input as written; `light` and `heavy` first
# render it the way the race's preprocessing arms do and configure the
# solver as those arms do. `props` counts dequeued trail literals, the same
# quantity Kissat reports as "propagations"; `ticks` is the work measure of
# wassat_propagate.

use ../lib/solver
use ../lib/preprocess

# Benchmark-only intervention: compare the scan policy in one release binary
# without changing the production policy or any other Kissat-profile choices.
+ PropBenchSolver < Wassat
  -> set_saved_positions(value)
    @pstate[13] = value
    0

-> prop_bench_us
  (ccall("__w_clock") * 1000000).to_i

av = argv()
formula = wassat_parse_cnf_native(read_file(av[0]))
nv = formula["nvars"]
mode = "raw"
mode = av[3] if av.size > 3
t0 = prop_bench_us
s = nil
pre_status = 0
snv = nv
if mode == "raw"
  art = wassat_raw_artifact(formula, nv)
  t0 = prop_bench_us
  s = PropBenchSolver.new(nv, [], WASSAT_PROOF_NONE, 0, true)
  s.load_flat(art)
else
  pre = WassatPreprocess.new(nv, [], WASSAT_PROOF_NONE, formula)
  pre.set_budget(wassat_pre_light_ticks)
  pre.set_heavy_budget(wassat_pre_heavy_ticks, 0)
  pre.force_full_pipeline
  rendered = pre.run_light_flat(formula, false)
  rendered = pre.run_heavy if mode == "heavy" && rendered["status"] == 0
  pre_status = rendered["status"]
  snv = rendered["nvars"]
  if pre_status == 0
    s = PropBenchSolver.new(snv, [], WASSAT_PROOF_NONE, 0, true)
    s.load_flat(rendered)
    if mode == "heavy"
      # PB_CHRONO=0 / PB_SHRINK=0 / PB_TARGET=0 drop one of the three for an
      # ablation; the race's heavy arm sets all of them.
      s.enable_chrono unless env("PB_CHRONO") == "0"
      s.enable_shrink unless env("PB_SHRINK") == "0"
      s.enable_target_stable_only unless env("PB_TARGET") == "0"
s.set_saved_positions(0) if s != nil && env("WASSAT_BENCH_SAVED_POS") == "0"
s.set_saved_positions(1) if s != nil && env("WASSAT_BENCH_SAVED_POS") == "1"
t1 = prop_bench_us
if pre_status != 0
  << "RESULT status=[pre_status] conflicts=0 decisions=0 props=0 load_ms=[(t1 - t0) / 1000] solve_ms=0 props_per_s=0 conflicts_per_s=0 restarts=0 reduces=0 mode=[mode] vars=[snv]"
  exit(0)
budget = av[1].to_i
limit_us = 0
limit_us = av[2].to_i * 1000000 if av.size > 2
tick_limit = 0
tick_limit = av[4].to_i * 1000000 if av.size > 4
s.set_tick_stop(tick_limit) if tick_limit > 0
r = nil
if limit_us == 0
  r = s.solve_budget(budget)
else
  spent = 0
  done = false
  while !done
    slice = 5000
    slice = budget - spent if budget > 0 && budget - spent < slice
    r = s.solve_budget(slice)
    spent += slice
    done = true if r["status"] != 0
    done = true if budget > 0 && spent >= budget
    done = true if prop_bench_us - t1 >= limit_us
t2 = prop_bench_us
# Replay SAT models outside the timed search. Reconstruct eliminated variables
# for prepared kernels before checking every original clause.
if r["status"] == 1
  model = r["model"]
  model = wassat_reconstruct_model(rendered["stack"], model, nv) if mode != "raw"
  raise "benchmark produced an invalid SAT model" unless wassat_model_satisfies?(formula, model)
us = t2 - t1
us = 1 if us < 1
props = r["props"]
<< "RESULT status=[r["status"]] conflicts=[r["conflicts"]] decisions=[r["decisions"]] props=[props] load_ms=[(t1 - t0) / 1000] solve_ms=[us / 1000] props_per_s=[props * 1000000 / us] conflicts_per_s=[r["conflicts"] * 1000000 / us] restarts=[r["restarts"]] reduces=[r["reduces"]] ticks=[r["ticks"]] mode=[mode] vars=[snv] watch_rebuilds=[r["watch_rebuilds"]] watch_relocations=[r["watch_relocations"]] watch_overflows=[r["watch_overflows"]]"
