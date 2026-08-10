# Portfolio coordinator (--proof half): a process race.
#
# One wassat worker process per arm over the SHARED preprocessed artifact;
# first decisive answer wins; losers are killed by process group. Processes,
# not threads, because in proof mode isolation and kill-ability must be OS
# guarantees, not protocols — there is no clause sharing here by design
# (finding 3A), so the only shared state is the read-only artifact on disk.
#
# The COORDINATOR owns the certificate. Preprocessing runs once; the
# artifact written to the race directory is the reduced formula as DIMACS,
# the global-proof-id table (line k = the certificate id of reduced clause
# k), and the coordinator keeps the elimination stack and proof prefix in
# memory. Workers solve the reduced formula with seeded ids, so their hint
# chains already cite global ids; on UNSAT the coordinator splices
# prefix + winner proof and the result verifies against the ORIGINAL
# formula's checker. On SAT the winner's model walks the elimination stack
# and must satisfy the original formula before anything is reported.
#
# Workers write their proof to a temp path and RENAME it into place after
# printing the verdict — a killed loser can never leave a plausible partial
# certificate at the expected path.
#
# Arm-failure policy (finding 5A): a dead or wedged arm is logged with its
# exit status and marked out, never respawned; zero live CDCL arms in proof
# mode is a loud fatal error, never a hang.

use atomic_stop
use ../../../core/bit_ops

WASSAT_ARM_MARATHON = 0        # rare restarts, saved phases (the default core)
WASSAT_ARM_GARDEN = 1          # randomized initial phases (diversity)
WASSAT_ARM_SLS = 2             # local search, models only

+ WassatPortfolio
  -> new(@input_path, @race_dir, @arms_spec, @timeout_ms)
    @procs = []                # arm index -> Process or nil
    @arm_kind = []
    @arm_label = []
    @out_paths = []
    @proof_paths = []
    @reduced_path = nil
    @gids_path = nil
    @proof_tmp_output = nil

  # Run the race. Returns {"verdict", "model", "proof_path", "winner",
  # "arms"}; raises on portfolio degradation or an unverifiable answer.
  -> run(proof_out)
    cnf_text = read_file(@input_path)
    raise "cannot read input formula '[@input_path]'" if cnf_text == nil
    wassat_clear_output(proof_out, @input_path, "portfolio proof")
    formula = wassat_parse_cnf(cnf_text)
    proof_tmp_out = wassat_reserve_output(proof_out, @input_path, "portfolio proof")
    @proof_tmp_output = proof_tmp_out
    portfolio_started = ccall("__w_clock_ms")

    # preprocess ONCE; the artifact is what every arm consumes
    # wassat_parse_cnf above is the BOXED parser -- no flat mirrors exist here.
    pre = WassatPreprocess.new(formula["nvars"], formula["clauses"], WASSAT_PROOF_WRAT, nil)
    art = pre.run

    if art["status"] == -1
      # refuted before any arm spawns; the prefix is the certificate
      wtext = "wrat 1\n" + art["wrat"].join("\n") + "\n"
      raise "proof write failed at '[proof_tmp_out]'" unless write_file(proof_tmp_out, wtext)
      wassat_publish_output(proof_tmp_out, proof_out, "portfolio proof")
      return { "verdict": "UNSAT", "model": [], "proof_path": proof_out,
               "winner": "preprocess", "arms": [] }

    if @timeout_ms > 0 && ccall("__w_clock_ms") - portfolio_started >= @timeout_ms
      wassat_discard_output(proof_tmp_out, proof_out)
      return { "verdict": "UNKNOWN", "model": [], "proof_path": nil,
               "winner": "deadline",
               "arms": ["deadline reached during preprocessing after [@timeout_ms]ms"] }

    reduced_path = @race_dir + "/reduced.cnf"
    gids_path = @race_dir + "/gids.txt"
    @reduced_path = reduced_path
    @gids_path = gids_path
    self.write_artifact(formula["nvars"], art, reduced_path, gids_path)

    # spawn one worker per arm, each in its own process group
    self_exe = wassat_own_binary
    i = 0
    while i < @arms_spec.size
      spec = @arms_spec[i]
      kind = spec["kind"]
      label = spec["label"]
      out_path = @race_dir + "/arm[i].out"
      proof_path = @race_dir + "/arm[i].wrat"
      argv = [self_exe, "--worker", reduced_path, "--gids", gids_path,
              "--status", out_path]
      if kind == WASSAT_ARM_SLS
        argv.push("--arm")
        argv.push("sls")
        argv.push("--seed")
        argv.push("[spec["seed"]]")
      elsif kind == WASSAT_ARM_GARDEN
        argv.push("--arm")
        argv.push("garden")
        argv.push("--seed")
        argv.push("[spec["seed"]]")
        argv.push("--proof-tmp")
        argv.push(proof_path)
      else
        argv.push("--arm")
        argv.push("marathon")
        argv.push("--proof-tmp")
        argv.push(proof_path)
      @procs.push(Process.spawn(argv))
      @arm_kind.push(kind)
      @arm_label.push(label)
      @out_paths.push(out_path)
      @proof_paths.push(proof_path)
      i += 1

    # poll until a decisive arm finishes; losers die by group
    winner = -1
    verdict = ""
    live_cdcl = 0
    @arm_kind.each -> (k)
      live_cdcl += 1 unless k == WASSAT_ARM_SLS
    arms_report = []
    race_started = portfolio_started
    timed_out = false
    while winner < 0
      done_any = false
      if @timeout_ms > 0 && ccall("__w_clock_ms") - race_started >= @timeout_ms
        timed_out = true
        arms_report.push("deadline reached after [@timeout_ms]ms")
        winner = 0 - 2
      else
        i = 0
        while i < @procs.size && winner < 0
          p = @procs[i]
          unless p == nil
            rc = p.poll
            unless rc == nil
              done_any = true
              @procs[i] = nil
              if rc == 10 || rc == 20
                winner = i
                verdict = rc == 10 ? "SAT" : "UNSAT"
              else
                # arm died without answering: log, mark out, never respawn
                live_cdcl -= 1 unless @arm_kind[i] == WASSAT_ARM_SLS
                arms_report.push("[@arm_label[i]] failed rc=[rc]")
                raise "portfolio degraded: no prover arms remain" if live_cdcl == 0
          i += 1
      z = ccall("__w_sleep_ms", 20) unless done_any || winner >= 0

    # kill the losers (TERM, then KILL for anything stubborn); all status
    # goes through the Process wrapper so its exit-code cache stays coherent
    i = 0
    while i < @procs.size
      p = @procs[i]
      unless p == nil
        z = p.kill
        rc = p.poll
        if rc == nil
          z = ccall("__w_sleep_ms", 50)
          rc = p.poll
          if rc == nil
            z = p.kill(9)
            rc = p.wait
      i += 1

    if timed_out
      wassat_discard_output(proof_tmp_out, proof_out)
      return { "verdict": "UNKNOWN", "model": [], "proof_path": nil,
               "winner": "deadline", "arms": arms_report }

    win_label = @arm_label[winner]
    arms_report.push("[win_label] WON [verdict]")

    if verdict == "SAT"
      wassat_discard_output(proof_tmp_out, proof_out)
      # reconstruct through the elimination stack; verify vs the ORIGINAL
      model_line = read_file(@out_paths[winner])
      raise "winning arm left no status file" if model_line == nil
      reduced_model = []
      wassat_tokenize(model_line).each -> (t)
        v = t.to_i
        reduced_model.push(v) unless v == 0 || t == "0"
      model = wassat_reconstruct_model(art["stack"], reduced_model, formula["nvars"])
      unless wassat_model_satisfies?(formula, model)
        raise "internal error: winning arm's model does not satisfy the original formula"
      { "verdict": "SAT", "model": model, "proof_path": nil,
        "winner": win_label, "arms": arms_report }
    else
      # Stream-splice: preprocessing prefix + the winner's search proof.
      # The worker proof can be arbitrarily large and is never boxed here.
      prefix = "wrat 1\n"
      prefix = prefix + art["wrat"].join("\n") + "\n" unless art["wrat"].empty?
      raise "proof write failed at '[proof_tmp_out]'" unless write_file(proof_tmp_out, prefix)
      raise "winning arm left no proof" unless ccall("__w_append_file_to", proof_tmp_out, @proof_paths[winner])
      wassat_publish_output(proof_tmp_out, proof_out, "portfolio proof")
      { "verdict": "UNSAT", "model": [], "proof_path": proof_out,
        "winner": win_label, "arms": arms_report }

  -> cleanup
    @procs.each -> (proc)
      unless proc == nil
        rc = proc.poll
        if rc == nil
          z = proc.kill
          z = ccall("__w_sleep_ms", 20)
          rc = proc.poll
          z = proc.kill(9) if rc == nil
          rc = proc.wait if rc == nil
    @out_paths.each -> (path)
      z = ccall("__w_unlink", path)
    @proof_paths.each -> (path)
      z = ccall("__w_unlink", path)
      z = ccall("__w_unlink", path + ".tmp")
    z = ccall("__w_unlink", @reduced_path) unless @reduced_path == nil
    z = ccall("__w_unlink", @gids_path) unless @gids_path == nil
    z = ccall("__w_unlink", @proof_tmp_output) unless @proof_tmp_output == nil || @proof_tmp_output == "-"
    z = ccall("__w_rmdir", @race_dir)
    0

  # The reduced formula as strict DIMACS plus the id table (line k holds the
  # certificate id of clause k).
  -> write_artifact(nvars, art, reduced_path, gids_path)
    lines = []
    lines.push("p cnf [nvars] [art["clauses"].size]")
    art["clauses"].each -> (c)
      lines.push(c.empty? ? "0" : c.join(" ") + " 0")
    raise "artifact write failed" unless write_file(reduced_path, lines.join("\n") + "\n")
    glines = []
    art["gids"].each -> (g)
      glines.push("[g]")
    glines.push("[art["next_gid"]]")
    raise "artifact write failed" unless write_file(gids_path, glines.join("\n") + "\n")
    0

# Write a preprocessed artifact (reduced DIMACS + global-id table) for
# worker processes. Returns false on any write failure.
-> wassat_write_artifact_files(nvars, art, reduced_path, gids_path)
  lines = []
  lines.push("p cnf [nvars] [art["clauses"].size]")
  art["clauses"].each -> (c)
    lines.push(c.empty? ? "0" : c.join(" ") + " 0")
  return false unless write_file(reduced_path, lines.join("\n") + "\n")
  glines = []
  art["gids"].each -> (g)
    glines.push("[g]")
  glines.push("[art["next_gid"]]")
  write_file(gids_path, glines.join("\n") + "\n")

# Path to the running wassat binary (argv[0] as invoked).
-> wassat_own_binary
  a = ccall("__w_argv_program")
  a == nil || a == "" ? "wassat" : a

# Resolve the Metal sidecar the build emits BESIDE the running executable,
# not relative to the current working directory. WASSAT_METAL overrides. Only
# when argv[0] carries no directory (a bare PATH lookup) do we fall back to a
# CWD-relative path.
-> wassat_metal_path
  override = env("WASSAT_METAL")
  return override if override != nil && override != ""
  prog = wassat_own_binary
  slash = 0 - 1
  i = 0
  while i < prog.size
    slash = i if prog.slice(i, 1) == "/"
    i += 1
  return "bin/wassat.metal" if slash < 0
  prog.slice(0, slash + 1) + "wassat.metal"

# ---- worker mode ------------------------------------------------------------
#
# `wassat --worker reduced.cnf --gids g.txt --status out [--arm X]
#  [--seed N] [--proof-tmp path]`
#
# Consumes the artifact, solves, writes its model (SAT) to the status file,
# commits its proof atomically (write temp, rename), and answers through the
# SAT-conventional exit code: 10 SAT / 20 UNSAT. Anything else is a failure.
-> wassat_run_worker(args)
  input = nil
  gids_path = nil
  status_path = nil
  proof_tmp = nil
  arm = "marathon"
  seed = 1
  seen = {}
  i = 0
  while i < args.size
    flag = args[i]
    if flag == "--gids" || flag == "--status" || flag == "--proof-tmp" || flag == "--arm" || flag == "--seed"
      raise "duplicate worker option: [flag]" if seen[flag] == true
      seen[flag] = true
      raise "missing value after [flag]" if i + 1 >= args.size
      value = args[i + 1]
      if flag == "--gids"
        gids_path = value
      elsif flag == "--status"
        status_path = value
      elsif flag == "--proof-tmp"
        proof_tmp = value
      elsif flag == "--arm"
        arm = value
      else
        seed = wassat_decimal_in_range("--seed", value, 0, 2147483647)
      i += 2
    elsif flag.starts_with?("--")
      raise "unknown worker option: [flag]"
    else
      raise "unexpected extra argument '[flag]'" unless input == nil
      input = flag
      i += 1
  raise "worker needs an input formula" if input == nil
  raise "worker needs --gids" if gids_path == nil
  raise "worker needs --status" if status_path == nil
  unless arm == "marathon" || arm == "garden" || arm == "sls" || arm == "probe"
    raise "unknown worker arm '[arm]'"
  raise "worker prover arm needs --proof-tmp" if (arm == "marathon" || arm == "garden") && proof_tmp == nil

  cnf_text = read_file(input)
  raise "cannot read reduced formula" if cnf_text == nil
  formula = wassat_parse_cnf(cnf_text)
  gtext = read_file(gids_path)
  raise "cannot read gid table" if gtext == nil
  gids = []
  max_gid = 0
  gtext.split("\n").each -> (line)
    t = line.strip
    unless t == ""
      g = wassat_decimal_in_range("gid table entry", t, 1, 2000000000)
      raise "gid table must be strictly increasing" if g <= max_gid
      gids.push(g)
      max_gid = g
  next_gid = gids.pop
  # NOTE: this worker path parses with wassat_parse_cnf (BOXED) -- it has no
  # flat mirrors, so the count must come from the boxed list.
  raise "gid table length mismatch" unless gids.size == formula["clauses"].size
  raise "gid table is missing next_gid" if next_gid == nil
  unless gids.empty?
    raise "next_gid must be greater than every clause id" if next_gid <= gids[gids.size - 1]

  if arm == "sls"
    r = wassat_sls_solve(formula, 50000000, seed)
    if r["sat"]
      raise "status write failed" unless write_file(status_path, r["model"].join(" ") + " 0\n")
      exit(10)
    exit(3)                    # budget exhausted; SLS never answers UNSAT

  if arm == "probe"
    # trusted-mode racer over a light artifact: no proof obligations, so
    # verdicts are exit codes and SAT writes the reduced-formula model.
    # SELF-LIMITING: a coordinator killed by timeout/interrupt orphans the
    # racer (it leads its own process group by design) — two leaked probes
    # ground at 97% CPU for 20 minutes. The budget bounds an orphan's life;
    # a live coordinator never needs more than this anyway.
    sp = Wassat.new(formula["nvars"], wassat_formula_clauses(formula), WASSAT_PROOF_NONE, 0)
    pr = sp.solve_budget(2000000)
    if pr["status"] == 1
      raise "status write failed" unless write_file(status_path, pr["model"].join(" ") + " 0\n")
      exit(10)
    elsif pr["status"] == 0 - 1
      raise "status write failed" unless write_file(status_path, "UNSAT\n")
      exit(20)
    exit(3)

  s = Wassat.new(formula["nvars"], wassat_formula_clauses(formula), WASSAT_PROOF_WRAT, 0)
  s.seed_proof_ids(gids, next_gid)
  s.reseed_phases(seed) if arm == "garden"
  tmp = proof_tmp + ".tmp"
  raise "proof temp cleanup failed" unless ccall("__w_unlink", tmp)
  raise "proof temp prepare failed" unless write_file(tmp, "")
  s.stream_proofs(tmp, nil)
  s.wrat_header_written
  result = s.solve_budget(0)

  if result["status"] == 1
    s.abort_proof_sinks
    z = ccall("__w_unlink", tmp)
    raise "status write failed" unless write_file(status_path, result["model"].join(" ") + " 0\n")
    exit(10)
  elsif result["status"] == -1
    s.flush_proof_sinks
    raise "proof flush failed" unless ccall("__w_fsync_path", tmp)
    raise "proof rename failed" unless ccall("__w_rename", tmp, proof_tmp)
    raise "status write failed" unless write_file(status_path, "UNSAT\n")
    exit(20)
  s.abort_proof_sinks
  z = ccall("__w_unlink", tmp)
  exit(3)

