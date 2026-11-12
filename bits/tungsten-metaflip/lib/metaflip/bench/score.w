# Scoring of an experiment: records grouped into one Sample per (task, algorithm),
# summary rows, comparisons with a reference algorithm and the performance profile
# (bench/README.md, section 7).
use core/file
use core/system
use proc
use stats
use record
use sample
use profile

+ Scoring
  ro :records, :tasks, :algos, :skipped

  # `options`: require_exact (hits need the verifier's approval; default true),
  # reps (bootstrap replicates, default 2000), reference (algorithm name), points and decades of the descent grid.
  -> new(@records, @options)
    @require_exact = @options.key?("require_exact") ? @options["require_exact"] : true
    @reps = @options.key?("reps") ? @options["reps"] : 2000
    @tasks = []
    @algos = []
    @skipped = 0
    @meta = {}
    @samples = {}
    @task_key = {}
    @records.each -> (rec)
      self.add(rec)
    # Tasks in ascending order of their target rank (then by name), whatever the order of the records.
    @tasks = @task_key.values.sort.map -> (key)
      key.split("\t")[1]

  # The records of files and directories (`*.jsonl` inside), restricted to one experiment when
  # named. When a run appears twice the later record wins.
  -> .load(paths, experiment)
    files = []
    paths.each -> (path)
      if File.directory?(path)
        capture("ls " + Shell.quote(path) + "/*.jsonl 2>/dev/null").split("\n").each -> (name)
          files.push(name) if name != ""
      else
        files.push(path)
    latest = {}
    order = []
    files.each -> (file)
      Record.load(file).each -> (rec)
        if experiment == nil || rec["experiment"] == experiment
          key = Record.key(rec)
          order.push(key) if !latest.key?(key)
          latest[key] = rec
    order.map -> (key)
      latest[key]

  # Adds a record to its (task, algorithm) sample; runs with status other than ok are counted and left out.
  -> add(rec)
    if rec["status"] != "ok"
      @skipped += 1
      return nil
    task = rec["task"]
    algo = rec["algo"]
    if !@samples.key?(task)
      @samples[task] = {}
      @tasks.push(task)
      @meta[task] = {"target" => rec["target_rank"], "start" => rec["start_rank"], "budget" => rec["budget_cpu_s"]}
      padded = "00000" + rec["target_rank"].to_s()
      @task_key[task] = padded.slice(padded.size - 5, 5) + "\t" + task
    @algos.push(algo) if !@algos.include?(algo)
    if @meta[task]["budget"] != rec["budget_cpu_s"]
      raise "task " + task + " has records with budgets " + @meta[task]["budget"].to_s + " and " + rec["budget_cpu_s"].to_s + "; select one experiment"
    if !@samples[task].key?(algo)
      @samples[task][algo] = Sample.new(rec["budget_cpu_s"].to_f, rec["start_rank"], rec["target_rank"], 1)
    hit = rec["hit"] == true && (rec["exact"] == true || !@require_exact)
    spent = hit ? rec["cpu_s_to_hit"] : rec["cpu_s_total"]
    trace = self.trace_of(rec, hit)
    @samples[task][algo].add(hit, spent, rec["instr_retired"], hit ? rec["proposals_to_hit"] : rec["proposals_total"], hit ? rec["flips_to_hit"] : rec["flips_total"], trace[0], trace[1])

  # The trace of a record as [times, ranks] (nil without a trace). A hit whose trace lacks the
  # target gets a final entry at its hit time.
  -> trace_of(rec, hit)
    entries = rec["trace"]
    entries = [] if entries == nil
    extra = hit && (entries.size == 0 || entries[entries.size - 1][3] > rec["target_rank"]) ? 1 : 0
    return [nil, nil] if entries.size + extra == 0
    times = f64[entries.size + extra]
    ranks = f64[entries.size + extra]
    i = 0 ## i64
    while i < entries.size
      times[i] = entries[i][0].to_f
      ranks[i] = entries[i][3].to_f
      i += 1
    if extra == 1
      times[entries.size] = rec["cpu_s_to_hit"].to_f
      ranks[entries.size] = rec["target_rank"].to_f
    [times, ranks]

  -> sample(task, algo)
    @samples[task][algo]

  -> has?(task, algo)
    @samples.key?(task) && @samples[task].key?(algo)

  -> target(task)
    @meta[task]["target"]

  -> start_rank(task)
    @meta[task]["start"]

  -> budget(task)
    @meta[task]["budget"]

  -> option(key, fallback)
    @options.key?(key) ? @options[key] : fallback

  -> bootstrap_seed(task, algo, axis)
    Stats.seed_of(task + "\t" + algo + "\t" + axis)

  # The statistics of one (task, algorithm) sample as a Hash.
  -> summary(task, algo)
    s = self.sample(task, algo)
    row = {"task" => task, "algo" => algo, "runs" => s.size, "hits" => s.hit_count}
    row["success"] = Stats.wilson(s.hit_count, s.size)
    row["ert_cpu"] = s.ert("cpu")
    row["ert_cpu_interval"] = s.ert_interval("cpu", self.bootstrap_seed(task, algo, "cpu"), @reps)
    ["instr", "proposals", "flips"].each -> (axis)
      row["ert_" + axis] = s.ert(axis)
      row["ert_" + axis + "_interval"] = s.ert_interval(axis, self.bootstrap_seed(task, algo, axis), @reps)
    curve = s.survival
    row["t25"] = curve.quantile_time(25)
    row["t50"] = curve.quantile_time(50)
    row["t75"] = curve.quantile_time(75)
    row["proposals_per_s"] = s.throughput("proposals")
    row["flips_per_s"] = s.throughput("flips")
    row["auc"] = s.auc
    row

  # Summary rows for every task and algorithm with data, in task then algorithm order.
  -> summaries
    rows = []
    @tasks.each -> (task)
      @algos.each -> (algo)
        rows.push(self.summary(task, algo)) if self.has?(task, algo)
    rows

  # Comparisons of every other algorithm with `reference` on each task: rows {task, algo, comparison, runs, hits, ref_runs, ref_hits}.
  -> comparisons(reference)
    rows = []
    @tasks.each -> (task)
      if self.has?(task, reference)
        base = self.sample(task, reference)
        @algos.each -> (algo)
          if algo != reference && self.has?(task, algo)
            s = self.sample(task, algo)
            seed = Stats.seed_of(task + "\t" + algo + "\t" + reference)
            rows.push({"task" => task, "algo" => algo, "comparison" => Comparison.of(s, base, seed, @reps), "runs" => s.size, "hits" => s.hit_count, "ref_runs" => base.size, "ref_hits" => base.hit_count})
    rows

  # The performance profile over tasks on the CPU axis.
  -> profile
    erts = {}
    @tasks.each -> (task)
      erts[task] = {}
      @algos.each -> (algo)
        erts[task][algo] = self.sample(task, algo).ert("cpu") if self.has?(task, algo)
    Profile.new(@tasks, @algos, erts)
