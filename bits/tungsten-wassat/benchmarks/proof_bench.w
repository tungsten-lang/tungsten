# One raw solver with proof formatting and sink flush included in timing.
# Build --release. Arguments: input.cnf conflicts wrat|dual|drat output-prefix
# [native|text]. `text` restores the former WRAT sink path in the same binary;
# DRAT-only already used byte formatting and remains unchanged as a control.
# Bounded UNKNOWN runs retain partial streams for byte comparison only;
# they are not refutations. Production CLI publication checks still apply.
use ../lib/solver

+ ProofBenchSolver < Wassat
  -> text_sinks
    if @proof_mode == WASSAT_PROOF_WRAT
      @wbytes = nil
      @dbytes = nil
    0

av = argv()
f = wassat_parse_cnf_native(read_file(av[0]))
clauses = wassat_formula_clauses(f)
kind = av[2]
raise "expected wrat, dual or drat" unless kind == "wrat" || kind == "dual" || kind == "drat"
mode = kind == "drat" ? WASSAT_PROOF_DRAT : WASSAT_PROOF_WRAT
s = ProofBenchSolver.new(f["nvars"], clauses, mode, 0)
wp = nil
dp = nil
wp = av[3] + ".wrat" unless kind == "drat"
dp = av[3] + ".drat" unless kind == "wrat"
write_file(wp, "") unless wp == nil
write_file(dp, "") unless dp == nil
s.enable_dual_drat if kind == "dual"
s.stream_proofs(wp, dp)
s.text_sinks if av.size > 4 && av[4] == "text"
t0 = ccall("__w_clock")
r = s.solve_budget(av[1].to_i)
s.flush_proof_sinks
us = ((ccall("__w_clock") - t0) * 1000000).to_i
if r["status"] == 1
  raise "invalid SAT model" unless wassat_model_satisfies?(f, r["model"])
<< "RESULT status=[r["status"]] conflicts=[r["conflicts"]] decisions=[r["decisions"]] props=[r["props"]] ticks=[r["ticks"]] restarts=[r["restarts"]] reduces=[r["reduces"]] solve_us=[us]"