# ---- threaded portfolio (--fast half) ----------------------------------------
#
# In-process threads with clause sharing — the trusted-not-proven mode, so
# PROOF_NONE throughout and no certificate. Everything workers touch is
# allocated on the MAIN thread before spawn (solver instances, the sharing
# ring, the stop cell, the result slab); worker bodies are allocation-free
# (fixed capacities, preallocated scratch), share low-LBD clauses through
# the seqlock ring, and stop cooperatively when any arm answers.
#
# A top-level fn as the thread body: thread.w snapshots block captures at
# spawn, so the per-arm loop variables bind correctly.
-> wassat_fast_arm_body(solver, res, base)
  solver.solve_shared(res, base)

# The same arm body for a ROUND of the adaptive race: solve a slice, then
# publish progress telemetry into this arm's private slice of the shared slab.
# `tel[tbase + 7]` accumulates solve milliseconds across rounds, which is the
# exposure denominator the allocator divides reward by — the "one pull is a
# resource-time quantum" rule, so a fast arm and a slow arm are compared on
# what they returned per millisecond rather than per invocation.
-> wassat_fast_arm_body_round(solver, res, base, budget, tel, tbase)
  t0 = ccall("__w_clock_ms")
  solver.solve_shared_budget(res, base, budget)
  solver.export_telemetry(tel, tbase)
  tel[tbase + 7] = tel[tbase + 7] + (ccall("__w_clock_ms") - t0)
  0

# ---- lucky arm ---------------------------------------------------------------
#
# kissat runs its lucky phases (lucky.c: four decision-free greedy dives) TWICE
# — once on the raw formula (`luckyearly`) and once on the preprocessed one
# (`luckylate`, search.c:178-190) — under two separate options, because
# preprocessing can CREATE luckiness: substitution and elimination collapse
# formulas that were not constant-satisfiable into ones that are.
#
# Here both shots are ARMS. An arm is the right shape for this technique
# because the dives propagate, and propagation permutes clause literals and
# moves watch entries — reordering any search that inherits the solver. Giving
# the dives their own solver in their own thread makes a miss cost nothing:
# nothing else in the process is perturbed, so there is no rebuild to pay for,
# and the arm's few milliseconds run beside real search rather than in front
# of it.
#
# Builds its own solver INSIDE the thread deliberately: constructing it on the
# main thread would put a from_flat back on the critical path, which is the
# cost this arrangement exists to remove.
-> wassat_lucky_arm_body(nv, art, res, base, stop)
  # Keep the worker-side guard even though the coordinator normally avoids
  # spawning this arm. It makes the no-construction contract local: a future
  # caller cannot accidentally copy the full formula before discovering that
  # shape policy disabled lucky phases.
  return 0 unless art["config"].use_lucky
  s = Wassat.from_flat_lucky(nv, art)
  s.set_stop_cell(stop)
  s.lucky_shared(res, base)

# ---- SLS arm ------------------------------------------------------------------
#
# Local search as a RACER on the raw path. It was previously a serial burst in
# wassat.w gated on `art["clauses"].size` in 2000..50000 — and on the raw path
# that gate could never pass, because wassat_raw_artifact returns
# `"clauses": []` and carries flat arrays instead. Since raw_kernel? is true
# above 5000 clauses the two windows overlap, so the burst was structurally
# unreachable exactly where it was written to fire (`c prof cli.sls_burst 0ms`
# on every raw run). Measured cost of that: n320p5q2_n 0.07s of walking against
# 25.06s of racing, n384p5q2_vh 0.47s against 58.67s, and DivS_568_11,
# DivS_862_11 and ntil-90d-33 solved in 2.3s/3.6s/23.0s where the race does not
# finish at all.
#
# An arm rather than a wider window, for the reason preprocessing is an arm: a
# serial burst that misses is wasted critical path, so it has to be gated on a
# guess about whether it will hit, and there is no such guess. As a racer a
# miss costs a core and nothing else, and the clause-count window disappears.
# Two of those rows are 200k and 553k clauses, far outside the window that was
# there.
#
# Builds inside its first thread slice, exactly like wassat_lucky_arm_body:
# construction normalises the raw artifact, which is real work that does not
# belong on the critical path. Later slices resume that same walker object.
#
# MODEL ONLY — local search cannot refute, so this arm never writes -1. Its
# model is in the ORIGINAL formula's variable space (it walks formula's own
# clauses, not a rendering), which is the same space the raw arms answer in,
# so the coordinator treats an SLS win exactly like a raw win.
#
# A bounded Metaflip-style repair is MODEL ONLY. Freeze every variable outside
# the exact unsatisfied-clause fringe of the walker's true best snapshot, solve
# under those assumptions, and grow the fringe only from failed-assumption
# cores. Formula-level UNSAT (an empty core) is deliberately non-decisive.
-> wassat_sls_frozen_repair(formula, art, best_bits, best_assign,
                            best_unsat, stop, conflict_cap = 0,
                            budget_state = nil, budget_limit = 0,
                            budget_slot = 0)
  miss = { "sat": false, "model": [], "attempted": false, "rounds": 0,
           "core_rounds": 0, "conflicts": 0, "relaxed": 0 }
  return miss if wassat_stop_requested?(stop)
  return miss unless art["raw"] == true
  return miss unless wassat_sls_repair_eligible?(formula)
  return miss if best_unsat < 1 || best_unsat > WASSAT_SLS_REPAIR_MAX_UNSAT

  nv = formula["nvars"]
  mutable = i64[nv + 1]
  meta = i64[2]
  wassat_sls_mark_fringe(
    art["fla"], art["fcs"], art["fcl"], art["fncl"],
    best_bits, mutable, meta
  )
  # The snapshot/count equality is an exact hand-off contract between the SLS
  # kernel and repair. A stale endpoint or malformed snapshot is a miss, never
  # a larger guessed neighbourhood.
  return miss unless meta[0] == best_unsat
  return miss if meta[1] < 1 || meta[1] > WASSAT_SLS_REPAIR_MAX_FRINGE
  miss["attempted"] = true
  miss["relaxed"] = meta[1]

  repair = Wassat.from_flat(nv, art, 0)
  repair.enable_fixed_caps
  repair.set_stop_cell(stop)
  if budget_state != nil
    repair.set_shared_conflict_budget(
      budget_state, budget_limit, budget_slot
    )
  repair.set_phases(best_assign)
  previous_conflicts = 0
  round = 0
  while round < WASSAT_SLS_REPAIR_ROUNDS
    return miss if wassat_stop_requested?(stop)
    allowance = wassat_sls_repair_round_conflicts(round)
    internal_left = WASSAT_SLS_REPAIR_MAX_CONFLICTS - miss["conflicts"]
    return miss if internal_left <= 0
    allowance = internal_left if allowance > internal_left
    if conflict_cap > 0
      caller_left = conflict_cap - miss["conflicts"]
      return miss if caller_left <= 0
      allowance = caller_left if allowance > caller_left

    assumptions = []
    v = 1
    while v <= nv
      assumptions.push(best_bits[v] == 1 ? v : 0 - v) if mutable[v] == 0
      v += 1
    # Poll immediately before every persistent-solver query. The solver itself
    # also polls the same cell at each conflict.
    return miss if wassat_stop_requested?(stop)
    r = repair.solve_assuming_budget(assumptions, allowance)
    delta = r["conflicts"] - previous_conflicts
    delta = 0 if delta < 0
    miss["conflicts"] += delta
    previous_conflicts = r["conflicts"]
    miss["rounds"] += 1

    if r["status"] == 1
      unless wassat_model_satisfies?(formula, r["model"])
        raise "internal error: frozen-fringe repair model does not satisfy the input formula"
      miss["sat"] = true
      miss["model"] = r["model"]
      return miss
    if r["status"] == 0 - 1
      core = r["core"]
      # Empty means the raw formula itself was refuted. This model-only lane
      # has no certificate channel, so it must not publish or stop the race.
      return miss if core.empty?
      added = 0
      core.each -> (l)
        v = l.abs
        if mutable[v] == 0
          mutable[v] = 1
          added += 1
      return miss if added == 0
      miss["relaxed"] += added
      miss["core_rounds"] += 1
      return miss if miss["relaxed"] > WASSAT_SLS_REPAIR_MAX_FRINGE
    round += 1
  miss

# One bounded/resumable SLS slice. The first call constructs from the ALREADY
# BUILT raw artifact and places the walker in `out`; later calls continue it.
# Result-slab tail:
#   +nv+1 repair won    +nv+2 repair inspected    +nv+3 walk finished
#   +nv+4 flips         +nv+5 end ms              +nv+6 start ms
#   +nv+7 repair conflicts (cumulative)
-> wassat_sls_arm_body_round(nv, formula, art, res, base, stop,
                             target_flips, total_flips, seed, out,
                             first, repair_allowed, repair_conflict_cap,
                             budget_state = nil, budget_limit = 0,
                             budget_slot = 0)
  res[base + nv + 6] = ccall("__w_clock_ms") if first
  s = nil
  if first
    # The stop cell reaches the CONSTRUCTOR too. Importantly, the source is
    # `art`, not the shared parser Hash: every race arm consumes the same
    # already-built raw artifact and no second formula view is rebuilt.
    s = WassatSls.new(nv, [], stop, art)
    s.set_stop_cell(stop)
    s.set_plateau(wassat_sls_plateau_window, wassat_sls_plateau_windows)
    out.push(s)
  else
    return 0 if out.empty?
    s = out[0]

  prefix_target = target_flips
  if repair_allowed && res[base + nv + 2] == 0 && target_flips > WASSAT_SLS_REPAIR_PREFIX_FLIPS
    prefix_target = WASSAT_SLS_REPAIR_PREFIX_FLIPS
  if first
    r = s.solve(prefix_target, seed)
  else
    r = s.continue_solve(prefix_target, seed)

  if !r["sat"] && !wassat_stop_requested?(stop) && repair_allowed && res[base + nv + 2] == 0 && r["flips"] >= WASSAT_SLS_REPAIR_PREFIX_FLIPS
    res[base + nv + 2] = 1
    rr = wassat_sls_frozen_repair(
      formula, art, r["best_bits"], r["best_assign"], r["best_unsat"],
      stop, repair_conflict_cap, budget_state, budget_limit, budget_slot
    )
    res[base + nv + 7] += rr["conflicts"]
    if rr["sat"]
      r["sat"] = true
      r["model"] = rr["model"]
      res[base + nv + 1] = 1

  # In an unbounded race the first slice may have paused only to attempt the
  # prefix repair. Resume straight through to its requested ceiling. Bounded
  # and adaptive races pass a finite per-round target and resume next round.
  if !r["sat"] && !wassat_stop_requested?(stop) && target_flips > r["flips"]
    r = s.continue_solve(target_flips, seed)

  res[base + nv + 4] = r["flips"]
  res[base + nv + 5] = ccall("__w_clock_ms")
  finished = r["sat"] || r["flips"] >= total_flips || r["retired"]
  res[base + nv + 3] = 1 if finished
  if r["sat"]
    m = r["model"]
    v = 1
    while v <= nv
      res[base + v] = m[v - 1] > 0 ? 1 : 0
      v += 1
    res[base] = 1
    # first decisive answer raises the stop flag for every other arm
    won = wassat_stop_publish(stop, 1)
  0

# Scout wrapper: its caller raises `stop` as soon as the decisive scout work
# ends, so even the nominally long target cannot become an orphaned join.
-> wassat_sls_arm_body(nv, formula, art, res, base, stop, flips, seed,
                       repair_allowed = false, repair_conflict_cap = 0,
                       budget_state = nil, budget_limit = 0,
                       budget_slot = 0)
  out = []
  wassat_sls_arm_body_round(
    nv, formula, art, res, base, stop, flips, flips, seed, out, true,
    repair_allowed, repair_conflict_cap,
    budget_state, budget_limit, budget_slot
  )
  0

# ---- xorshift circuit specialist ----------------------------------------------
#
# The SC2026 xorshift family is not merely "XOR-heavy".  It is a complete,
# topologically ordered 32-bit circuit: variables 1..32 are the only inputs,
# every later variable is defined once by XOR/AND/OR, and exactly 32 trailing
# units pin one output word.  The high-level circuit is
#
#   state = input; accumulator = input
#   state = xorshift32(state); accumulator {xor/add}= state
#
# for a formula-specific sequence of folds.  One final xorshift state is
# rendered but unused. A full gate scan followed by an exact wire-graph match
# recovers the fold sequence automatically; there is no filename or user
# switch in the decision.
#
# Once recognized, exhaustive preimage search has only 2^32 candidates and a
# tiny native evaluator.  It is bounded and MODEL ONLY: exhausting the domain
# says nothing to the coordinator.  A hit is replayed through every recognized
# gate and checked against the ORIGINAL CNF before the shared SAT flag moves.

WASSAT_XS32_MASK = 4294967295
WASSAT_XS32_DOMAIN = 4294967296
WASSAT_XS32_MAX_FOLDS = 20
WASSAT_XS32_MAX_WORKERS = 10

-> wassat_xs32_step(x) (i64) i64
  y = x & WASSAT_XS32_MASK ## i64
  y = (y ^ (y << 13)) & WASSAT_XS32_MASK
  y = y ^ (y >> 17)
  (y ^ (y << 5)) & WASSAT_XS32_MASK

-> wassat_xs32_fold(x, add_mask, nfolds) (i64 i64 i64) i64
  state = x & WASSAT_XS32_MASK ## i64
  accumulator = state ## i64
  i = 0 ## i64
  while i < nfolds
    state = wassat_xs32_step(state)
    if ((add_mask >> i) & 1) == 1
      accumulator = (accumulator + state) & WASSAT_XS32_MASK
    else
      accumulator = accumulator ^ state
    i += 1
  accumulator

# Evaluate one three-clause gate definition on a proposed input/output triple.
# Returns 1 iff every clause is satisfied and every literal belongs to the
# proposed variables.  The recognizer calls this only during its bounded
# 8-row truth-table check.
-> wassat_gate3_clauses_hold(fla, fcs, fcl, ci, a, av, b, bv, o, ov) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64) i64
  q = 0 ## i64
  while q < 3
    off = fcs[ci + q] ## i64
    len = fcl[ci + q] ## i64
    return 0 unless (q == 0 && len == 3) || (q > 0 && len == 2)
    sat = 0 ## i64
    j = 0 ## i64
    while j < len
      lit = fla[off + j] ## i64
      var = lit < 0 ? 0 - lit : lit ## i64
      val = 0 - 1 ## i64
      val = av if var == a
      val = bv if var == b
      val = ov if var == o
      return 0 if val < 0
      truth = lit > 0 ? val : 1 - val ## i64
      sat = 1 if truth == 1
      j += 1
    return 0 if sat == 0
    q += 1
  1

