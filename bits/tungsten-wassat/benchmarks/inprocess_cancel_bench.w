# Maintenance overhead and cooperative-stop latency on an original DIMACS input.
# Build --release. Arguments: input.cnf pass-mask delay-ms arms.
# delay-ms=-1 measures uninterrupted work; >=0 publishes a synthetic winning
# status after the start barrier. Reported tail_us ends at maintenance return,
# before checksum collection; this is not a full-solve benchmark.
# Example: bench qwh.cnf 15 5 3
# Workers allocate no scratch; all preparation occurs before Thread.new.

use ../lib/solver
use ../lib/preprocess

-> cancel_now_us
  (ccall("__w_clock") * 1000000).to_i

+ CancelBench < Wassat
  -> setup(mask)
    @inprocess_passes = mask
    @conflicts = 1
    @inp_props_at = @pstate[4] - 400000000
    @lucky_pending = false
    @use_walk = false
    self.prepare_inprocessing
    self.enable_fixed_caps
    0

  -> maintenance(stage)
    if stage == 1
      self.probe_round(20000000)
    elsif stage == 2
      self.vivify_round(@ncl, true, 20000000)
    elsif stage == 4
      self.run_subsume(1, 20000000)
      self.clean_root_clauses
    elsif stage == 8
      self.substitute_equivalences
      self.clean_root_clauses
    else
      self.inprocess_round
    0

  # TODO: investigate the installed compiler's explicit i64 return conversion:
  # annotating this zero-argument helper yielded a boxed value in results[].
  # Leave its inferred return here so the diagnostic prints the numeric digest.
  -> fingerprint
    h = 7 ## i64
    i = 0
    while i < @ncl
      h = ((h * 1000003) ^ @alive[i] ^ @clbd[i] ^ @cmeta[2 * i + 1]) & 2147483647
      if @alive[i] == 1
        j = 0
        while j < @cmeta[2 * i + 1]
          h = ((h * 1000003) ^ @arena[@cmeta[2 * i] + j]) & 2147483647
          j += 1
      i += 1
    i = 1
    while i <= @nvars
      h = ((h * 1000003) ^ @assign[i] ^ @phase[i]) & 2147483647
      i += 1
    h

  -> counters(out, base)
    out[base] = @pstate[4]
    out[base + 1] = @inp_failed
    out[base + 2] = @inp_lifted
    out[base + 3] = @inp_subsumed
    out[base + 4] = @inp_strengthened
    out[base + 5] = @nsubst
    out[base + 6] = @wp_state[3]
    out[base + 7] = @dlevel
    0

  -> run_worker(stage, barrier, results, wi)
    z = ccall("__w_arr_store_rel", barrier, wi + 1, 1)
    while ccall("__w_arr_load_acq", barrier, 0) == 0
      z = 0
    started = cancel_now_us
    self.maintenance(stage)
    ended = cancel_now_us
    results[wi * 16] = started
    results[wi * 16 + 1] = ended
    self.counters(results, wi * 16 + 3)
    results[wi * 16 + 2] = self.fingerprint
    0

av = argv()
formula = wassat_parse_cnf_native(read_file(av[0]))
nv = formula["nvars"]
art = wassat_raw_artifact(formula, nv)
stage = av[1].to_i
delay = av[2].to_i
count = av[3].to_i
solvers = []
stop = i64[4]
barrier = i64[count + 2]
results = i64[count * 16]
i = 0
while i < count
  s = CancelBench.new(nv, [], 0, 0, true)
  s.load_flat(art)
  s.setup(stage)
  s.set_stop_cell(stop)
  solvers.push(s)
  i += 1
handles = []
i = 0
while i < count
  s = solvers[i]
  wi = i
  h = Thread.new -> s.run_worker(stage, barrier, results, wi)
  handles.push(h)
  i += 1
ready = false
while !ready
  ready = true
  i = 0
  while i < count
    ready = false if ccall("__w_arr_load_acq", barrier, i + 1) == 0
    i += 1
z = ccall("__w_arr_store_rel", barrier, 0, 1)
published = 0 ## i64
if delay >= 0
  sleep(delay / 1000.0)
  published = cancel_now_us
  z = wassat_stop_publish(stop, 1)
handles.each -> (h)
  z = h.join
joined = cancel_now_us
i = 0
while i < count
  b = i * 16
  us = results[b + 1] - results[b]
  tail = published > 0 ? results[b + 1] - published : -1
  << "RESULT arm=[i] work_us=[us] tail_us=[tail] hash=[results[b + 2]] props=[results[b + 3]] failed=[results[b + 4]] lifted=[results[b + 5]] subsumed=[results[b + 6]] strengthened=[results[b + 7]] subst=[results[b + 8]] rebuilds=[results[b + 9]] level=[results[b + 10]]"
  i += 1
