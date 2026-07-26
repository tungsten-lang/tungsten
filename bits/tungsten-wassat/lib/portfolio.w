# Portfolio coordinator (Phase 3, --proof half): a process race.
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
    pre = WassatPreprocess.new(formula["nvars"], formula["clauses"], WASSAT_PROOF_WRAT)
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
    sp = Wassat.new(formula["nvars"], formula["clauses"], WASSAT_PROOF_NONE, 0)
    pr = sp.solve_budget(2000000)
    if pr["status"] == 1
      raise "status write failed" unless write_file(status_path, pr["model"].join(" ") + " 0\n")
      exit(10)
    elsif pr["status"] == 0 - 1
      raise "status write failed" unless write_file(status_path, "UNSAT\n")
      exit(20)
    exit(3)

  s = Wassat.new(formula["nvars"], formula["clauses"], WASSAT_PROOF_WRAT, 0)
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

# Budgeted arm body: each arm stops UNKNOWN after `budget` conflicts (0 =
# unlimited) so the raw-kernel race honours the aggregate --conflicts cap.
-> wassat_fast_arm_body_budget(solver, res, base, budget)
  solver.solve_shared_budget(res, base, budget)

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
  s = Wassat.from_flat(nv, art, 0)
  s.set_stop_cell(stop)
  s.lucky_shared(res, base)

# The bounded CDCL scout, as an arm. It is the same search the coordinator used
# to run inline: its own solver over the same artifact, stopped by conflict cap
# (and, off the raw path, by wall clock). It runs beside the lucky arm so that
# neither pays for the other — a lucky win stops it through the shared cell,
# and a lucky miss leaves its trajectory bit-identical to the serial one.
#
# `out` is its private channel for the boxed result: the coordinator reports
# conflicts, decisions and propagations from it.
-> wassat_scout_arm_body(nv, art, stop, cap, wall, raw, simplify, out)
  s = Wassat.from_flat(nv, art, 0)
  s.set_stop_cell(stop)
  s.simplify_raw if simplify
  t0 = ccall("__w_clock_ms")
  slice = cap < 512 ? cap : 512
  spr = s.solve_budget(slice)
  # The wall-clock cap bounds a miss on kernels whose conflicts are expensive,
  # but it makes the outcome depend on machine load: on bmc-ibm-10 the scout
  # decides at 1,733 conflicts when quiet and falls off a cliff to a full
  # 11k-conflict main solve when busy. A raw kernel's scout is already bounded
  # by its conflict cap, so it runs on conflicts alone and is reproducible.
  while spr["status"] == 0 && spr["conflicts"] < cap && stop[0] == 0 && (raw || ccall("__w_clock_ms") - t0 < wall)
    rem = cap - spr["conflicts"]
    slice = rem < 512 ? rem : 512
    spr = s.solve_budget(slice)
  out.push(spr)
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
-> wassat_race_build(nv, art, threads, formula)
  # Capacity for the raw arms plus the two preprocessed renderings, allocated
  # once: `res` is addressed by arm index and must not move after an arm has
  # a pointer into it.
  cap = threads + 2
  stop = i64[4]
  res = i64[cap * (nv + 8)]
  ring_maxlen = 24
  ring_cap = 4096
  ring = i64[8 + ring_cap * (3 + ring_maxlen)]
  solvers = []
  a = 0
  while a < threads
    s = Wassat.from_flat(nv, art, 0)
    s.enable_fixed_caps
    s.set_stop_cell(stop)
    # A lone raw arm has nobody to share with — the preprocessing arms solve
    # DIFFERENT formulas and must never take its clauses — so it keeps the
    # export path out of its inner loop entirely.
    s.enable_sharing(ring, ring_cap, ring_maxlen, a) if threads > 1
    if threads == 1
      # Sole raw arm: take the configuration the serial post-probe solve
      # would have used, so adding a preprocessing arm changes only what
      # runs BESIDE the raw search and never the raw trajectory itself.
      s.enable_chrono
      s.simplify_raw if art["config"].force_simplify?
    else
      s.disable_vmtf if a % 2 == 1
      grp = a / 2
      # arm 0 would exactly replay the serial probe's already-failed
      # trajectory (same heuristic, same phases) — give it a fresh basin
      s.reseed_phases(777) if a == 0
      s.reseed_phases(1000 + a * 7919) if grp == 1
      s.reseed_phases(4242 + a * 104729) if grp == 3
      s.set_positive_phases if grp == 2
      # Chronological backtracking on half the arms: it is worth ~3.5x on
      # this instance class when it fits the trajectory and costs when it
      # does not, which is exactly what a race is for — take the min rather
      # than guess which side the instance is on.
      s.enable_chrono if grp % 2 == 1
      # Fifth diversity axis: congruence closure + equivalent-literal
      # substitution against the arm's own arena. Deterministic single-arm
      # measurement on the bmc family: ibm-11 11,940 -> 4,734 conflicts and
      # ibm-13 20,350 -> 9,238 with it, against ibm-12 7,162 -> 15,868. A
      # symmetric win and loss of the same size on the same family is the
      # definition of a race axis — take the min rather than pick a side.
      # Arms 1, 2, 5, 6 draw one from each of the four existing groups, so
      # the axis stays decorrelated from phases, VMTF and chronological
      # backtracking instead of piggybacking on one of them.
      s.simplify_raw_mode(0) if a % 4 == 1
      s.simplify_raw_mode(1) if a % 4 == 2
      s.simplify_raw if a % 4 != 1 && a % 4 != 2 && art["config"].force_simplify?
    solvers.push(s)
    a += 1
  { "nv": nv, "solvers": solvers, "res": res, "stop": stop, "threads": threads,
    "cap": cap, "pre": [], "formula": formula }

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
# `out` is this arm's private two-slot channel back to the coordinator: the
# elimination stack its model must be reconstructed through, and the stats to
# report. Private per arm, so pushing to it needs no synchronisation.
-> wassat_pre_arm_body(pre, formula, nv, res, base, heavy, stop, out, budget)
  rendered = pre.run_light_flat(formula)
  rendered = pre.run_heavy if heavy && rendered["status"] == 0
  out.push(rendered["stack"])
  out.push(rendered["stats"])
  # A refutation during preprocessing is a real answer: report it the way an
  # arm reports one, so the coordinator needs no second channel for it.
  if rendered["status"] != 0
    res[base] = 0 - 1
    stop[1] = 0 - 1
    stop[0] = 1
    return 0
  # kissat's LATE lucky shot (search.c: luckylate, after preprocessing), taken
  # here by the arm that did the rendering rather than by an arm of its own.
  # The rendering exists only inside this thread — handing it to a separate arm
  # would mean either a synchronised handoff or a second preprocessor rendering
  # the same formula twice — so the arm that produced it takes its own shot on
  # it, and the coordinator needs no new channel: a win lands in this arm's
  # result slot and is reconstructed through this arm's elimination stack,
  # exactly like a search win. The dives get their own solver so that a miss
  # leaves the arm's search trajectory bit-identical to what it would have been.
  if stop[0] == 0
    ls = Wassat.from_flat(nv, rendered, 0)
    ls.set_stop_cell(stop)
    ls.lucky_shared(res, base)
    return 0 if res[base] != 0
  s = Wassat.from_flat(nv, rendered, 0)
  s.enable_fixed_caps
  s.set_stop_cell(stop)
  s.solve_shared_budget(res, base, budget)