# Replay the topological gate program. `values` is supplied by the caller so
# fingerprinting can reuse one allocation and a winning arm can retain the
# complete original-variable assignment for the final CNF check.
-> wassat_xs32_circuit_eval(types, lhs, rhs, unit_vars, nv, input, values) (i64[] i64[] i64[] i64[] i64 i64 i64[]) i64
  v = 1 ## i64
  while v <= 32
    values[v] = (input >> (v - 1)) & 1
    v += 1
  while v <= nv
    a = values[lhs[v]] ## i64
    b = values[rhs[v]] ## i64
    kind = types[v] ## i64
    values[v] = a ^ b if kind == 1
    values[v] = a & b if kind == 2
    values[v] = a | b if kind == 3
    v += 1
  word = 0 ## i64
  i = 0 ## i64
  while i < 32
    word = word | (values[unit_vars[i]] << i)
    i += 1
  word

# Gate inputs are commutative. The CNF recognizer stores them in variable-id
# order, while the structural matcher names them by bit-level role.
-> wassat_xs32_gate_is?(types, lhs, rhs, gate, kind, a, b)
  return false unless types[gate] == kind
  return true if lhs[gate] == a && rhs[gate] == b
  lhs[gate] == b && rhs[gate] == a

# Match the exact 19+15+27 gate rendering of:
#
#   x ^= x << 13; x ^= x >> 17; x ^= x << 5
#
# `cursor` advances only after the whole operation matches.
-> wassat_xs32_match_step(types, lhs, rhs, input, cursor, nv)
  word = i64[32]
  old = i64[32]
  i = 0
  while i < 32
    word[i] = input[i]
    old[i] = input[i]
    i += 1
  gate = cursor[0]
  i = 13
  while i < 32
    return nil if gate > nv
    return nil unless wassat_xs32_gate_is?(
      types, lhs, rhs, gate, 1, old[i], old[i - 13]
    )
    word[i] = gate
    gate += 1
    i += 1
  i = 0
  while i < 32
    old[i] = word[i]
    i += 1
  i = 0
  while i < 15
    return nil if gate > nv
    return nil unless wassat_xs32_gate_is?(
      types, lhs, rhs, gate, 1, old[i], old[i + 17]
    )
    word[i] = gate
    gate += 1
    i += 1
  i = 0
  while i < 32
    old[i] = word[i]
    i += 1
  i = 5
  while i < 32
    return nil if gate > nv
    return nil unless wassat_xs32_gate_is?(
      types, lhs, rhs, gate, 1, old[i], old[i - 5]
    )
    word[i] = gate
    gate += 1
    i += 1
  cursor[0] = gate
  word

# Match one bitwise accumulator XOR. Outputs are one consecutive 32-gate run.
-> wassat_xs32_match_word_xor(types, lhs, rhs, a, b, cursor, nv)
  out = i64[32]
  gate = cursor[0]
  i = 0
  while i < 32
    return nil if gate > nv
    return nil unless wassat_xs32_gate_is?(
      types, lhs, rhs, gate, 1, a[i], b[i]
    )
    out[i] = gate
    gate += 1
    i += 1
  cursor[0] = gate
  out

# Match the generator's exact 189-gate ripple adder. The sum outputs are
# emitted in bit order but are interleaved with carry auxiliaries.
-> wassat_xs32_match_add(types, lhs, rhs, a, b, cursor, nv)
  out = i64[32]
  gate = cursor[0]
  return nil if gate + 188 > nv
  return nil unless wassat_xs32_gate_is?(
    types, lhs, rhs, gate, 1, a[0], b[0]
  )
  out[0] = gate
  gate += 1
  return nil unless wassat_xs32_gate_is?(
    types, lhs, rhs, gate, 2, a[0], b[0]
  )
  carry = gate
  gate += 1
  return nil unless wassat_xs32_gate_is?(
    types, lhs, rhs, gate, 3, a[0], b[0]
  )
  gate += 1

  i = 1
  while i < 32
    return nil unless wassat_xs32_gate_is?(
      types, lhs, rhs, gate, 1, a[i], b[i]
    )
    pair = gate
    gate += 1
    return nil unless wassat_xs32_gate_is?(
      types, lhs, rhs, gate, 1, carry, pair
    )
    out[i] = gate
    gate += 1
    return nil unless wassat_xs32_gate_is?(
      types, lhs, rhs, gate, 2, a[i], b[i]
    )
    both = gate
    gate += 1
    return nil unless wassat_xs32_gate_is?(
      types, lhs, rhs, gate, 3, a[i], b[i]
    )
    a_or_b = gate
    gate += 1
    return nil unless wassat_xs32_gate_is?(
      types, lhs, rhs, gate, 2, carry, a_or_b
    )
    carried = gate
    gate += 1
    return nil unless wassat_xs32_gate_is?(
      types, lhs, rhs, gate, 3, both, carried
    )
    carry = gate
    gate += 1
    i += 1
  cursor[0] = gate
  out

# A strict, complete circuit recognizer.  It accepts only:
#   * 32 primary inputs and one definition for every later variable;
#   * consecutive four-clause xor(a,b,out) or three-clause AND/OR definitions;
#   * the exact xorshift32 and fold wire graph, ending in one unused step;
#   * 32 trailing units pinning exactly the final accumulator outputs; and
#   * redundant semantic agreement on four independent evaluations.
#
# Returning nil is the normal generic-formula path.
-> wassat_xs32_circuit_plan(nv, formula)
  return nil unless formula.has_key?("nvars") && formula["nvars"] == nv
  return nil if nv < 128 || nv > 10000
  fla = formula["flat_lits"] ## i64[]
  fcs = formula["flat_offs"] ## i64[]
  fcl = formula["flat_lens"] ## i64[]
  ncl = formula["flat_ncl"]
  return nil if ncl < 500 || ncl > 100000
  return nil if ncl < 32
  unit_start = ncl - 32
  ci = unit_start
  while ci < ncl
    return nil unless fcl[ci] == 1
    ci += 1
  return nil if unit_start > 0 && fcl[unit_start - 1] == 1

  types = i64[nv + 1]
  lhs = i64[nv + 1]
  rhs = i64[nv + 1]
  expected = 33
  ci = 0
  nxor = 0
  nand = 0
  nor = 0
  while expected <= nv
    return nil if ci >= unit_start
    accepted = false

    # Four complete, distinct patterns of one parity over the same three
    # variables are an exact width-three XOR. The largest variable is the
    # newly defined output and the parity must encode out = a xor b.
    if ci + 4 <= unit_start
      all_three = true
      q = 0
      while q < 4
        all_three = false unless fcl[ci + q] == 3
        q += 1
      if all_three
        vars = []
        off = fcs[ci]
        j = 0
        while j < 3
          lit = fla[off + j]
          var = lit < 0 ? 0 - lit : lit
          vars.push(var)
          j += 1
        # Three-element insertion sort.
        if vars[0] > vars[1]
          z = vars[0]
          vars[0] = vars[1]
          vars[1] = z
        if vars[1] > vars[2]
          z = vars[1]
          vars[1] = vars[2]
          vars[2] = z
        if vars[0] > vars[1]
          z = vars[0]
          vars[0] = vars[1]
          vars[1] = z
        if vars[0] != vars[1] && vars[1] != vars[2] && vars[2] == expected && vars[0] < expected && vars[1] < expected
          seen = i64[8]
          parity = 0 - 1
          good = true
          q = 0
          while q < 4
            pattern = 0
            par = 0
            matched = 0
            off = fcs[ci + q]
            j = 0
            while j < 3
              lit = fla[off + j]
              var = lit < 0 ? 0 - lit : lit
              k = 0
              k = 1 if var == vars[1]
              k = 2 if var == vars[2]
              good = false unless var == vars[k]
              matched = matched | (1 << k)
              if lit < 0
                pattern = pattern | (1 << k)
                par = par ^ 1
              j += 1
            good = false unless matched == 7
            parity = par if parity < 0
            good = false unless par == parity
            good = false if seen[pattern] == 1
            seen[pattern] = 1
            q += 1
          # xor(a,b,out)=0, hence out=a xor b.
          if good && parity == 1
            types[expected] = 1
            lhs[expected] = vars[0]
            rhs[expected] = vars[1]
            nxor += 1
            ci += 4
            expected += 1
            accepted = true

    unless accepted
      return nil if ci + 3 > unit_start
      return nil unless fcl[ci] == 3 && fcl[ci + 1] == 2 && fcl[ci + 2] == 2
      vars = []
      off = fcs[ci]
      j = 0
      while j < 3
        lit = fla[off + j]
        var = lit < 0 ? 0 - lit : lit
        vars.push(var)
        j += 1
      if vars[0] > vars[1]
        z = vars[0]
        vars[0] = vars[1]
        vars[1] = z
      if vars[1] > vars[2]
        z = vars[1]
        vars[1] = vars[2]
        vars[2] = z
      if vars[0] > vars[1]
        z = vars[0]
        vars[0] = vars[1]
        vars[1] = z
      return nil unless vars[0] != vars[1] && vars[1] != vars[2]
      return nil unless vars[2] == expected && vars[0] < expected && vars[1] < expected
      table = 0
      av = 0
      while av < 2
        bv = 0
        while bv < 2
          found = 0 - 1
          ov = 0
          while ov < 2
            if wassat_gate3_clauses_hold(
              fla, fcs, fcl, ci, vars[0], av, vars[1], bv, expected, ov
            ) == 1
              return nil if found >= 0
              found = ov
            ov += 1
          return nil if found < 0
          table = table | (found << (av * 2 + bv))
          bv += 1
        av += 1
      return nil unless table == 8 || table == 14
      types[expected] = table == 8 ? 2 : 3
      lhs[expected] = vars[0]
      rhs[expected] = vars[1]
      nand += 1 if table == 8
      nor += 1 if table == 14
      ci += 3
      expected += 1
  return nil unless ci == unit_start

  # Match the dataflow itself. Gate counts are not a family recognizer: an
  # unrelated circuit can have the same totals and collide on finitely many
  # sample evaluations. Here every expected wire must be the next defined
  # variable, so a successful plan is the exact xorshift/fold program.
  state = i64[32]
  accumulator = i64[32]
  i = 0
  while i < 32
    state[i] = i + 1
    accumulator[i] = i + 1
    i += 1
  cursor = i64[1]
  cursor[0] = 33
  nfolds = 0
  nadd = 0
  add_mask = 0
  while nfolds <= WASSAT_XS32_MAX_FOLDS
    next_state = wassat_xs32_match_step(
      types, lhs, rhs, state, cursor, nv
    )
    return nil if next_state == nil
    state = next_state
    # The generator renders one final state transition whose outputs are
    # intentionally unused. It must consume every remaining gate definition.
    break if cursor[0] == nv + 1
    return nil if cursor[0] > nv
    return nil if nfolds == WASSAT_XS32_MAX_FOLDS

    folded = wassat_xs32_match_word_xor(
      types, lhs, rhs, accumulator, state, cursor, nv
    )
    if folded == nil
      folded = wassat_xs32_match_add(
        types, lhs, rhs, accumulator, state, cursor, nv
      )
      return nil if folded == nil
      add_mask = add_mask | (1 << nfolds)
      nadd += 1
    accumulator = folded
    nfolds += 1
  return nil unless cursor[0] == nv + 1
  return nil if nfolds <= 0 || nfolds > WASSAT_XS32_MAX_FOLDS

  # Retain gate-count equations as redundant whole-program invariants.
  expected_xor = 61 * (nfolds + 1) + 32 * (nfolds - nadd) + 63 * nadd
  return nil unless nxor == expected_xor
  return nil unless nand == 63 * nadd && nor == 63 * nadd

  # Units can appear in any clause order. Match them as a set against the
  # structurally recovered accumulator and derive target bits by accumulator
  # position, not by variable id (ripple-add auxiliaries create gaps).
  unit_vars = i64[32]
  used_units = i64[32]
  target = 0
  i = 0
  while i < 32
    unit_vars[i] = accumulator[i]
    found_unit = 0 - 1
    q = 0
    while q < 32
      lit = fla[fcs[unit_start + q]]
      var = lit < 0 ? 0 - lit : lit
      if var == accumulator[i]
        return nil if found_unit >= 0
        found_unit = q
      q += 1
    return nil if found_unit < 0 || used_units[found_unit] == 1
    used_units[found_unit] = 1
    lit = fla[fcs[unit_start + found_unit]]
    target = target | (1 << i) if lit > 0
    i += 1

  # Redundant semantic assertion: exact structural matching is the admission
  # gate, while these samples guard future edits to either evaluator.
  values = i64[nv + 1]
  samples = [1, 0x12345678, 0x9e3779b9, 0xdeadbeef]
  i = 0
  while i < samples.size
    actual = wassat_xs32_circuit_eval(
      types, lhs, rhs, unit_vars, nv, samples[i], values
    )
    return nil unless wassat_xs32_fold(
      samples[i], add_mask, nfolds
    ) == actual
    i += 1
  {
    "types": types, "lhs": lhs, "rhs": rhs, "unit_vars": unit_vars,
    "target": target, "add_mask": add_mask, "nfolds": nfolds,
    "nxor": nxor, "nand": nand, "nor": nor
  }

# One allocation-free contiguous partition of the 32-bit preimage domain.
# `found[slot]` stores candidate+1 before the private stop cell is published.
-> wassat_xs32_partition(target, add_mask, nfolds, lo, hi,
                         race_stop, local_stop, found, slot) (i64 i64 i64 i64 i64 i64[] i64[] i64[] i64) i64
  x = lo ## i64
  while x < hi
    if (x & 4095) == 0
      return 0 if wassat_stop_requested?(race_stop)
      return 0 if wassat_stop_requested?(local_stop)
    # Keep the hot 2^32-candidate kernel in one typed function. Tungsten's
    # current native pipeline does not inline the helper chain even under
    # release LTO; spelling out the fold here avoids one call per candidate
    # and one xorshift-step call per fold.
    state = x & WASSAT_XS32_MASK ## i64
    accumulator = state ## i64
    fold = 0 ## i64
    while fold < nfolds
      y = (state ^ (state << 13)) & WASSAT_XS32_MASK ## i64
      y = y ^ (y >> 17)
      state = (y ^ (y << 5)) & WASSAT_XS32_MASK
      if ((add_mask >> fold) & 1) == 1
        accumulator = (accumulator + state) & WASSAT_XS32_MASK
      else
        accumulator = accumulator ^ state
      fold += 1
    if accumulator == target
      found[slot] = x + 1
      won = wassat_stop_publish(local_stop, 1)
      return 1
    x += 1
  0

