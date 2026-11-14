# One solver, one thread, a conflict budget: the propagation rate of the CDCL
# core on an original DIMACS input, with no portfolio, preprocessing arms or
# specialists around it. Build --release. Arguments: input.cnf conflicts
# [seconds]. With a seconds limit the budget is spent in slices of 20,000
# conflicts until the verdict, the budget (0 = unlimited) or the limit.
# `props` counts dequeued trail literals, the same quantity Kissat reports as
# "propagations".

use ../lib/solver
use ../lib/preprocess

-> prop_bench_us
  (ccall("__w_clock") * 1000000).to_i

av = argv()
formula = wassat_parse_cnf_native(read_file(av[0]))
nv = formula["nvars"]
art = wassat_raw_artifact(formula, nv)
t0 = prop_bench_us
s = Wassat.from_flat(nv, art, WASSAT_PROOF_NONE)
t1 = prop_bench_us
budget = av[1].to_i
limit_us = 0
limit_us = av[2].to_i * 1000000 if av.size > 2
r = nil
if limit_us == 0
  r = s.solve_budget(budget)
else
  spent = 0
  done = false
  while !done
    slice = 20000
    slice = budget - spent if budget > 0 && budget - spent < slice
    r = s.solve_budget(slice)
    spent += slice
    done = true if r["status"] != 0
    done = true if budget > 0 && spent >= budget
    done = true if prop_bench_us - t1 >= limit_us
t2 = prop_bench_us
us = t2 - t1
us = 1 if us < 1
props = r["props"]
<< "RESULT status=[r["status"]] conflicts=[r["conflicts"]] decisions=[r["decisions"]] props=[props] load_ms=[(t1 - t0) / 1000] solve_ms=[us / 1000] props_per_s=[props * 1000000 / us] conflicts_per_s=[r["conflicts"] * 1000000 / us] restarts=[r["restarts"]] reduces=[r["reduces"]]"
