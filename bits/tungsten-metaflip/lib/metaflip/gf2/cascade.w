# The drivers of the record hunt's cascade: which scoreboard witnesses to project, the projection screen, which children to walk, the
# parallel walk screen and the iterative deepening. Ports of the campaign's scripts next_parents.py, project_screen.py,
# pick_children.py, sweep.py and iterate.py (they lived in the campaign's working directory; copies are in tools/campaign/ with
# the machine-specific paths they ran with).
#
#   Cascade.next_parents(board, out, logs, kinds)          the scoreboard witnesses of the given kinds whose file no log has projected
#                                                          yet, lowest rank first, written to `out`; returns the summary line
#   Cascade.project_screen(seeds, out, options)            every parent's projection children (13 bases, `per_shape` 1) as MFW1
#                                                          files in options["mfw_dir"], one JSON row per child in `out` (resumed)
#   Cascade.pick_children(proj, board, out, tolerance, options)
#                                                          per child shape the lowest-rank projection that beats our witness and
#                                                          is within `tolerance` above the best listed rank in any ring; returns
#                                                          the summary line
#   Cascade.sweep(seeds, out, options)                     the compiled directed walker over exact seeds, in parallel; one JSON
#                                                          row per walk in `out` (resumed)
#   Cascade.iterate(seeds, log, options)                   walk each seed's current best until `patience` rounds stall
#
# options: lille, catalog, fmm_repo, fmm_revision, extra_repo (the public tables, as of RecordBoard.public_tables), mfw_dir, walker, steps,
# jobs, worker (the command that screens one parent), nonce_base, filter (a file of shapes), repeats, walks_per_round, patience, and
# optionally lines (an Array that collects the printed lines).
#
# Differences from the originals: the projection screen runs each parent in a process of its own when options["worker"] is given (the
# tool does: like the original's process pool, and the memory of a parent is returned when its process ends; the log is then in the
# order the processes finish); the parallel walks of sweep are processes (the original uses threads that run processes); iterate
# runs the rounds of all shapes in lock step, so the rows of one shape come in the original's order but the rows of different
# shapes are not interleaved as they happen to finish; a parent that cannot be decoded is reported as `ERROR <file> <message>`
# (the original prints the Python repr of its exception); the public tables come from the options, not from a module of the
# working directory.
use scheme
use derive
use projection_walks
use record_board
use public_ternary
use jsonx
use fsx
use procx
use textx
use floatx