-> wassat_xs32_circuit_arm_body(nv, formula, plan, res, base, stop,
                                metrics = nil)
  return 0 if plan == nil || wassat_stop_requested?(stop)
  started = ccall("__w_clock_ms")
  res[base + nv + 6] = started
  workers = System.cpu_count - 3
  workers = 1 if workers < 1
  workers = WASSAT_XS32_MAX_WORKERS if workers > WASSAT_XS32_MAX_WORKERS
  local_stop = i64[4]
  found = i64[workers]
  handles = []
  slot = 0
  while slot < workers
    lo = (WASSAT_XS32_DOMAIN * slot) / workers
    hi = (WASSAT_XS32_DOMAIN * (slot + 1)) / workers
    target = plan["target"]
    add_mask = plan["add_mask"]
    nfolds = plan["nfolds"]
    worker_slot = slot
    handles.push(Thread.new -> wassat_xs32_partition(
      target, add_mask, nfolds, lo, hi, stop, local_stop, found, worker_slot
    ))
    slot += 1
  handles.each -> (handle)
    z = handle.join
  return 0 if wassat_stop_requested?(stop)

  candidate = 0 - 1
  slot = 0
  while slot < workers
    candidate = found[slot] - 1 if found[slot] > 0
    slot += 1
  res[base + nv + 5] = ccall("__w_clock_ms")
  if metrics != nil
    metrics[2] = plan["nfolds"] if metrics.size > 2
    metrics[3] = workers if metrics.size > 3
    metrics[4] = candidate if metrics.size > 4
    metrics[5] = res[base + nv + 5] - started if metrics.size > 5
  # Exhaustion is deliberately non-decisive: this lane has no proof channel.
  return 0 if candidate < 0

  values = i64[nv + 1]
  word = wassat_xs32_circuit_eval(
    plan["types"], plan["lhs"], plan["rhs"], plan["unit_vars"],
    nv, candidate, values
  )
  return 0 unless word == plan["target"]
  model = []
  v = 1
  while v <= nv
    res[base + v] = values[v]
    model.push(values[v] == 1 ? v : 0 - v)
    v += 1
  return 0 unless wassat_model_satisfies?(formula, model)
  # Payload before publication. +nv+2 tags the circuit specialist so the CLI
  # does not report it as a one-point Gaussian-elimination model.
  res[base + nv + 2] = 1
  res[base + nv + 4] = nv - 32
  res[base] = 1
  won = wassat_stop_publish(stop, 1)
  1

# ---- XOR refutation arm --------------------------------------------------------
#
# Tseitin/parity kernels are CNF renderings of GF(2) linear systems, and a
# linear system is refuted by Gaussian elimination in microseconds where CDCL
# needs millions of conflicts: Urquhart-s3-b3 is 18 XOR constraints wearing 376
# clauses, and the raw race spent 48s on what GE settles instantly. CaDiCaL
# beats us on these rows with raw throughput alone; this beats the approach
# rather than the constant.
#
# DETECTION. A width-k XOR constraint appears in CNF as exactly 2^(k-1)
# clauses over the same variable set, one per odd (or per even) assignment:
# each clause forbids the single assignment where all its literals are false,
# so the group's forbidden points are precisely one parity class. The test is
# therefore: group clauses by sorted variable set, and accept a group iff it
# has 2^(k-1) DISTINCT sign patterns all of the same negation parity p. The
# constraint is then xor(vars) = p^1.
#
# A common tree-parity rendering replaces one clause of a width-three XOR
# group by a stronger binary subclause. Recognize that form conservatively:
# exactly three distinct same-parity patterns, exactly one signed binary
# subclause of the missing pattern, and that binary must belong to exactly one
# such near-group. The binary implies the missing ternary clause, so the XOR
# row is still a logical consequence of the input.
#
# SOUNDNESS needs no coverage gate: complete groups are present verbatim, and
# every accepted near-group is implied by clauses present in the formula. An
# inconsistent system of those consequences refutes the whole formula.
# Clauses that fit neither strict form are simply not rows. The arm can
# therefore run on every instance; on a non-XOR formula it finds few or no
# rows, fails to refute, and reports nothing.
#
# A consistent subsystem does not by itself prove SAT because non-XOR clauses
# may remain. For a bounded dense kernel, however, back-substitute one exact
# GF(2) solution and check it against the ORIGINAL CNF. If the reduced system
# has a small affine dimension, enumerate its free coordinates under a static
# literal-work bound rather than trying only the all-free-zero point. Every
# candidate is checked against every original clause; a passing candidate is
# a self-certifying SAT model and a miss reports nothing. Fast path only -- a
# GE refutation has no DRAT justification here.
WASSAT_XOR_ENUM_MAX_FREE = 24
WASSAT_XOR_ENUM_MAX_LITERAL_WORK = 134217728
WASSAT_XOR_ARM_MAX_MS = 100
WASSAT_XOR_GRACE_NEAR_ROWS = 16

-> wassat_xor_should_stop?(stop, deadline_ms)
  return true if wassat_stop_requested?(stop)
  deadline_ms > 0 && ccall("__w_clock_ms") >= deadline_ms

-> wassat_xor_grace_requested?(res, base, nv)
  return false unless res.size > base + nv + 3
  ccall("__w_arr_load_acq", res, base + nv + 3) == 1

-> wassat_xor_arm_body(nv, formula, res, base, stop, metrics = nil,
                       circuit_plan = nil, deadline_ms = 0)
  if circuit_plan != nil
    hit = wassat_xs32_circuit_arm_body(
      nv, formula, circuit_plan, res, base, stop, metrics
    )
    return 0 if hit == 1 || wassat_stop_requested?(stop)
  # Flat mirrors, not boxed clauses: this arm runs in a worker thread.
  fla = formula["flat_lits"] ## i64[]
  fcs = formula["flat_offs"] ## i64[]
  fcl = formula["flat_lens"] ## i64[]
  ncl = formula["flat_ncl"]
  # Grouping hashes every clause; bound the work since this is a side arm.
  return 0 if ncl > 100000 || ncl < 4
  gvars = {}
  gpats = {}
  gpar = {}
  gbad = {}
  ci = 0
  while ci < ncl
    return 0 if (ci & 1023) == 0 && wassat_xor_should_stop?(stop, deadline_ms)
    co = fcs[ci]
    k = fcl[ci]
    if k >= 2 && k <= 24
      # sort the variables (insertion, k is tiny) and reject duplicates
      vs = []
      i = 0
      while i < k
        l = fla[co + i]
        v = l < 0 ? 0 - l : l
        j = vs.size - 1
        vs.push(v)
        while j >= 0 && vs[j] > v
          vs[j + 1] = vs[j]
          j -= 1
        vs[j + 1] = v
        i += 1
      dup = false
      i = 1
      while i < k
        dup = true if vs[i] == vs[i - 1]
        i += 1
      unless dup
        key = vs.join(",")
        # sign pattern: bit i set iff the literal of vs[i] is negative
        pat = 0
        par = 0
        i = 0
        while i < k
          l = fla[co + i]
          v = l < 0 ? 0 - l : l
          if l < 0
            par = par ^ 1
            j = 0
            while j < k
              pat = pat | (1 << j) if vs[j] == v
              j += 1
          i += 1
        if gvars[key] == nil
          gvars[key] = vs
          gpats[key] = {}
          gpar[key] = par
          gbad[key] = false
        gbad[key] = true if gpar[key] != par
        pats = gpats[key]
        gbad[key] = true if pats[pat] != nil
        pats[pat] = 1
    ci += 1
  # Find the strict width-three near-groups before selecting rows. A supporting
  # binary clause is accepted only if it is the sole clause on that signed
  # variable pair and is owned by exactly one near-group. Both restrictions
  # are conservative: ambiguous shapes fall through to generic search.
  near_support = {}
  support_owners = {}
  gkeys = gvars.keys
  gi = 0
  while gi < gkeys.size
    return 0 if (gi & 63) == 0 && wassat_xor_should_stop?(stop, deadline_ms)
    key = gkeys[gi]
    gi += 1
    unless gbad[key]
      vs = gvars[key]
      pats = gpats[key]
      if vs.size == 3 && pats.size == 3
        missing = 0 - 1
        pat = 0
        while pat < 8
          parity = ((pat >> 0) & 1) ^ ((pat >> 1) & 1) ^ ((pat >> 2) & 1)
          missing = pat if parity == gpar[key] && pats[pat] == nil
          pat += 1
        if missing >= 0
          support = nil
          nsupport = 0
          a = 0
          while a < 3
            b = a + 1
            while b < 3
              bkey = "[vs[a]],[vs[b]]"
              bpats = gpats[bkey]
              bpat = ((missing >> a) & 1) | (((missing >> b) & 1) << 1)
              if bpats != nil && !gbad[bkey] && bpats.size == 1 && bpats[bpat] != nil
                support = bkey + ":" + bpat.to_s
                nsupport += 1
              b += 1
            a += 1
          if nsupport == 1
            near_support[key] = support
            owners = support_owners[support]
            support_owners[support] = owners == nil ? 1 : owners + 1

  # Select accepted rows first and compress their variable coordinates.
  # DIMACS permits a huge declared variable bound with only a tiny active
  # parity kernel. Allocating every row across `nv` made 4096 accepted rows
  # quadratic in the declaration rather than the actual XOR subsystem.
  accepted = []
  near_rows = 0
  dense = {}
  dense_vars = []
  gi = 0
  while gi < gkeys.size && accepted.size < 4096
    return 0 if (gi & 63) == 0 && wassat_xor_should_stop?(stop, deadline_ms)
    key = gkeys[gi]
    gi += 1
    unless gbad[key]
      vs = gvars[key]
      k = vs.size
      support = near_support[key]
      complete = gpats[key].size == (1 << (k - 1))
      implied = support != nil && support_owners[support] == 1
      if complete || implied
        accepted.push(key)
        near_rows += 1 if implied
        i = 0
        while i < k
          v = vs[i]
          if dense[v] == nil
            dense[v] = dense_vars.size
            dense_vars.push(v)
          i += 1

  # Incremental GE over accepted groups. Rows are bitsets over only the
  # participating coordinates; `metrics` is a test/diagnostic sink.
  nw = (dense.size >> 6) + 1
  if metrics != nil
    metrics[0] = dense.size
    metrics[1] = nw
    metrics[2] = accepted.size if metrics.size > 2
    metrics[3] = near_rows if metrics.size > 3
  if near_rows >= WASSAT_XOR_GRACE_NEAR_ROWS && res.size > base + nv + 3
    z = ccall("__w_arr_store_rel", res, base + nv + 3, 1)
  pivots = []
  nrows = 0
  refuted = false
  gi = 0
  while gi < accepted.size
    return 0 if (gi & 63) == 0 && wassat_xor_should_stop?(stop, deadline_ms)
    key = accepted[gi]
    gi += 1
    unless refuted
      vs = gvars[key]
      k = vs.size
      nrows += 1
      row = i64[nw]
      i = 0
      while i < k
        d = dense[vs[i]]
        row[d >> 6] = row[d >> 6] | (1 << (d & 63))
        i += 1
      rhs = gpar[key] ^ 1
      # Reduce by existing pivots, lowest set bit as pivot position. Poll
      # inside both potentially long dimensions so a refutation by another
      # arm does not leave a dense elimination join behind.
      pi = 0
      while pi < pivots.size
        return 0 if (pi & 63) == 0 && wassat_xor_should_stop?(stop, deadline_ms)
        pv = pivots[pi]
        prow = pv[0]
        pw = pv[2]
        pb = pv[3]
        if ((row[pw] >> pb) & 1) == 1
          w = 0
          while w < nw
            return 0 if (w & 1023) == 0 && wassat_xor_should_stop?(stop, deadline_ms)
            row[w] = row[w] ^ prow[w]
            w += 1
          rhs = rhs ^ pv[1]
        pi += 1

      # Find this row's pivot.
      pw = 0 - 1
      pb = 0
      w = 0
      while w < nw && pw < 0
        return 0 if (w & 1023) == 0 && wassat_xor_should_stop?(stop, deadline_ms)
        if row[w] != 0
          pw = w
          b = 0
          while b < 64
            if ((row[w] >> b) & 1) == 1
              pb = b
              b = 64
            else
              b += 1
        w += 1
      if pw < 0
        refuted = true if rhs == 1
      else
        pivots.push([row, rhs, pw, pb])
  if refuted
    res[base] = 0 - 1
    res[base + nv + 4] = nrows
    won = wassat_stop_publish(stop, 0 - 1)
  elsif dense.size > 0 && dense.size <= 4096 && formula.has_key?("nvars") && formula["nvars"] == nv && res.size >= base + nv + 8
    # Rows are reduced against every EARLIER pivot before insertion, so a row
    # can depend only on free variables and LATER pivots. Reverse insertion
    # order is therefore a valid back-substitution order.
    # Keep each candidate in the same packed representation as the GE rows.
    # Back-substitution then computes one row parity with `nw` native popcounts
    # instead of scanning every dense coordinate for every pivot.
    value_words = i64[nw]
    pivoted = i64[dense.size]
    pi = 0
    while pi < pivots.size
      pv = pivots[pi]
      pivoted[pv[2] * 64 + pv[3]] = 1
      pi += 1
    free = []
    d = 0
    while d < dense.size
      free.push(d) if pivoted[d] == 0
      d += 1

    # The zero-free point preserves the old cheap candidate on every shape.
    # Full affine enumeration is allowed only when both dimension and total
    # verification work are bounded. A losing lane therefore cannot turn one
    # small XOR kernel into an unbounded 2^rank scan.
    candidates = 1
    if free.size <= WASSAT_XOR_ENUM_MAX_FREE
      full = 1 << free.size
      literal_work = full * formula["flat_nlits"]
      candidates = full if literal_work <= WASSAT_XOR_ENUM_MAX_LITERAL_WORK

    # `sign` is in ORIGINAL variable space and is reused across candidates.
    # Variables outside the accepted subsystem default false. wassat_verify_flat
    # scans every original clause; the canonical model guard is repeated once
    # on a hit before publication.
    sign = i64[nv + 1]
    v = 1
    while v <= nv
      sign[v] = 0 - 1
      v += 1
    verify = i64[2]
    verify[1] = ncl
    mask = 0
    while mask < candidates
      return 0 if wassat_xor_should_stop?(stop, deadline_ms)
      w = 0
      while w < nw
        value_words[w] = 0
        w += 1
      fi = 0
      while fi < free.size
        if ((mask >> fi) & 1) == 1
          d = free[fi]
          value_words[d >> 6] = value_words[d >> 6] | (1 << (d & 63))
        fi += 1

      pi = pivots.size - 1
      while pi >= 0
        return 0 if (pi & 63) == 0 && wassat_xor_should_stop?(stop, deadline_ms)
        pv = pivots[pi]
        row = pv[0]
        pivot = pv[2] * 64 + pv[3]
        value = pv[1]
        w = 0
        while w < nw
          value = value ^ (BitOps.count_ones_u64(row[w] & value_words[w]) & 1)
          w += 1
        if value == 1
          value_words[pivot >> 6] = value_words[pivot >> 6] | (1 << (pivot & 63))
        pi -= 1

      d = 0
      while d < dense_vars.size
        bit = (value_words[d >> 6] >> (d & 63)) & 1
        sign[dense_vars[d]] = bit == 1 ? 1 : 0 - 1
        d += 1
      wassat_verify_flat(fla, fcs, fcl, sign, verify)
      if verify[0] == 1
        model = []
        v = 1
        while v <= nv
          model.push(sign[v] == 1 ? v : 0 - v)
          v += 1
        unless wassat_model_satisfies?(formula, model)
          raise "internal error: affine xor model does not satisfy the input formula"
        v = 1
        while v <= nv
          res[base + v] = sign[v] == 1 ? 1 : 0
          v += 1
        res[base + nv + 4] = nrows
        res[base] = 1
        won = wassat_stop_publish(stop, 1)
        break
      mask += 1
  0