# Run the race: every raw arm over the flat artifact, plus one arm per
# preprocessed rendering that renders and then solves, all concurrently.
# `budget` caps each arm's conflicts (0 = unlimited). While the arms are live
# the main thread does nothing but join — inline caches are process-global,
# so the coordinator must not dispatch until every arm has stopped.
-> wassat_race_run(race, budget)
  nv = race["nv"]
  res = race["res"]
  stop = race["stop"]
  solvers = race["solvers"]
  threads = race["threads"]
  pre = race["pre"]
  formula = race["formula"]
  total = threads + pre.size
  handles = []
  a = 0
  while a < threads
    solver = solvers[a]
    base = a * (nv + 8)
    handles.push(Thread.new -> wassat_fast_arm_body_budget(solver, res, base, budget))
    a += 1
  p = 0
  while p < pre.size
    spec = pre[p]
    pp = spec["pre"]
    heavy = spec["heavy"]
    out = spec["out"]
    base = (threads + p) * (nv + 8)
    handles.push(Thread.new -> wassat_pre_arm_body(pp, formula, nv, res, base, heavy, stop, out, budget))
    p += 1
  handles.each -> (h)
    z = h.join
  a = 0
  while a < total
    base = a * (nv + 8)
    kind = a < threads ? "raw" : "pre"
    ms = res[base + nv + 5] - res[base + nv + 6]
    wassat_prof_note("race.arm[a] [kind] status=[res[base]] conflicts=[res[base + nv + 4]] ms=[ms]")
    a += 1
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
  model = []
  conflicts = 0
  if winner >= 0
    base = winner * (nv + 8)
    conflicts = res[base + nv + 4]
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
    "pre_index": winner >= threads ? winner - threads : 0 - 1 }

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
  config = WassatConfig.new(nv, formula["clauses"])
  pre = WassatPreprocess.new(nv, formula["clauses"], WASSAT_PROOF_NONE)
  art = nil
  if config.raw_kernel?
    art = wassat_raw_artifact(formula, nv)
  else
    art = pre.run_light_flat(formula)
    art = pre.run_heavy if art["status"] == 0
  if art["status"] == -1
    << "s UNSATISFIABLE"
    << "c mode: fast-portfolio (preprocessing refuted)"
    return 0

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
    reduced = { "nvars": nv, "clauses": art["clauses"] }
    metal_path = wassat_metal_path
    begin
      gr = wassat_sls_gpu_solve(reduced, 512, 2000000000, 9001, 48, metal_path, stop)
      if gr["sat"]
        gpu_model = gr["model"]
        stop[0] = 1
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
    print("s SATISFIABLE\nv " + model.join(" ") + " 0\n")
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
  0

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
    print("s SATISFIABLE\nv " + r["model"].join(" ") + " 0\n")
  elsif r["verdict"] == "UNSAT"
    << "s UNSATISFIABLE"
  else
    << "s UNKNOWN"
  << "c mode: portfolio"
  << "c winner: [r["winner"]]"
  r["arms"].each -> (line)
    << "c arm: [line]"
  0