+ Cascade
  -> .say(options, line)
    lines = options["lines"]
    if lines != nil
      lines.push(line)
    else
      << line

  # The rows of a JSON-lines file, one JSON value per line (a blank line is an error, as for the original's json.loads).
  -> .rows_of(path)
    Textx.splitlines(Fsx.read(path)).map -> (line)
      Jsonx.loads(line)

  -> .shape_text(shape)
    shape.map(-> (d) d.to_s).join("x")

  # {"NxMxP" (sorted) => best listed rank in any ring} (the second table of the scoreboard's public tables).
  -> .public_ranks(options)
    Metaflip:Gf2:RecordBoard.public_tables(options["lille"], options["catalog"], options["fmm_repo"], options["fmm_revision"], options["extra_repo"])[1]

  # ---- next_parents -------------------------------------------------------------------------------------------------

  -> .next_parents(board_path, out_path, logs, kinds)
    done = {}
    logs.each -> (log)
      Cascade.rows_of(log).each -> (row)
        done[row["parent"]] = true
    parents = []
    Jsonx.load(board_path).each -> (row)
      if kinds.include?(row["kind"]) && !done.key?(row["path"])
        parents.push({"shape" => row["shape"], "canonical" => row["shape"], "gf2_rank" => row["rank"], "mfw" => row["path"], "kind" => row["kind"]})
    ordered = Textx.sort_by(parents) -> (parent) parent["gf2_rank"]
    Fsx.write(out_path, Jsonx.dumps(ordered, indent: 1))
    ordered.size.to_s + " new parents (" + done.size.to_s + " already projected)"

  # ---- project_screen -----------------------------------------------------------------------------------------------

  # The rows of one parent: its projection children, exact-checked, as files in options["mfw_dir"].
  -> .screen_one(seed, public, options)
    path = seed["mfw"]
    text = Metaflip:Gf2:RecordBoard.load(path)
    ProjectionWalks.fail("cannot read " + path) if text == nil
    scheme = Metaflip:Gf2:RecordBoard.decode_scheme(path, text)
    ProjectionWalks.fail("no orientation verifies: " + path) if scheme == nil
    shape = [scheme.n, scheme.m, scheme.p]
    terms = scheme.terms
    parent_sha = Digest.sha256(scheme.blob)
    rows = ProjectionWalks.proposals(shape, terms, public, 1)
    rows.map -> (row)
      ProjectionWalks.check(ProjectionWalks.exact?(row["shape"], row["terms"]), "projection child is not exact")
      name = Cascade.shape_text(row["shape"]) + "_r" + row["rank"].to_s + "_" + row["sha256"].slice(0, 10) + ".mfw"
      file = Fsx.join(options["mfw_dir"], name)
      Fsx.write(file, row["raw"]) if !Fsx.regular?(file)
      {"parent" => path, "parent_sha256" => parent_sha, "parent_rank" => terms.size, "shape" => Cascade.shape_text(row["shape"]), "rank" => row["rank"], "mode" => row["mode"], "axis" => row["axis"], "coordinate" => row["coordinate"], "lille" => row["public_rank"], "mfw" => file}

  # The rows of one parent as the screen logs them (a parent without a child gets one row without a shape), and the lines it prints.
  -> .record_screen(seed, rows, problem, out_path, options)
    if problem != nil
      Cascade.say(options, "ERROR " + seed["mfw"] + " " + problem)
    else
      logged = rows
      logged = [{"parent" => seed["mfw"], "shape" => nil}] if rows.size == 0
      logged.each -> (row)
        Fsx.append(out_path, Jsonx.dumps(row) + "\n")
      logged.each -> (row)
        if row["shape"] != nil && row["rank"] < row["lille"]
          Cascade.say(options, "CHILD-BELOW-LILLE " + row["shape"] + " " + row["rank"].to_s + " lille " + row["lille"].to_s)
    nil

  # The last line of a worker's standard error, for the ERROR line.
  -> .last_line(text)
    lines = Textx.splitlines(text.strip)
    lines.size == 0 ? "" : lines.last

  # The arguments that make a worker screen one parent: options["worker"] (the command, e.g. [binary, "screen-one"]) then these.
  -> .worker_argv(seed, options)
    argv = options["worker"] + [seed["mfw"], "--mfw-dir", options["mfw_dir"], "--lille", options["lille"], "--fmm-revision", options["fmm_revision"]]
    argv = argv + ["--catalog", options["catalog"]] if options["catalog"] != nil
    argv = argv + ["--fmm-repo", options["fmm_repo"]] if options["fmm_repo"] != nil
    options["extra_repo"].each -> (extra)
      argv = argv + ["--extra-repo", extra]
    argv

  # Screens the parents of a JSON file. With options["worker"] every parent is screened by a process of its own, options["jobs"] at
  # a time (the memory of a parent is then returned when its process ends, and the log is in the order the processes finish, as the
  # original's process pool wrote it); without, one after the other in this process.
  -> .project_screen(seeds_path, out_path, options)
    doc = Jsonx.load(seeds_path)
    seeds = type(doc) == "Hash" ? doc["seeds"] : doc
    Fsx.mkdir(options["mfw_dir"], parents: true, exist_ok: true)
    done = {}
    if Fsx.regular?(out_path)
      Cascade.rows_of(out_path).each -> (row)
        done[row["parent"]] = true
    todo = seeds.select(-> (seed) !done.key?(seed["mfw"]))
    Cascade.say(options, todo.size.to_s + " parents")
    Fsx.append(out_path, "") if !Fsx.regular?(out_path)
    if options["worker"] == nil
      public = Cascade.public_ranks(options)
      todo.each -> (seed)
        rows = nil
        problem = nil
        begin
          rows = Cascade.screen_one(seed, public, options)
        rescue failure
          problem = failure.message.to_s
        Cascade.record_screen(seed, rows, problem, out_path, options)
    else
      results = todo.map(-> (seed) nil)
      handled = todo.map(-> (seed) false)
      running = []
      started = 0
      while started < todo.size || running.size > 0
        while started < todo.size && running.size < options["jobs"]
          running.push(Procx.launch(started, Cascade.worker_argv(todo[started], options), nil, nil))
          started += 1
        indices = running.map(-> (entry) entry[0])
        running = Procx.reap(running, results)
        indices.each -> (index)
          if results[index] != nil && !handled[index]
            handled[index] = true
            result = results[index]
            if result.status == 0
              Cascade.record_screen(todo[index], Jsonx.loads(result.out), nil, out_path, options)
            else
              Cascade.record_screen(todo[index], nil, Cascade.last_line(result.err + result.out), out_path, options)
    nil

  # ---- pick_children ------------------------------------------------------------------------------------------------

  -> .key_of(shape_text)
    Metaflip:Gf2:RecordBoard.sorted_key(shape_text.split("x").map(-> (d) d.to_i))

  # Per canonical child shape the lowest-rank projection when it beats our witness (or we have none) and its rank is at most
  # (1 + tolerance) times the best listed rank in any ring.
  -> .pick_children(proj_path, board_path, out_path, tolerance_text, options)
    tolerance = Floatx.parse(tolerance_text)
    listed = Cascade.public_ranks(options)
    board = {}
    Jsonx.load(board_path).each -> (row)
      board[Cascade.key_of(row["shape"])] = row["rank"]
    best = {}
    Cascade.rows_of(proj_path).each -> (row)
      if row["shape"] != nil && row["shape"] != ""
        key = Cascade.key_of(row["shape"])
        best[key] = row if !best.key?(key) || row["rank"] < best[key]["rank"]
    order = Textx.sort_by(best.keys) -> (key)
      dims = key.split("x").map(-> (d) d.to_i)
      [dims[0], dims[1], dims[2]]
    seeds = []
    no_gain = 0
    too_far = 0
    order.each -> (key)
      row = best[key]
      ProjectionWalks.fail("no listed rank for " + key) if !listed.key?(key)
      public = listed[key]
      if board.key?(key) && row["rank"] >= board[key]
        no_gain += 1
      elsif row["rank"] > public * (1 + tolerance)
        too_far += 1
      else
        raw = Fsx.read(row["mfw"])
        seeds.push({"shape" => row["shape"], "canonical" => key, "gf2_rank" => row["rank"], "mfw" => row["mfw"], "mfw_sha256" => Digest.sha256(raw), "public" => public, "board" => board[key], "parent" => row["parent"], "mode" => row["mode"], "axis" => row["axis"], "coordinate" => row["coordinate"]})
    Fsx.write(out_path, Jsonx.dumps(seeds, indent: 1))
    below = seeds.select(-> (seed) seed["gf2_rank"] < seed["public"]).size
    best.size.to_s + " child shapes; " + no_gain.to_s + " no gain over board; " + too_far.to_s + " beyond " + Textx.percent(tolerance, 0) + " of public; " + seeds.size.to_s + " selected (" + below.to_s + " already below every listed rank)"

  # ---- the walker ---------------------------------------------------------------------------------------------------

  # [seed_rank, rank, moves, accepted, no_pair, escapes] of the walker's result line, or nil.
  -> .result_numbers(text)
    Metaflip:Gf2:PublicTernary.parse_result(text)

  # ---- sweep --------------------------------------------------------------------------------------------------------

  -> .sweep_row(seed, steps, nonce, out, result)
    row = {"shape" => seed["shape"], "canonical" => seed["canonical"], "seed" => seed["mfw"], "steps" => steps, "nonce" => nonce, "returncode" => result.status}
    numbers = Cascade.result_numbers(result.out)
    if numbers != nil && result.status == 0
      row["seed_rank"] = numbers[0]
      row["rank"] = numbers[1]
      row["moves"] = numbers[2]
      row["escapes"] = numbers[5]
      row["output"] = out
    else
      text = result.out + result.err
      row["error"] = text.size > 400 ? text.slice(text.size - 400, 400) : text
    row

  -> .sweep(seeds_path, out_path, options)
    doc = Jsonx.load(seeds_path)
    seeds = type(doc) == "Hash" ? doc["seeds"] : doc
    if options["filter"] != nil
      keep = {}
      Textx.words(Fsx.read(options["filter"])).each -> (word)
        keep[word] = true
      seeds = seeds.select(-> (seed) keep.key?(seed["shape"]) || keep.key?(seed["canonical"]))
    outdir = Fsx.join(Fsx.dirname(out_path), Fsx.stem(out_path) + "_mfw")
    Fsx.mkdir(outdir, parents: true, exist_ok: true)
    done = {}
    if Fsx.regular?(out_path)
      Cascade.rows_of(out_path).each -> (row)
        done[row["seed"] + "|" + row["nonce"].to_s + "|" + row["steps"].to_s] = true
    ordered = Textx.sort_by(seeds) -> (seed) seed["gf2_rank"]
    work = []
    (0...options["repeats"]).each -> (repeat)
      ordered.each -> (seed)
        nonce = options["nonce_base"] + repeat * 7919 + Textx.crc32(seed["shape"]) % 1000003
        work.push([seed, nonce]) if !done.key?(seed["mfw"] + "|" + nonce.to_s + "|" + options["steps"].to_s)
    Cascade.say(options, work.size.to_s + " walks queued")
    Fsx.append(out_path, "") if !Fsx.regular?(out_path)
    jobs = work.map -> (item)
      seed = item[0]
      [seed, item[1], Fsx.join(outdir, seed["shape"] + "_r" + seed["gf2_rank"].to_s + "_n" + item[1].to_s + "_s" + options["steps"].to_s + ".mfw")]
    results = jobs.map(-> (job) nil)
    handled = jobs.map(-> (job) false)
    running = []
    started = 0
    while started < jobs.size || running.size > 0
      while started < jobs.size && running.size < options["jobs"]
        job = jobs[started]
        Fsx.unlink(job[2], missing_ok: true)
        running.push(Procx.launch(started, [options["walker"], job[0]["shape"], job[0]["mfw"], job[2], options["steps"].to_s, job[1].to_s], nil, nil))
        started += 1
      indices = running.map(-> (entry) entry[0])
      running = Procx.reap(running, results)
      indices.each -> (index)
        if results[index] != nil && !handled[index]
          handled[index] = true
          job = jobs[index]
          row = Cascade.sweep_row(job[0], options["steps"], job[1], job[2], results[index])
          Fsx.append(out_path, Jsonx.dumps(row) + "\n")
          if row.key?("rank") && row["rank"] < row["seed_rank"]
            Cascade.say(options, "DROP " + row["shape"] + " " + row["seed_rank"].to_s + " -> " + row["rank"].to_s)
          elsif row.key?("error")
            text = row["error"]
            Cascade.say(options, "ERROR " + row["shape"] + " " + (text.size > 200 ? text.slice(text.size - 200, 200) : text))
    nil

  # ---- iterate ------------------------------------------------------------------------------------------------------

  # One round of one shape: the rows of its walks (in nonce order) and the lowest [rank, path] of the round, or nil.
  -> .round_rows(state, results, nonces, options, outputs)
    rows = []
    found = []
    nonces.each_with_index -> (nonce, at)
      seed = state["seed"]
      parent = state["best_path"]
      row = {"shape" => seed["shape"], "canonical" => seed["canonical"], "round" => state["round"], "nonce" => nonce, "steps" => options["steps"], "parent" => parent, "parent_sha256" => Digest.sha256(Fsx.read(parent))}
      result = results[at]
      numbers = result.status == 0 ? Cascade.result_numbers(result.out) : nil
      if numbers == nil
        text = result.out + result.err
        row["error"] = text.size > 300 ? text.slice(text.size - 300, 300) : text
      else
        row["parent_rank"] = state["best_rank"]
        row["rank"] = numbers[1]
        row["output"] = outputs[at]
        row["sha256"] = Digest.sha256(Fsx.read(outputs[at]))
        found.push([numbers[1], outputs[at]])
      rows.push(row)
    low = nil
    found.each -> (entry)
      low = entry if low == nil || entry[0] < low[0]
    [rows, low]

  -> .iterate(seeds_path, log_path, options)
    seeds = Jsonx.load(seeds_path)
    outdir = Fsx.join(Fsx.dirname(log_path), Fsx.stem(log_path) + "_mfw")
    Fsx.mkdir(outdir, parents: true, exist_ok: true)
    states = []
    seeds.each_with_index -> (seed, index)
      states.push({"index" => index, "seed" => seed, "best_rank" => seed["gf2_rank"], "best_path" => seed["mfw"], "stall" => 0, "round" => 0, "done" => false})
    active = states.select(-> (state) state["stall"] < options["patience"])
    states.each -> (state)
      if state["stall"] >= options["patience"]
        Cascade.say(options, "DONE " + state["seed"]["shape"] + " " + state["best_rank"].to_s)
        state["done"] = true
    while active.size > 0
      plans = active.map -> (state)
        nonces = (0...options["walks_per_round"]).map(-> (k) options["nonce_base"] + 100003 * state["index"] + 7919 * (state["round"] * options["walks_per_round"] + k))
        outputs = nonces.map(-> (nonce) Fsx.join(outdir, state["seed"]["shape"] + "_n" + nonce.to_s + "_s" + options["steps"].to_s + ".mfw"))
        [state, nonces, outputs]
      argvs = []
      plans.each -> (plan)
        plan[1].each_with_index -> (nonce, at)
          Fsx.unlink(plan[2][at], missing_ok: true)
          argvs.push([options["walker"], plan[0]["seed"]["shape"], plan[0]["best_path"], plan[2][at], options["steps"].to_s, nonce.to_s])
      outcomes = Procx.run_all(argvs, limit: options["jobs"])
      cursor = 0
      plans.each -> (plan)
        state = plan[0]
        taken = outcomes.slice(cursor, plan[1].size)
        cursor += plan[1].size
        round = Cascade.round_rows(state, taken, plan[1], options, plan[2])
        round[0].each -> (row)
          Fsx.append(log_path, Jsonx.dumps(row) + "\n")
        low = round[1]
        if low != nil && low[0] < state["best_rank"]
          Cascade.say(options, "DROP " + state["seed"]["shape"] + " " + state["best_rank"].to_s + " -> " + low[0].to_s)
          state["best_rank"] = low[0]
          state["best_path"] = low[1]
          state["stall"] = 0
        else
          state["stall"] += 1
        state["round"] += 1
        if state["stall"] >= options["patience"]
          Cascade.say(options, "DONE " + state["seed"]["shape"] + " " + state["best_rank"].to_s)
          state["done"] = true
      active = states.select(-> (state) !state["done"])
    nil