# The bounded CDCL scout, as an arm. It is the same search the coordinator used
# to run inline: its own solver over the same artifact, stopped by conflict cap
# (and, off the raw path, by wall clock). It runs beside the lucky arm so that
# neither pays for the other — a lucky win stops it through the shared cell,
# and a lucky miss leaves its trajectory bit-identical to the serial one.
#
# `out` is its private channel for the boxed result: the coordinator reports
# conflicts, decisions and propagations from it.
-> wassat_scout_arm_body(nv, art, stop, cap, wall, raw, simplify, out,
                         budget_state = nil, budget_limit = 0,
                         budget_slot = 0)
  s = Wassat.from_flat(nv, art, 0)
  s.set_stop_cell(stop)
  if budget_state != nil
    s.set_shared_conflict_budget(budget_state, budget_limit, budget_slot)
  s.simplify_raw if simplify
  t0 = ccall("__w_clock_ms")
  slice = cap < 512 ? cap : 512
  spr = s.solve_budget(slice)
  # The wall-clock cap bounds a miss on kernels whose conflicts are expensive,
  # but it makes the outcome depend on machine load: on bmc-ibm-10 the scout
  # decides at 1,733 conflicts when quiet and falls off a cliff to a full
  # 11k-conflict main solve when busy. A raw kernel's scout is already bounded
  # by its conflict cap, so it runs on conflicts alone and is reproducible.
  while spr["status"] == 0 && spr["conflicts"] < cap && !wassat_stop_requested?(stop) && (raw || ccall("__w_clock_ms") - t0 < wall)
    rem = cap - spr["conflicts"]
    slice = rem < 512 ? rem : 512
    spr = s.solve_budget(slice)
  out.push(spr)
  # Keep the live solver beside the detached result. A scout miss has already
  # paid construction, propagation, conflicts, learned clauses and heuristic
  # state; the main race can continue that exact search instead of throwing
  # all of it away and rebuilding four solvers from the original formula.
  out.push(s)
  # Publish the answer to the co-running arms only after the result payload is
  # complete. The lucky arm was short enough that this never mattered, the SLS
  # arm is not.
  if spr["status"] == 1 || spr["status"] == 0 - 1
    won = wassat_stop_publish(stop, spr["status"])
  0

# Raw-kernel basin race: K allocation-free arms over the SAME flat artifact,
# diversified along the axes that measurably move bmc-family trajectories —
# decision heuristic (VMTF vs EVSIDS) and initial phases. First decisive arm
# raises the stop cell. Motivation: ibm-12's conflict count ranges 4.9k-17k
# across heuristic configurations with no single winner; sampling basins
# concurrently buys min-over-arms wall time for one thread-spawn's overhead.
#
# Build the raw arms and the state they race over, returned as a bundle so
# the coordinator can run the race in SLICES and do main-thread work — which
# is to say preprocessing — in the gaps between them.
-> wassat_otfs_specialist_count(formula, matrix_threads, pre_workers,
                                  sls_worker, incumbent_worker,
                                  resident_cdcl_arenas = 0,
                                  resident_sls_arenas = 0,
                                  resident_preprocess_arenas = 0)
  return 0 if env("WASSAT_OTFS") == "0" || matrix_threads < 2
  requested = 1
  if env("WASSAT_OTFS_SPECIALISTS") != nil
    requested = wassat_decimal_in_range(
      "WASSAT_OTFS_SPECIALISTS", env("WASSAT_OTFS_SPECIALISTS"), 0, 1
    )
  return 0 if requested == 0
  # The specialist is additive: never trade away an established basin for a
  # sharply two-sided technique. WASSAT_ARMS is the deterministic width pin
  # used by A/B measurements, so an automatic arm must not silently widen it;
  # WASSAT_OTFS_SPECIALISTS remains the explicit override for specialist A/B.
  return 0 if env("WASSAT_ARMS") != nil && env("WASSAT_OTFS_SPECIALISTS") == nil
  # Count every worker already planned by the coordinator. Preprocessing, SLS
  # and a scout continuation are registered after race construction, but they
  # still consume cores once the race starts.
  workers = matrix_threads + pre_workers + sls_worker + incumbent_worker
  return 0 if System.cpu_count <= workers
  # Arena accounting is deliberately broader than runnable-worker accounting.
  # The completed scout/lucky solvers and scout SLS allocation remain resident
  # in this non-collecting runtime. Count those, every raw/preprocessed solver,
  # the race SLS arena, and this proposed specialist.
  cdcl_arenas = resident_cdcl_arenas + matrix_threads + pre_workers + incumbent_worker + 1
  sls_arenas = resident_sls_arenas + sls_worker
  preprocess_arenas = resident_preprocess_arenas + pre_workers
  return 0 unless wassat_race_memory_fits?(
    formula, cdcl_arenas, sls_arenas, preprocess_arenas
  )
  1

-> wassat_race_build(nv, art, threads, formula, incumbent = nil,
                     incumbent_conflicts = 0, pre_workers = 0, sls_worker = 0,
                     scout_solvers = 0, scout_sls_arenas = 0,
                     resident_preprocess_arenas = 0)
  # Continuation is additive. Replacing matrix arm 3 made qwh.35 lose its
  # repeatable 4,366-conflict trajectory; the scout has already allocated its
  # solver, so keeping it as one extra arm restores that diversity without
  # another large allocation.
  matrix_threads = threads
  incumbent_worker = incumbent == nil ? 0 : 1
  resident_cdcl_arenas = scout_solvers - incumbent_worker
  resident_cdcl_arenas = 0 if resident_cdcl_arenas < 0
  # SLS is optional. Apply the complete resident-memory gate before an OTFS
  # specialist is considered so the specialist can never crowd an accepted
  # walker out after construction.
  base_cdcl_arenas = resident_cdcl_arenas + matrix_threads + pre_workers + incumbent_worker
  preprocess_arenas = resident_preprocess_arenas + pre_workers
  if sls_worker > 0
    unless wassat_race_memory_fits?(
      formula, base_cdcl_arenas, scout_sls_arenas + 1,
      preprocess_arenas
    )
      sls_worker = 0
  otfs_specialists = wassat_otfs_specialist_count(
    formula, matrix_threads, pre_workers, sls_worker, incumbent_worker,
    resident_cdcl_arenas, scout_sls_arenas, resident_preprocess_arenas
  )
  otfs_index = matrix_threads
  threads += otfs_specialists
  threads += 1 if incumbent != nil
  incumbent_index = incumbent == nil ? 0 - 1 : threads - 1
  cdcl_arenas = resident_cdcl_arenas + threads + pre_workers
  sls_arenas = scout_sls_arenas + sls_worker
  # Repair owns one additional full CDCL arena while the SLS arena stays live.
  # Unknown host memory fails closed for this new specialist; the established
  # race itself retains its old unknown-memory behaviour.
  repair_allowed = false
  if sls_worker > 0 && System.physical_memory_bytes > 0
    repair_allowed = wassat_sls_repair_eligible?(formula)
    if repair_allowed
      repair_allowed = wassat_race_memory_fits?(
        formula, cdcl_arenas + 1, sls_arenas, preprocess_arenas
      )
  # Capacity for the raw arms, the two preprocessed renderings and the SLS
  # arm (slot threads+2, always reserved so indices never move), allocated
  # once: `res` is addressed by arm index and must not move after an arm has
  # a pointer into it.
  cap = threads + 3
  stop = i64[4]
  res = i64[cap * (nv + 8)]
  tel = i64[cap * WASSAT_TEL_STRIDE]
  # Cell k counts clauses AUTHORED by arm k that some other arm installed.
  credit = i64[cap]
  ring_maxlen = 24
  ring_cap = 4096
  ring = i64[8 + ring_cap * (3 + ring_maxlen)]
  # The arm's configuration, kept as DATA rather than only as a sequence of
  # calls on the solver: an allocator that may replace an arm has to be able
  # to name the configuration it is replacing, name the one it is replacing it
  # with, and give the axes credit separately (see wassat_race_axis_score).
  cfgs = i64[cap * WASSAT_CFG_STRIDE]
  # Conflicts an incumbent spent before joining this race. Race budgets are
  # additional work, and the CLI has already charged the scout work once, so
  # final accounting subtracts this offset from the winning arm.
  offsets = i64[cap]
  solvers = []
  a = 0
  while a < threads
    # Preserve every established matrix arm. The OTFS specialist clones arm
    # 1, the configuration that wins both ntil34 and mrpp6 under global OTFS,
    # without removing arm 1's ordinary first-UIP trajectory. The optional
    # final slot is still the scout continuation.
    continued = incumbent != nil && a == threads - 1
    specialist = a >= otfs_index && a < otfs_index + otfs_specialists
    s = continued ? incumbent : Wassat.from_flat(nv, art, 0)
    offsets[a] = incumbent_conflicts if continued
    s.enable_otfs if specialist
    s.enable_fixed_caps
    s.set_stop_cell(stop)
    # A lone raw arm has nobody to share with — the preprocessing arms solve
    # DIFFERENT formulas and must never take its clauses — so it keeps the
    # export path out of its inner loop entirely.
    # Keep continuation private: letting it publish into the established
    # matrix perturbed qwh.35's repeatable 4,366-conflict winning basin. Its
    # value is the state it already learned, not another source of clauses.
    if threads > 1 && !continued
      # The specialist may import the matrix's glue clauses, but does not
      # publish its changed trajectory back into the baseline arms. Thus the
      # hedge can win without perturbing the configurations it protects.
      s.enable_sharing(ring, ring_cap, ring_maxlen, a, !specialist)
      # Import-only specialists must also stay out of adaptive author-credit:
      # accepting a baseline clause is evidence about the specialist, not a
      # contribution that should change the protected arm's allocation.
      s.set_share_credit(credit) unless specialist
    if continued
      # Keep every bit of the scout trajectory. In particular, do not run
      # raw simplification after search has begun or overwrite the phases it
      # learned. Sharing/fixed-cap state above is safe to attach at a barrier.
      z = 0
    elsif matrix_threads == 1
      # Sole raw arm: take the configuration the serial post-probe solve
      # would have used, so adding a preprocessing arm changes only what
      # runs BESIDE the raw search and never the raw trajectory itself.
      s.enable_chrono
      s.simplify_raw if art["config"].force_simplify?
    else
      source = specialist ? 1 : a
      wassat_race_matrix_config(source, cfgs, a * WASSAT_CFG_STRIDE)
      # TRAIL REUSE axis, set here rather than in the native matrix because the
      # assignment is policy-driven (see policy.w trail_reuse_mask). Two-sided
      # and trajectory-dependent: forced on every arm it wins 2bitadd_10 and
      # schooltt but turns f1000 from 5.7s into a >150s timeout, twice.
      cfgs[a * WASSAT_CFG_STRIDE + 7] = (art["config"].trail_reuse_mask >> source) & 1
      # STABLE-ONLY axis (kissat --stable=2), same mask form. Violently
      # two-sided as a global -- 2bitadd_10 0.32x and ContextModel 0.29x FOR
      # it, dspam 20.21x and f600 3.70x against -- which is the textbook case
      # for racing it instead of choosing it.
      cfgs[a * WASSAT_CFG_STRIDE + 8] = (art["config"].stable_only_mask >> source) & 1
      wassat_race_apply_config(s, cfgs, a * WASSAT_CFG_STRIDE,
                               art["config"].force_simplify?,
                               art["config"].use_vmtf(art["raw"] == true))
    solvers.push(s)
    a += 1
  { "nv": nv, "solvers": solvers, "res": res, "stop": stop, "threads": threads,
    "cap": cap, "pre": [], "formula": formula, "tel": tel, "cfgs": cfgs,
    "art": art, "ring": ring, "ring_cap": ring_cap, "ring_maxlen": ring_maxlen,
    "credit": credit, "offsets": offsets, "sls": [],
    "matrix_threads": matrix_threads, "incumbent_index": incumbent_index,
    "otfs_index": otfs_index, "otfs_specialists": otfs_specialists,
    "sls_allowed": sls_worker > 0, "sls_repair_allowed": repair_allowed,
    "resident_cdcl_arenas": cdcl_arenas,
    "resident_sls_arenas": sls_arenas,
    "resident_preprocess_arenas": preprocess_arenas,
    "repair_cdcl_arenas": repair_allowed ? 1 : 0 }

# ---- arm configuration as data ------------------------------------------------
#
# WASSAT_CFG_STRIDE cells per arm:
#   0 branching   0 = the shape policy's heuristic, 1 = the other one
#   1 phase kind  0 = saved phases, 1 = reseeded from cell 2, 2 = all-positive
#   2 phase seed  (kind 1 only)
#   3 chrono      0 off, 1 on (chronological backtracking v2)
#   4 simplify    0 = none unless forced, 1 = substitution, 2 = + congruence
#   5 shrink      0 off, 1 All-UIP learned-clause shrinking
#   6 subsume     0 off, 1 subsumption+SSR every 3k conflicts, 2 every 10k
#   7 trail reuse  0 off, 1 on (policy trail_reuse_mask, set in the build loop)
#   8 stable-only  0 off, 1 never leave stable mode (policy stable_only_mask)
#
# Widened from 8 to 16 when the stable-only axis was added. Every access is
# relative to `a * WASSAT_CFG_STRIDE`, so the stride is free to grow.
WASSAT_CFG_STRIDE = 16
WASSAT_TEL_STRIDE = 8

# The historical hard-coded diversity matrix, transcribed exactly. Reproducing
# it here rather than replacing it is the point: the adaptive allocator STARTS
# from the matrix, so an instance the matrix already decides in one round is
# decided by the same eight trajectories it always was, and anything the
# allocator does afterwards is measured against that baseline rather than
# confounded with a new starting allocation.
#
# The axis rationale (unchanged, and each one is a measured symmetric win/loss
# on the bmc family, which is what makes it a race axis rather than a default):
# branching heuristic — ibm-12's conflict count ranges 4.9k-17k across
# configurations with no single winner. Chronological backtracking — worth
# ~3.5x when it fits the trajectory and a loss when it does not. Congruence
# plus equivalent-literal substitution — ibm-11 11,940 -> 4,734 conflicts and
# ibm-13 20,350 -> 9,238 with it, against ibm-12 7,162 -> 15,868; arms 1, 2, 5,
# 6 draw one from each phase group so the axis stays decorrelated. Arm 0 is
# reseeded because it would otherwise replay the serial probe's already-failed
# trajectory exactly.
-> wassat_race_matrix_config(a, cfgs, b) (i64 i64[] i64)
  grp = a / 2 ## i64
  cfgs[b] = a % 2
  cfgs[b + 1] = 0
  cfgs[b + 2] = 0
  if a == 0
    cfgs[b + 1] = 1
    cfgs[b + 2] = 777
  if grp == 1
    cfgs[b + 1] = 1
    cfgs[b + 2] = 1000 + a * 7919
  if grp == 2
    cfgs[b + 1] = 2
  if grp == 3
    cfgs[b + 1] = 1
    cfgs[b + 2] = 4242 + a * 104729
  cfgs[b + 3] = grp % 2
  cfgs[b + 4] = 0
  cfgs[b + 4] = 1 if a % 4 == 1
  cfgs[b + 4] = 2 if a % 4 == 2
  # SHRINK, decorrelated from the chrono axis so the four arms of a width-4
  # race span the full 2x2 of {chrono, shrink}: arm0 neither, arm1 shrink only,
  # arm2 chrono only, arm3 both. Raced rather than decided because the measured
  # spread is enormous and instance-dependent with no static predictor --
  # minand064 wants it (0.54x, 2.6x fewer conflicts) while php109 and hole9 are
  # 10x worse with it and need 34x the conflicts.
  cfgs[b + 5] = a % 2
  # SUBSUME, crossed with the chrono/shrink pair: arms 0-1 off, arms 2-3 on,
  # so a width-4 race samples {chrono, shrink} x {subsume} rather than
  # correlating them. Raced rather than defaulted because the spread is
  # extreme in BOTH directions -- 2bitadd_10 0.48x and mrpp_6x6 0.74x for it,
  # em_7_3_6_fbc 19x AGAINST it -- so no global setting is right.
  # ON, and the reason it survived a retraction is worth stating. An A/B on
  # MIN-of-3 scored it 0.89; that was an artifact (em_7_3_6_fbc is bimodal at
  # 5.3s/36.0s across runs of ONE binary in ONE configuration, so min reports
  # whichever column drew the fast mode). reference.py on MEDIANS then scored
  # the competition GEOMEAN worse, 1.81x -> 1.54x.
  #
  # But geomean is the wrong objective here. Row-by-row against the same
  # suite run, nothing lost a win and three rows improved in kind:
  #   2bitadd_10       TIE      -> WIN
  #   ibm-2004-03-k70  TIE      -> WIN
  #   crusti_g2io_200  UNSOLVED -> solves (59.8s)
  # 34 rows won -> 36, unsolved 8 -> 7. The geomean fell because
  # Carry_Bits_Fast_12 slowed 11.75s -> 40.57s, which is margin on a row that
  # is lost either way.
  # 0 off (arms 0,1) / 1 every 3k (arm 2) / 2 every 10k (arm 3)
  cfgs[b + 6] = 0
  cfgs[b + 6] = 1 if a % 4 == 2
  cfgs[b + 6] = 2 if a % 4 == 3
  # TRAIL REUSE, the XOR of the branching and chrono axes: arms 1 and 2 on,
  # arms 0 and 3 off. Those two already span the full 2x2 of {chrono, shrink},
  # so no plain split stays uncorrelated with them; the XOR does.
  #
  # Raced rather than defaulted for the usual reason -- it is two-sided with
  # no static predictor. Break_triple_10_16 0.31x and 2bitadd_10 0.61x for it,
  # minand064 1.32x and ContextModel 1.92x against it, and minand064's noise
  # floor is 1.02x so that regression is real rather than churn. It is also
  # NOT the fix it was built to be: SCPC-500-19, the 1,611-props/conflict row
  # that motivated it, times out at 120s with it both off and on.
  # slot 7 (TRAIL REUSE) is not set here: it comes from policy's
  # trail_reuse_mask in the build loop, which this native fn cannot read.
  0

# Apply a configuration vector to a freshly built solver. `forced` is the
# WASSAT_SIMPLIFY measurement hook: it only reaches arms whose simplify axis is
# 0, exactly as before.
-> wassat_race_apply_config(s, cfgs, b, forced, policy_vmtf)
  if cfgs[b] == 1
    if policy_vmtf
      s.disable_vmtf
    else
      s.enable_vmtf
  s.reseed_phases(cfgs[b + 2]) if cfgs[b + 1] == 1
  s.set_positive_phases if cfgs[b + 1] == 2
  s.enable_chrono if cfgs[b + 3] == 1
  s.simplify_raw_mode(0) if cfgs[b + 4] == 1
  s.simplify_raw_mode(1) if cfgs[b + 4] == 2
  s.simplify_raw if cfgs[b + 4] == 0 && forced
  s.enable_shrink if cfgs[b + 5] == 1
  # Two intervals, not one: the axis pays, so spend its second arm on a
  # DIFFERENT cadence rather than a duplicate. Arm 2 subsumes every 3k
  # conflicts, arm 3 every 10k -- the two intervals scored differently on
  # every row measured, so they are not interchangeable.
  s.enable_subsume(cfgs[b + 6] == 2 ? 10000 : 3000) if cfgs[b + 6] > 0
  s.enable_trail_reuse if cfgs[b + 7] == 1
  s.enable_stable_only if cfgs[b + 8] == 1
  0

# Register the SLS arm. Occupies the fixed slot threads+2 so it never collides
# with a preprocessing arm, whatever pre_arms turns out to be.
-> wassat_race_add_sls(race, flips, seed, art = nil)
  return 0 unless race["sls_allowed"] == true
  source = art == nil ? race["art"] : art
  race["sls"].push(
    { "flips": flips, "seed": seed, "out": [], "art": source }
  )
  0

# Register a PREPROCESSING arm: its own preprocessor (never shared — two
# threads rendering through one WassatPreprocess would race on its arena) and
# whether it runs the heavy rounds on top of the light ones. `label` names it
# in the verdict line.
#
# No clause sharing for these arms, deliberately. A learned clause is sound
# only for the formula it was derived from: variable elimination preserves
# satisfiability, not consequences, so a clause from the raw kernel need not
# be implied by a reduced one and installing it could refute a satisfiable
# formula. Every rendering is a different formula and carries exactly one
# arm, so a ring would be unsound AND useless.
-> wassat_race_add_pre(race, pre, heavy, label)
  raise "race capacity exceeded" if race["threads"] + race["pre"].size >= race["cap"]
  race["pre"].push({ "pre": pre, "heavy": heavy, "label": label, "out": [] })
  0

# A preprocessing arm: ONE thread that renders the formula and then solves
# what it rendered. This is the whole point of the design — preprocessing is
# not a decision the coordinator makes and pays for up front, it is a racer,
# and it costs the raw arms nothing but a core.
#
# It allocates heavily, in a worker thread, deliberately. That is safe here:
# the runtime has no GC and hands allocation to the system allocator, and
# per-thread runtime state is already __thread. The rule that does bind is
# about process-global DISPATCH state — inline caches are per-call-site and
# shared, and two threads publishing DIFFERENT methods through one site can
# still interleave — so the MAIN thread does nothing but join while this
# runs, and this arm sticks to the same already-warm code the serial
# preprocessed path uses rather than any newly-written polymorphic helper.
#
# `out` is this arm's private channel back to the coordinator: the elimination
# stack its model must be reconstructed through, the stats to report, and —
# from round 1 on — the solver it built over its own rendering, so a later
# round resumes that search instead of re-rendering the formula. Private per
# arm, so pushing to it needs no synchronisation.
#
# `round` 0 renders and starts search; every later round is a pure search slice
# on the solver round 0 left behind. A rendering cannot be sliced
# in the middle, so round 0 is as long as the rendering takes and the barrier
# after it is the one place a raw arm can be left waiting — which is why round
# 0 is also the longest slice the race ever hands out.
-> wassat_pre_arm_body(pre, formula, nv, res, base, heavy, stop, out, budget,
                       tel, tbase, round, budget_state = nil,
                       budget_limit = 0, budget_slot = 0)
  t0 = ccall("__w_clock_ms")
  if round > 0
    # Nothing to resume: this arm refuted during rendering, or won with the
    # late lucky dives, or its rendering never produced a solver.
    return 0 if out.size < 3
    sr = out[2]
    sr.solve_shared_budget(res, base, budget)
    sr.export_telemetry(tel, tbase)
    tel[tbase + 7] = tel[tbase + 7] + (ccall("__w_clock_ms") - t0)
    return 0
  pre.set_stop_cell(stop)
  rendered = pre.run_light_flat(formula)
  return 0 if rendered == nil
  rendered = pre.run_heavy if heavy && rendered["status"] == 0
  return 0 if rendered == nil
  return 0 if wassat_stop_requested?(stop)
  out.push(rendered["stack"])
  out.push(rendered["stats"])
  # A refutation during preprocessing is a real answer: report it the way an
  # arm reports one, so the coordinator needs no second channel for it.
  if rendered["status"] != 0
    res[base] = 0 - 1
    won = wassat_stop_publish(stop, 0 - 1)
    return 0
  # The former late-lucky shot built a complete throwaway solver for every
  # rendering. Across 154 measured races it produced no answer and only added
  # startup/memory pressure, while the early lucky arm already covers the
  # original formula. Go directly from the prepared rendering to useful CDCL.
  s = Wassat.from_flat(nv, rendered, 0)
  s.enable_fixed_caps
  s.set_stop_cell(stop)
  if budget_state != nil
    s.set_shared_conflict_budget(budget_state, budget_limit, budget_slot)
  out.push(s)
  s.solve_shared_budget(res, base, budget)
  s.export_telemetry(tel, tbase)
  tel[tbase + 7] = tel[tbase + 7] + (ccall("__w_clock_ms") - t0)
  0

# ---- the reward signal --------------------------------------------------------
#
# A race arm's terminal signal is "did you win", and it is useless for
# allocation: at most one arm per race ever emits it, and it arrives exactly
# when there is nothing left to allocate. Everything below is therefore scored
# from telemetry an UNFINISHED arm produces, which is the whole difficulty.
#
# All five were MEASURED against the only question that matters — where does
# the arm that goes on to win sit in this metric's ranking at a barrier — and
# all five came back at chance. The numbers are under
# wassat_race_round1_conflicts. They are kept selectable rather than reduced to
# the winner because there is no winner; the next attempt at this should start
# by re-running that study, not by trusting a comment.
#
#   0 tight-rate, conflicts per second over the fast LBD EMA. Work rate divided
#     by work quality: an arm loses by being slow OR by learning garbage. The
#     prior favourite, and no better than chance (0.417 +- 0.100).
#   1 the fast LBD EMA alone, lower better — recent learned-clause tightness,
#     the solver's own restart controller reading its own learning quality.
#   2 propagations per conflict, higher better — reasoning depth per conflict.
#     The metric whose SIGN flipped between two samples of the same instances,
#     which is what established that none of this is signal.
#   3 sharing credit: clauses this arm AUTHORED that other arms installed. The
#     one candidate that is not about the arm's own progress at all — metaflip's
#     delayed credit assignment (lib/metaflip/fleet/lineage.w), where an arm is
#     paid for what its descendants achieved. In a clause-sharing race this is
#     the honest objective, because the race's goal is its own finish time and
#     an arm that helps another arm finish has earned its core. Also chance.
#   4 live learned-clause count. The only metric to clear chance (0.320 +-
#     0.097) and the only one with no mechanism behind it, on one sample, out of
#     ten tried. Treated as noise until someone reproduces it.
#
# Returned in milli-units, and normalised by the round's best arm before it is
# banked, so a banked reward is always 0..1000 whatever the instance or the
# round length. Note that a PREPROCESSING arm's numbers are not comparable with
# a raw arm's — it is solving a smaller formula, so its conflict rate and trail
# depth are on a different scale — which is why only raw arms are ranked
# against each other.
-> wassat_race_arm_score(metric, dconf, dms, dprop, dcredit, learnt, fast_lbd) (i64 i64 i64 i64 i64 i64 i64) i64
  return 0 if dconf <= 0
  # A sub-millisecond slice is charged one millisecond rather than scored zero:
  # an arm that answered its slice too fast to time is the LAST one to call a
  # loser, and a zero here would name it worst and respawn it.
  ms = dms < 1 ? 1 : dms ## i64
  # est[0] is the fast LBD EMA in <<16 fixed point; +1 floors the divisor and
  # keeps a formula whose learned clauses are all unit from dividing by zero.
  lbd = (fast_lbd >> 16) + 1 ## i64
  return (dconf * 1000000) / (ms * lbd) if metric == 0
  return 1000000 / lbd if metric == 1
  return (dprop * 1000) / dconf if metric == 2
  return (dcredit * 1000000) / ms if metric == 3
  learnt

# floor(log2) and integer sqrt: UCB needs a logarithm and a square root, and
# this codebase has neither in integer form. Borrowed from metaflip's GPU role
# scheduler (lib/metaflip/kernels/policy.w), which solves the same problem for
# the same reason — fixed-point integer arithmetic end to end, so an allocation
# is reproducible and testable rather than a float that drifts by platform.
-> wassat_log2_floor(x) (i64) i64
  n = x ## i64
  r = 0 ## i64
  while n > 1
    n = n >> 1
    r += 1
  r

-> wassat_isqrt(x) (i64) i64
  return 0 if x <= 0
  return 1 if x < 4
  g = 1 << ((wassat_log2_floor(x) / 2) + 1) ## i64
  i = 0 ## i64
  while i < 64
    ng = (g + x / g) / 2 ## i64
    return g if ng >= g
    g = ng
    i += 1
  g

# ---- axis-level credit assignment ---------------------------------------------
#
# Credit goes to the AXIS LEVELS a configuration carries, not to the
# configuration as a whole. With eight arms there is exactly ONE sample of each
# full configuration and four of each binary axis level, so per-configuration
# credit is a bandit with one pull per arm — no better than random — while
# per-axis credit has enough samples in a single round to mean something.
#
# Ten slots: branching {evsids, vmtf} | phases {saved, seeded, positive} |
# chrono {off, on} | simplify {none, subst, subst+congruence}.
WASSAT_AXIS_SLOTS = 10

-> wassat_axis_base(axis) (i64) i64
  return 0 if axis == 0
  return 2 if axis == 1
  return 5 if axis == 2
  7

-> wassat_axis_levels(axis) (i64) i64
  return 2 if axis == 0
  return 3 if axis == 1
  return 2 if axis == 2
  3

# Which configuration cell an axis reads: branching 0, phases 1, chrono 3,
# simplify 4 (cell 2 is the phase seed, which is a payload, not a level).
-> wassat_axis_cfg_slot(axis) (i64) i64
  return 0 if axis == 0
  return 1 if axis == 1
  return 3 if axis == 2
  4

# Integer UCB1 in milli-units over one axis. 1386000 is 2*ln(2)*10^6, so
# isqrt(1386000 * log2(N) / n) is 1000*sqrt(2 ln N / n) — the textbook bonus,
# without a float. An untried level is infinitely optimistic, which is what
# forces every level of every axis to be sampled before any of them is trusted.
-> wassat_race_axis_best(axis, rew, cnt) (i64 i64[] i64[]) i64
  b = wassat_axis_base(axis) ## i64
  n = wassat_axis_levels(axis) ## i64
  total = 0 ## i64
  l = 0 ## i64
  while l < n
    total += cnt[b + l]
    l += 1
  total = 2 if total < 2
  best = 0 ## i64
  best_score = 0 - 1 ## i64
  l = 0
  while l < n
    score = 1000000000 ## i64
    if cnt[b + l] > 0
      mean = rew[b + l] / cnt[b + l] ## i64
      score = mean + wassat_isqrt((1386000 * wassat_log2_floor(total)) / cnt[b + l])
    if score > best_score
      best = l
      best_score = score
    l += 1
  best

# Build the configuration a respawned arm takes. `rotate` is metaflip's forced
# rotation (kernels/pool.w: every fourth launch ignores the argmax): without
# it a noisy first round can pin every later respawn to one corner of the
# configuration space and the race stops being a race. The phase seed is ALWAYS
# fresh — a respawned arm that replays a trajectory already in the race has
# bought nothing at all.
-> wassat_race_new_config(cfgs, b, rew, cnt, nrealloc, rotate) (i64[] i64 i64[] i64[] i64 i64)
  if rotate == 1
    # Continue the diversity matrix's own sequence past the arms in play,
    # which walks it onto phase seeds and axis combinations no live arm holds.
    wassat_race_matrix_config(nrealloc, cfgs, b)
    cfgs[b + 2] = 990001 + nrealloc * 15485863 if cfgs[b + 1] == 1
    return 0
  cfgs[b] = wassat_race_axis_best(0, rew, cnt)
  cfgs[b + 1] = wassat_race_axis_best(1, rew, cnt)
  cfgs[b + 3] = wassat_race_axis_best(2, rew, cnt)
  cfgs[b + 4] = wassat_race_axis_best(3, rew, cnt)
  # Level 0 of the phase axis is "saved phases", which for a FRESH solver means
  # the default initial polarity — the incumbent arm 0's own starting point. A
  # respawn onto it buys a duplicate trajectory, so it is promoted to a seeded
  # one. The seed is always fresh for the same reason.
  cfgs[b + 1] = 1 if cfgs[b + 1] == 0
  cfgs[b + 2] = 990001 + nrealloc * 15485863
  0

# Run the race: every raw arm over the flat artifact, plus one arm per
# preprocessed rendering that renders and then solves, all concurrently.
# `budget` caps aggregate race conflicts (0 = unlimited) through a shared
# lock-free ticket pool. Per-round arm slices remain scheduling boundaries,
# not independent copies of the CLI allowance. While the arms are live
# the main thread does nothing but join — inline caches are process-global,
# so the coordinator must not dispatch until every arm has stopped.
#
# ADAPTIVE ALLOCATION. The race runs in rounds separated by a join barrier;
# scoring and reallocation happen at the barrier, on the main thread, with
# every arm stopped. Round 0 is sized (wassat_race_round1_conflicts) so that
# every instance the fixed matrix already decides quickly never reaches a
# barrier at all, and the mechanism costs those families exactly nothing.
#
# Two invariants hold whatever the allocator decides:
#   * arm 0 is never reallocated. With one raw arm it holds the configuration
#     the serial post-probe solve would have used, and a race that REPLACES
#     that configuration can lose outright to the serial path on the instances
#     where it was the right one.
#   * an arm is replaced only when it is losing BADLY (below half the median
#     score), never merely because it is behind. A respawn throws away that
#     arm's learned clauses and pays a fresh from_flat, so churn on a race
#     whose arms are all comparable — which the measurements say is the common
#     case — is a pure loss.
-> wassat_race_run(race, budget)
  nv = race["nv"]
  res = race["res"] ## i64[]
  stop = race["stop"] ## i64[]
  solvers = race["solvers"]
  threads = race["threads"]
  matrix_threads = race["matrix_threads"]
  pre = race["pre"]
  formula = race["formula"]
  tel = race["tel"] ## i64[]
  cfgs = race["cfgs"] ## i64[]
  art = race["art"]
  cap = race["cap"]
  offsets = race["offsets"] ## i64[]
  # A finite CLI cap is one lock-free ticket pool shared by every CDCL
  # implementation in the race. Slot zero is the exact aggregate; each
  # logical arm owns one disjoint contribution slot. Reallocated solvers reuse
  # their logical slot and SLS's optional exact repair uses its fixed slot.
  conflict_budget = nil
  if budget > 0
    conflict_budget = i64[cap + 1]
    a = 0
    while a < threads
      solvers[a].set_shared_conflict_budget(conflict_budget, budget, a + 1)
      a += 1
  race["conflict_budget"] = conflict_budget
  total = threads + pre.size
  # The SLS arm sits at a FIXED slot past both preprocessing slots, so its
  # index does not move with pre_arms. It is deliberately outside `total`:
  # `total` bounds the scoring/reallocation machinery, and a model-only arm
  # has no conflict telemetry to score and nothing to reallocate to.
  sls = race["sls"]
  sls_idx = threads + 2
  sls_base = sls_idx * (nv + 8)
  round_ms = wassat_race_round_ms
  trace = wassat_race_trace?
  # Reallocation needs somebody to reallocate: with one raw arm there is no
  # second configuration to compare against and no arm that may be replaced.
  # Rounds exist ONLY to make reallocation possible, so a race that structurally
  # cannot reallocate does not pay for them — measured on the three instances
  # the policy gives a single raw arm, rounds alone cost 4-6% (smulo016 8.90s ->
  # 9.21s, minand064 6.07s -> 6.43s) buying nothing, because with one arm the
  # barrier is pure idle time at the join. WASSAT_REALLOC=0 keeps the barriers
  # and the telemetry while suppressing the respawn, which is the ablation that
  # separates the cost of the mechanism from its value.
  sliceable = matrix_threads > 1
  realloc = sliceable ? wassat_race_reallocate : 0
  round1 = sliceable ? wassat_race_round1_conflicts : 0
  credit = race["credit"] ## i64[]
  metric = wassat_race_reward_metric
  realloc_every = wassat_race_realloc_every
  live = i64[cap]
  slice = i64[cap]
  spent = i64[cap]
  pcredit = i64[cap]
  prev = i64[cap * WASSAT_TEL_STRIDE]
  score = i64[cap]
  sorted = i64[cap]
  axis_rew = i64[WASSAT_AXIS_SLOTS]
  axis_cnt = i64[WASSAT_AXIS_SLOTS]
  axis_pulls = 0
  nrealloc = 0
  # A scout continuation starts this race with cumulative solver counters.
  # Seed its telemetry baseline before round zero so the scout's work is not
  # scored or charged to the race a second time.
  incumbent_index = race["incumbent_index"]
  if incumbent_index >= 0
    tb = incumbent_index * WASSAT_TEL_STRIDE
    solvers[incumbent_index].export_telemetry(tel, tb)
    k = 0
    while k < WASSAT_TEL_STRIDE
      prev[tb + k] = tel[tb + k]
      k += 1
  a = 0
  while a < total
    live[a] = 1
    slice[a] = round1 == 0 ? budget : round1
    slice[a] = budget if budget > 0 && (slice[a] == 0 || slice[a] > budget)
    a += 1
  round = 0
  running = 1
  while running == 1
    handles = []
    sls_handle = nil
    a = 0
    while a < threads
      if live[a] == 1
        solver = solvers[a]
        base = a * (nv + 8)
        tbase = a * WASSAT_TEL_STRIDE
        arm_slice = slice[a]
        handles.push(Thread.new -> wassat_fast_arm_body_round(solver, res, base, arm_slice, tel, tbase))
      a += 1
    p = 0
    while p < pre.size
      if live[threads + p] == 1
        spec = pre[p]
        pp = spec["pre"]
        heavy = spec["heavy"]
        out = spec["out"]
        base = (threads + p) * (nv + 8)
        tbase = (threads + p) * WASSAT_TEL_STRIDE
        pre_slice = slice[threads + p]
        pre_round = round
        pre_slot = threads + p + 1
        handles.push(Thread.new -> wassat_pre_arm_body(
          pp, formula, nv, res, base, heavy, stop, out, pre_slice, tel,
          tbase, pre_round, conflict_budget, budget, pre_slot
        ))
      p += 1
    if sls.size > 0 && res[sls_base + nv + 3] == 0
      spec = sls[0]
      sflips = spec["flips"]
      sseed = spec["seed"]
      sout = spec["out"]
      sart = spec["art"]
      # Default unbounded races retain the established long walker. Bounded
      # or explicitly rounded races advance it in 200k-flip slices, so a
      # finite CDCL budget can never leave a 200M-flip orphan at the join.
      starget = sflips
      if budget > 0 || round1 > 0
        starget = WASSAT_SLS_REPAIR_PREFIX_FLIPS * (round + 1)
        starget = sflips if starget > sflips || starget < 0
      repair_allowed = race["sls_repair_allowed"] == true
      repair_cap = 0
      if budget > 0
        repair_cap = budget - ccall("__w_arr_load_acq", conflict_budget, 0)
        repair_allowed = false if repair_cap <= 0
      first_sls = sout.empty?
      sls_handle = Thread.new -> wassat_sls_arm_body_round(
        nv, formula, sart, res, sls_base, stop, starget, sflips, sseed,
        sout, first_sls, repair_allowed, repair_cap,
        conflict_budget, budget, sls_idx + 1
      )
    handles.each -> (h)
      z = h.join
    # Join decisive CDCL work FIRST. If this was its final bounded slice (or
    # every live arm retired/stalled), signal the model-only walker before
    # joining it. The old all-handles join could wait behind the walker's full
    # 200M ceiling after every CDCL arm had already returned UNKNOWN.
    if sls_handle != nil
      decisive_now = 0
      a = 0
      while a < total
        st = res[a * (nv + 8)]
        decisive_now = 1 if st == 1 || st == 0 - 1
        a += 1
      cdcl_can_continue = 0
      if decisive_now == 0 && round1 > 0
        a = 0
        while a < total
          if live[a] == 1
            tb = a * WASSAT_TEL_STRIDE
            dconf = tel[tb] - prev[tb]
            next_spent = spent[a] + dconf
            can = res[a * (nv + 8)] != 2 && dconf > 0
            can = false if budget > 0 && next_spent >= budget
            cdcl_can_continue = 1 if can
          a += 1
      if decisive_now == 1 || round1 == 0 || cdcl_can_continue == 0
        z = wassat_stop_cancel(stop)
      z = sls_handle.join
    # ---- barrier: every arm is stopped, the coordinator may dispatch again --
    #
    # Everything from here to the next spawn runs with no worker live, which is
    # the condition the whole design is built around: inline caches are
    # process-global, so the coordinator scores, sorts, allocates and builds
    # replacement solvers HERE and does nothing but join while arms run.
    running = 0
    budget_done = false
    if conflict_budget != nil
      budget_done = ccall("__w_arr_load_acq", conflict_budget, 0) >= budget
    if round1 > 0 && !budget_done
      decided = 0
      a = 0
      while a < total
        st = res[a * (nv + 8)]
        decided = 1 if st == 1 || st == 0 - 1
        a += 1
      decided = 1 if sls.size > 0 && res[sls_base] == 1
      if decided == 0
        # Score the round every arm just finished, and retire the arms that
        # cannot continue: retired by the solver, stuck (no conflict advanced,
        # which is how a preprocessing arm that refuted or won its lucky dives
        # reports "nothing here to resume"), or out of aggregate budget.
        best = 0
        nlive = 0
        nconfig_live = 0
        a = 0
        while a < total
          score[a] = 0
          if live[a] == 1
            tb = a * WASSAT_TEL_STRIDE
            dconf = tel[tb] - prev[tb]
            dms = tel[tb + 7] - prev[tb + 7]
            dprop = tel[tb + 2] - prev[tb + 2]
            dcredit = credit[a] - pcredit[a]
            spent[a] = spent[a] + dconf
            score[a] = wassat_race_arm_score(metric, dconf, dms, dprop, dcredit, tel[tb + 6], tel[tb + 3])
            best = score[a] if a < matrix_threads && score[a] > best
            if trace
              z = ccall("__w_eprint", "c trace r[round] arm[a] conf=[tel[tb]] d=[dconf] ms=[dms] lbdf=[tel[tb + 3] >> 16] lbds=[tel[tb + 4] >> 16] trail=[tel[tb + 5] >> 16] learnt=[tel[tb + 6]] dec=[tel[tb + 1]] prop=[tel[tb + 2]] credit=[credit[a]] score=[score[a]]\n")
            pcredit[a] = credit[a]
            live[a] = 0 if res[a * (nv + 8)] == 2
            live[a] = 0 if dconf <= 0
            live[a] = 0 if budget > 0 && spent[a] >= budget
            if live[a] == 1
              # Each arm's next slice comes from its OWN measured rate, not
              # from a shared conflict count: arms in a diversified race differ
              # by up to 3x in conflicts per second, and a shared slice would
              # make every barrier wait on the slowest arm.
              ms = dms < 1 ? 1 : dms
              rate = (dconf * round_ms) / ms
              slice[a] = rate < 1000 ? 1000 : rate
              slice[a] = budget - spent[a] if budget > 0 && spent[a] + slice[a] > budget
              nlive += 1
              nconfig_live += 1 if a < matrix_threads
            k = 0
            while k < WASSAT_TEL_STRIDE
              prev[tb + k] = tel[tb + k]
              k += 1
          a += 1
        running = 1 if nlive > 0
        if realloc > 0 && best > 0 && nconfig_live > 1
          # Bank each arm's reward against the axis levels its configuration
          # carries, normalised to 0..1000 against the round's best arm so the
          # scale is the same whatever the instance or the round length.
          a = 0
          while a < matrix_threads
            if live[a] == 1
              cb = a * WASSAT_CFG_STRIDE
              r = (score[a] * 1000) / best
              i = 0
              while i < 4
                lvl = wassat_axis_base(i) + cfgs[cb + wassat_axis_cfg_slot(i)]
                axis_rew[lvl] = axis_rew[lvl] + r
                axis_cnt[lvl] = axis_cnt[lvl] + 1
                i += 1
            a += 1
          axis_pulls += 1
          # The median of the live raw arms, and the worst arm that is not the
          # pinned one. `sorted` is reused every round; m is small (<= 64).
          m = 0
          a = 0
          while a < matrix_threads
            if live[a] == 1
              sorted[m] = score[a]
              m += 1
            a += 1
          i = 1
          while i < m
            v = sorted[i]
            j = i - 1
            while j >= 0 && sorted[j] > v
              sorted[j + 1] = sorted[j]
              j -= 1
            sorted[j + 1] = v
            i += 1
          med = m > 0 ? sorted[m / 2] : 0
          worst = 0 - 1
          a = 1
          while a < matrix_threads
            if live[a] == 1 && (worst < 0 || score[a] < score[worst])
              worst = a
            a += 1
          # RATIO mode: losing BADLY, not merely behind. Half the median is the
          # line: on a race whose arms are all within 25% of each other — the
          # common case on every instance measured — nothing is ever replaced
          # and the allocator degenerates to the fixed matrix, which is the
          # intent. RANK mode replaces the worst arm on a fixed cadence
          # whatever the spread, which is the aggressive bracket.
          fire = 0
          fire = 1 if realloc == 1 && med > 0 && score[worst] * 2 < med
          fire = 1 if realloc == 2 && round % realloc_every == realloc_every - 1
          if worst >= 0 && fire == 1
            cb = worst * WASSAT_CFG_STRIDE
            wassat_race_new_config(cfgs, cb, axis_rew, axis_cnt, nrealloc,
                                   nrealloc % 4 == 3 ? 1 : 0)
            ns = Wassat.from_flat(nv, art, 0)
            is_otfs = worst >= race["otfs_index"] && worst < race["otfs_index"] + race["otfs_specialists"]
            ns.enable_otfs if is_otfs
            ns.enable_fixed_caps
            ns.set_stop_cell(stop)
            if conflict_budget != nil
              ns.set_shared_conflict_budget(
                conflict_budget, budget, worst + 1
              )
            ns.enable_sharing(
              race["ring"], race["ring_cap"], race["ring_maxlen"], worst,
              !is_otfs
            )
            ns.set_share_credit(credit) unless is_otfs
            wassat_race_apply_config(ns, cfgs, cb,
                                     art["config"].force_simplify?,
                                     art["config"].use_vmtf(art["raw"] == true))
            solvers[worst] = ns
            # A fresh solver's counters restart at zero, so its telemetry
            # baseline restarts with them. `spent` deliberately does NOT: the
            # aggregate --conflicts cap counts work the race did, not work any
            # one solver object remembers doing.
            tb = worst * WASSAT_TEL_STRIDE
            k = 0
            while k < WASSAT_TEL_STRIDE
              tel[tb + k] = 0
              prev[tb + k] = 0
              k += 1
            # A replacement is a fresh solver, not the scout continuation it
            # may have displaced. Its final conflict count has no old offset.
            offsets[worst] = 0
            slice[worst] = round1
            slice[worst] = budget - spent[worst] if budget > 0 && spent[worst] + slice[worst] > budget
            nrealloc += 1
            if trace
              z = ccall("__w_eprint", "c trace r[round] REALLOC arm[worst] score=[score[worst]] med=[med] -> vmtf=[cfgs[cb]] ph=[cfgs[cb + 1]]/[cfgs[cb + 2]] chrono=[cfgs[cb + 3]] simp=[cfgs[cb + 4]]\n")
    round += 1
  a = 0
  while a < total
    base = a * (nv + 8)
    kind = a < threads ? "raw" : "pre"
    ms = res[base + nv + 5] - res[base + nv + 6]
    wassat_prof_note("race.arm[a] [kind] status=[res[base]] conflicts=[res[base + nv + 4]] ms=[ms]")
    a += 1
  if sls.size > 0
    ms = res[sls_base + nv + 5] - res[sls_base + nv + 6]
    wassat_prof_note("race.arm[sls_idx] sls status=[res[sls_base]] flips=[res[sls_base + nv + 4]] repair_conflicts=[res[sls_base + nv + 7]] repair_won=[res[sls_base + nv + 1]] ms=[ms]")
  status = 0
  winner = -1
  a = 0
  while a < total
    st = res[a * (nv + 8)]
    if st == 0 - 1
      status = 0 - 1
      winner = a
      a = total
    else
      if st == 1 && status == 0
        status = 1
        winner = a
      a += 1
  # A model-only arm cannot beat a refutation, so it is consulted last and
  # only when nothing decisive was found.
  if status == 0 && sls.size > 0 && res[sls_base] == 1
    status = 1
    winner = sls_idx
  model = []
  repair_conflicts = sls.size > 0 ? res[sls_base + nv + 7] : 0
  conflicts = repair_conflicts
  if conflict_budget != nil
    conflicts = ccall("__w_arr_load_acq", conflict_budget, 0)
  if winner >= 0
    base = winner * (nv + 8)
    if winner != sls_idx && conflict_budget == nil
      conflicts += res[base + nv + 4] - offsets[winner]
    if status == 1
      v = 1
      while v <= nv
        model.push(res[base + v] == 1 ? v : 0 - v)
        v += 1
  # The winning arm's model lives in ITS OWN formula's variable space, so the
  # caller must walk the matching elimination stack — "pre_index" says which
  # rendering won (-1 = the raw one). Getting this wrong is caught by the
  # model check against the original formula, never passed off as an answer.
  { "status": status, "model": model, "winner": winner, "conflicts": conflicts,
    "conflict_budget": conflict_budget,
    "pre_index": (winner >= threads && winner != sls_idx) ? winner - threads : 0 - 1,
    "sls_won": winner == sls_idx,
    "sls_repair_won": winner == sls_idx && res[sls_base + nv + 1] == 1,
    "sls_repair_conflicts": repair_conflicts }

-> wassat_run_fast_portfolio(input, threads, share, gpu)
  cnf_text = read_file(input)
  raise "cannot read input formula '[input]'" if cnf_text == nil
  # the NATIVE parser: run_light_flat and wassat_raw_artifact both consume
  # its flat mirrors, which the boxed parser does not produce
  formula = wassat_parse_cnf_native(cnf_text)
  nv = formula["nvars"]

  # Preprocess ONCE, along the SAME route the serial `--fast` path takes:
  # a raw kernel skips the preprocessor entirely, everything else runs the
  # light flat phases and then the heavy subsumption/BVE rounds. Arms then
  # ingest the flat mirrors natively through from_flat, so arm 0 is a
  # faithful replica of the serial solver rather than a weaker cousin —
  # without this the race started from a light-only kernel and lost to
  # `--fast` on uuf250-01 (2.10s against 1.53s) before diversity even had a
  # chance to pay.
  config = WassatConfig.from_lens(nv, formula["flat_lens"], formula["flat_ncl"])
  pre = WassatPreprocess.new(nv, [], WASSAT_PROOF_NONE, formula)
  art = nil
  if config.raw_kernel?
    art = wassat_raw_artifact(formula, nv)
  else
    art = pre.run_light_flat(formula)
    art = pre.run_heavy if art["status"] == 0
  if art["status"] == -1
    << "s UNSATISFIABLE"
    << "c mode: fast-portfolio (preprocessing refuted)"
    exit(20)

  # A busier ring than the raw-kernel race's: this half of the portfolio is
  # unbounded, so exports accumulate for the whole search rather than a
  # short burst, and the gate below is deliberately wider than glue-only.
  # Lapping is harmless (a lost shared clause is a lost hint, not a wrong
  # answer) but wasteful, so the ring holds ~8 drain intervals' worth.
  ring_maxlen = 24
  ring_cap = 32768
  ring = i64[8 + ring_cap * (3 + ring_maxlen)]
  # Export gate. Glue-only (2) is the raw race's setting and leaves the ring
  # nearly empty; this half exports broadly and lets the IMPORT filter below
  # decide what is worth installing, which is the GpuShareSat division of
  # labour. Unfiltered, this gate would be ruinous — measured on uuf250-01
  # at 4 arms, LBD<=12 with no filter takes 187s against 1.06s at LBD<=4.
  share_lbd = 12
  share_lbd = wassat_decimal_in_range("WASSAT_SHARE_LBD", env("WASSAT_SHARE_LBD"), 0, 64) if env("WASSAT_SHARE_LBD") != nil

  # Batched import filtering (GpuShareSat, SAT'21). Each arm keeps a rotating
  # window of assignment snapshots and installs a shared clause only when it
  # would have been FALSE or UNIT under one of them — the clauses that would
  # actually propagate or conflict. Everything else costs a store, two watch
  # appends and a propagation to say nothing.
  #
  # Depth 64 is the measured knee on uuf250-01: conflicts are flat from 64
  # to 1024 (62k vs 65k) while the scan cost is linear in depth, so the
  # deeper windows buy nothing and cost 0.6s. 0 disables the filter and
  # installs everything. Buffers are allocated HERE, on the main thread —
  # worker arms only ever write into their own slice.
  filter_slots = 64
  filter_slots = wassat_decimal_in_range("WASSAT_FILTER", env("WASSAT_FILTER"), 0, 4096) if env("WASSAT_FILTER") != nil
  filter_every = 64
  filter_every = wassat_decimal_in_range("WASSAT_FILTER_EVERY", env("WASSAT_FILTER_EVERY"), 1, 1000000) if env("WASSAT_FILTER_EVERY") != nil
  asg_words = nv / 64 + 2
  asg_sinks = []
  a = 0
  while a < threads
    asg_sinks.push(filter_slots > 0 ? i64[filter_slots * 2 * asg_words + 8] : nil)
    a += 1

  stop = i64[4]
  res = i64[threads * (nv + 8)]

  solvers = []
  a = 0
  while a < threads
    s = Wassat.from_flat(nv, art, 0)
    s.set_share_lbd(share_lbd)
    s.enable_fixed_caps
    s.set_stop_cell(stop)
    s.enable_sharing(ring, ring_cap, ring_maxlen, a) if share
    if filter_slots > 0 && share
      s.set_assignment_sink(asg_sinks[a], asg_words, filter_slots, filter_every)
      s.enable_import_filter
    # Diversity along the axes that measurably move trajectories, the same
    # three the raw-kernel race samples: branching heuristic, initial
    # phases, and chronological backtracking. Arm 0 is the marathon default
    # — the serial path's own configuration — so the race can only improve
    # on it, never lose to it by construction.
    #
    # Odd arms take the heuristic the policy did NOT pick, so both EVSIDS
    # and VMTF are sampled whatever the kernel's shape says.
    if a % 2 == 1
      if config.use_vmtf(art["raw"] == true)
        s.disable_vmtf
      else
        s.enable_vmtf
    grp = a / 2
    s.reseed_phases(1000 + a * 7919) if grp == 1
    s.set_positive_phases if grp == 2
    s.reseed_phases(4242 + a * 104729) if grp == 3
    s.reseed_phases(90001 + a * 15485863) if grp >= 4
    s.enable_chrono if grp % 2 == 1
    solvers.push(s)
    a += 1

  # Materialize before any worker starts; the helper handles both raw and
  # lazily boxed preprocessed artifacts.
  gpu_formula = gpu ? wassat_gpu_formula(art, nv) : nil

  handles = []
  a = 0
  while a < threads
    solver = solvers[a]
    base = a * (nv + 8)
    handles.push(Thread.new -> wassat_fast_arm_body(solver, res, base))
    a += 1

  # The GPU walker fleet races on the COORDINATOR'S thread — which would
  # otherwise sleep in join — so all Metal allocation stays off the worker
  # threads. Models only; a CDCL answer raises the stop cell and the host
  # dispatch loop yields between chunks. Unavailability (no device, no
  # sidecar) degrades to a CPU-only race, never an error.
  gpu_model = []
  if gpu
    metal_path = wassat_metal_path
    begin
      gr = wassat_sls_gpu_solve(gpu_formula, 512, 2000000000, 9001, 48, metal_path, stop)
      if gr["sat"]
        gpu_model = gr["model"]
        won = wassat_stop_publish(stop, 1)
    rescue e
      << "c arm gpu-sls unavailable: [e]"

  handles.each -> (h)
    z = h.join

  # collect: any UNSAT wins (trusted by the --fast contract); else any SAT
  # model is reconstructed through the elimination stack and must satisfy
  # the ORIGINAL formula; else everyone stopped or retired.
  verdict = "UNKNOWN"
  winner = -1
  a = 0
  while a < threads
    st = res[a * (nv + 8)]
    if st == 0 - 1
      verdict = "UNSAT"
      winner = a
      a = threads
    else
      winner = a if st == 1 && verdict == "UNKNOWN"
      verdict = "SAT" if st == 1 && verdict == "UNKNOWN"
      a += 1

  # a CDCL UNSAT beats everything; otherwise any model wins — the GPU's
  # counts as one more arm
  if verdict == "UNKNOWN" && !gpu_model.empty?
    verdict = "SAT"
    winner = 0 - 2

  if verdict == "SAT"
    reduced_model = gpu_model
    if winner >= 0
      base = winner * (nv + 8)
      reduced_model = []
      v = 1
      while v <= nv
        reduced_model.push(res[base + v] == 1 ? v : 0 - v)
        v += 1
    model = wassat_reconstruct_model(art["stack"], reduced_model, nv)
    unless wassat_model_satisfies?(formula, model)
      raise "internal error: winning arm's model does not satisfy the original formula"
    print(wassat_sat_text(model))
  elsif verdict == "UNSAT"
    << "s UNSATISFIABLE"
  else
    << "s UNKNOWN"
  << "c mode: fast-portfolio threads=[threads] gpu=[gpu]"
  << "c winner: arm[winner]" if winner >= 0
  << "c winner: gpu-sls" if winner == 0 - 2
  a = 0
  while a < threads
    base = a * (nv + 8)
    ms = res[base + nv + 5] - res[base + nv + 6]
    << "c arm[a]: status=[res[base]] conflicts=[res[base + nv + 4]] ms=[ms] exported=[res[base + nv + 1]] imported=[res[base + nv + 2]] dropped=[res[base + nv + 3]] filtered=[res[base + nv + 7]]"
    a += 1
  # SAT Competition convention, after every diagnostic line is out: 10 =
  # SATISFIABLE, 20 = UNSATISFIABLE, 0 = UNKNOWN.
  if verdict == "SAT"
    exit(10)
  if verdict == "UNSAT"
    exit(20)
  0

# GPU SLS consumes boxed clauses, but raw and large lazy artifacts deliberately
# leave art["clauses"] empty. Rebuild only the live selected clauses from the
# flat artifact. MAIN THREAD ONLY: calling this after worker spawn would race
# boxed inline caches in addition to feeding raw artifacts an empty formula.
-> wassat_gpu_formula(art, nv)
  clauses = art["clauses"]
  if clauses.empty? && art["fncl"] > 0
    clauses = []
    synthetic = art["fsynth"] == true
    ci = 0
    while ci < art["fncl"]
      alive = synthetic
      alive = art["falive"][ci] == 1 && art["ftaut"][ci] == 0 unless synthetic
      if alive
        clause = []
        j = 0
        while j < art["fcl"][ci]
          clause.push(art["fla"][art["fcs"][ci] + j])
          j += 1
        clauses.push(clause)
      ci += 1
    art["clauses"] = clauses
  { "nvars": nv, "clauses": clauses }

# ---- portfolio CLI -----------------------------------------------------------
#
# `wassat portfolio <cnf> --proof <path> [--dir <race dir>]`
-> wassat_run_portfolio(args)
  input = nil
  proof_out = nil
  race_dir = nil
  fast = false
  share = true
  gpu = false
  threads = 4
  timeout_ms = 300000
  seen = {}
  i = 0
  while i < args.size
    flag = args[i]
    if flag == "--proof" || flag == "--dir" || flag == "--threads" || flag == "--timeout-ms"
      raise "duplicate portfolio option: [flag]" if seen[flag] == true
      seen[flag] = true
      raise "missing value after [flag]" if i + 1 >= args.size
      if flag == "--proof"
        proof_out = args[i + 1]
      elsif flag == "--threads"
        value = args[i + 1]
        threads = wassat_decimal_in_range("--threads", value, 1, 64)
      elsif flag == "--timeout-ms"
        value = args[i + 1]
        timeout_ms = wassat_decimal_in_range("--timeout-ms", value, 1, 86400000)
      else
        race_dir = args[i + 1]
      i += 2
    elsif flag == "--fast"
      raise "duplicate portfolio option: [flag]" if seen[flag] == true
      seen[flag] = true
      fast = true
      i += 1
    elsif flag == "--no-share"
      raise "duplicate portfolio option: [flag]" if seen[flag] == true
      seen[flag] = true
      share = false
      i += 1
    elsif flag == "--gpu"
      raise "duplicate portfolio option: [flag]" if seen[flag] == true
      seen[flag] = true
      gpu = true
      i += 1
    elsif flag.starts_with?("--")
      raise "unknown portfolio option: [flag]"
    else
      raise "unexpected extra argument '[flag]'" unless input == nil
      input = flag
      i += 1
  raise "missing input formula" if input == nil
  raise "--fast forgoes certificates; drop --fast or --proof" if fast && proof_out != nil
  raise "--gpu requires --fast (the GPU arm returns models, not proofs)" if gpu && !fast
  return wassat_run_fast_portfolio(input, threads, share, gpu) if fast
  raise "portfolio proof mode requires --proof <path>" if proof_out == nil
  raise "portfolio proof must be written to a file, not stdout" if proof_out == "-"
  if race_dir == nil
    race_dir = ccall("__w_mkdtemp", "wassat-race")
  else
    raise "cannot create portfolio work root '[race_dir]'" unless ccall("__w_mkdir_p", race_dir)
    race_dir = ccall("__w_mkdtemp_in", race_dir, "run")
  raise "cannot create unique portfolio work directory" if race_dir == nil

  arms = [
    { "kind": WASSAT_ARM_MARATHON, "label": "marathon", "seed": 0 },
    { "kind": WASSAT_ARM_GARDEN, "label": "garden", "seed": 42 },
    { "kind": WASSAT_ARM_SLS, "label": "sls", "seed": 7 }
  ]
  port = WassatPortfolio.new(input, race_dir, arms, timeout_ms)
  r = nil
  begin
    r = port.run(proof_out)
  rescue e
    port.cleanup
    raise e
  port.cleanup
  if r["verdict"] == "SAT"
    print(wassat_sat_text(r["model"]))
  elsif r["verdict"] == "UNSAT"
    << "s UNSATISFIABLE"
  else
    << "s UNKNOWN"
  << "c mode: portfolio"
  << "c winner: [r["winner"]]"
  r["arms"].each -> (line)
    << "c arm: [line]"
  # SAT Competition convention, after every diagnostic line is out: 10 =
  # SATISFIABLE, 20 = UNSATISFIABLE, 0 = UNKNOWN (deadline included).
  if r["verdict"] == "SAT"
    exit(10)
  if r["verdict"] == "UNSAT"
    exit(20)
  0
