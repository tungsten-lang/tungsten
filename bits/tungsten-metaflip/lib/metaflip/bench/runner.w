# Runs the jobs of an experiment through a pool of worker processes and
# appends one record per run (bench/README.md, sections 3 to 6).
use core/file
use core/json
use core/system
use tables
use proc
use record
use start
use verifier
use stats
use format
use plan
use walker

+ Runner
  ro :tally

  # `opts`: experiment, out, jobs, scale, runs, verifier, verify (hits|all|none),
  # order_seed, keep_runs, retry_errors, wall_factor, wall_slack, compiler,
  # bit_root, dry_run. Missing keys take the defaults of bench/README.md.
  -> new(@bench, @opts)
    @experiment = @opts["experiment"]
    @out = File.expand_path(self.option("out", env("HOME") + "/.tungsten/metaflip/experiments/record-hunt-20260926/work/eval/" + @experiment))
    @slots = self.option("jobs", 4).to_i
    @scale = self.option("scale", 1.0).to_f
    @verify = self.option("verify", "hits")
    @verifier = Verifier.new(@bench, self.option("verifier", "ruby"))
    @starts = {}
    @start_hashes = {}
    @tally = {"runs" => 0, "hits" => 0, "errors" => 0, "false_claims" => 0}
    @host = Proc.hostname()
    @commit = ""
    @walker = ""
    @total = 0
    @finished = 0

  -> option(key, fallback)
    value = @opts[key]
    value == nil ? fallback : value

  ro :out

  # Path of the JSONL file of an algorithm.
  -> records_path(algo)
    @out + "/" + algo.slug + ".jsonl"

  -> git_commit
    root = @bench.dir
    short = capture("git -C " + Shell.quote(root) + " rev-parse --short HEAD 2>/dev/null").strip
    dirty = capture("git -C " + Shell.quote(root) + " status --porcelain --untracked-files=no -- . 2>/dev/null").strip
    dirty == "" ? short : short + "-dirty"

  -> compiler
    self.option("compiler", "tungsten")

  # True when an algorithm runs the compiled walker.
  -> needs_walker?(algos)
    found = false
    algos.each -> (algo)
      found = true if algo.command.include?("/adapters/metaflip")
    found

  # The jobs still to run for the selected algorithms and tasks.
  -> plan(algos, tasks)
    records = []
    selected_tasks = {}
    selected_algos = {}
    tasks.each -> (task)
      selected_tasks[task.id] = task
    algos.each -> (algo)
      selected_algos[algo.name] = algo
    if File.directory?(@out)
      File.children(@out).each -> (name)
        if name.ends_with?(".jsonl")
          Record.load(@out + "/" + name).each -> (rec)
            if rec["experiment"] == @experiment
              self.check_resume(rec, selected_tasks[rec["task"]], selected_algos[rec["algo"]])
              records.push(rec)
    done = Plan.finished(@experiment, records, self.option("retry_errors", false))
    order_seed = self.option("order_seed", Stats.seed_of(@experiment))
    Plan.jobs(@experiment, algos, tasks, self.option("runs", nil), order_seed, done)

  # The adapter and the record both express CPU seconds to millisecond precision.
  -> budget(task)
    Format.trimmed(task.budget_cpu_s * @scale, 3).to_f

  -> check_resume(rec, task, algo)
    field = nil
    if task != nil
      if rec["budget_cpu_s"] == nil || rec["budget_cpu_s"].to_f != self.budget(task)
        field = "CPU budget"
      elsif rec["target_rank"] != task.target
        field = "target rank"
      elsif rec["start_sha256"] != self.start_hash(task)
        field = "starting-scheme digest"
    if algo != nil && rec["algo_command"] != algo.command
      field = "algorithm command"
    if field != nil
      raise "incompatible resume for " + rec["task"] + " / " + rec["algo"] + ": " + field + " differs or is unknown; use a new experiment"

  # Runs everything the plan lists; false when interrupted.
  -> run(algos, tasks)
    File.mkdir_p(@out)
    File.mkdir_p(@out + "/runs")
    @commit = self.git_commit
    jobs = self.plan(algos, tasks)
    if self.option("dry_run", false)
      jobs.each -> (job)
        << job["algo"].name + " " + job["task"].id + " " + job["seed"].to_s
      return true
    if jobs.size > 0 && self.needs_walker?(algos)
      @walker = WalkerBuild.ensure(self.option("bit_root", @bench.dir + "/.."), @out, self.compiler)
    ccall("__w_append_file", @out + "/invocations.log", capture("date -u +%Y-%m-%dT%H:%M:%SZ").strip + "\t" + @commit + "\t" + @host + "\t" + jobs.size.to_s + " jobs\n")
    Proc.trap()
    self.execute(jobs)

  -> execute(jobs)
    @total = jobs.size
    @finished = 0
    next_job = 0 ## i64
    running = []
    @storage_error = nil
    while (next_job < @total && @storage_error == nil) || running.size > 0
      while running.size < @slots && next_job < @total && @storage_error == nil
        running.push(self.launch(jobs[next_job]))
        next_job += 1
      still = []
      progressed = false
      k = 0 ## i64
      while k < running.size
        job = running[k]
        result = job["child"].poll
        if result == nil
          if Proc.now_ms() - job["child"].started_ms > job["wall_ms"] && !job["killed"]
            job["killed"] = true
            job["child"].kill
          still.push(job)
        else
          progressed = true
          self.finish(job, result)
        k += 1
      running = still
      if Proc.interrupted?()
        running.each -> (job)
          job["child"].kill
        << "interrupted after " + @finished.to_s + " of " + @total.to_s + " runs"
        return false
      Proc.sleep_ms(4) if !progressed
    raise @storage_error if @storage_error != nil
    true

  # The text of the start scheme of a task, generated once.
  -> start_text(task)
    @starts[task.id] = Start.text(@bench, task) if !@starts.key?(task.id)
    @starts[task.id]

  -> start_hash(task)
    @start_hashes[task.id] = Crypto:SHA256.hexdigest(self.start_text(task)) if !@start_hashes.key?(task.id)
    @start_hashes[task.id]

  -> run_dir(algo, task, seed)
    @out + "/runs/" + algo.slug + "/" + task.slug + "/" + seed.to_s

  # The environment of a run, as `NAME=value` words for /usr/bin/env.
  -> environment(task, seed, budget, dir)
    [
      "MB_BENCH=" + @bench.dir,
      "MB_TASK=" + task.id,
      "MB_N=" + task.n.to_s,
      "MB_M=" + task.m.to_s,
      "MB_P=" + task.p.to_s,
      "MB_TARGET=" + task.target.to_s,
      "MB_START=" + task.start,
      "MB_START_FILE=" + dir + "/start.mfw",
      "MB_START_RANK=" + Start.rank(self.start_text(task)).to_s,
      "MB_SEED=" + seed.to_s,
      "MB_BUDGET_CPU_S=" + Format.trimmed(budget, 3),
      "MB_OUT=" + dir,
      "MB_WALKER=" + @walker,
      "MB_TOOL=" + System.executable_path,
      "OMP_NUM_THREADS=1",
      "VECLIB_MAXIMUM_THREADS=1",
      "OPENBLAS_NUM_THREADS=1",
      "MKL_NUM_THREADS=1"
    ]

  # Prepares the run directory and starts the adapter.
  -> launch(job)
    task = job["task"]
    algo = job["algo"]
    seed = job["seed"]
    dir = self.run_dir(algo, task, seed)
    # A retry must preserve the diagnostics and certificate of a failed write.
    base = dir
    attempt = 0
    while File.exists?(dir)
      attempt += 1
      dir = base + "-retry-" + attempt.to_s
    File.mkdir_p(dir)
    write_file(dir + "/start.mfw", self.start_text(task))
    budget = self.budget(task) ## f64
    cpu_limit = Math.ceil(budget).to_i + 2 ## i64
    values = {"bench" => @bench.dir, "task" => task.id, "seed" => seed, "budget" => Format.trimmed(budget, 3), "out" => dir}
    command = Shell.expand(algo.command, values)
    script = "cd " + Shell.quote(dir) + " || exit 99; exec 2> stderr.log; ulimit -t " + cpu_limit.to_s + "; " + command + " > stdout.log"
    job["dir"] = dir
    job["budget"] = budget
    job["load1"] = Proc.load1()
    job["killed"] = false
    factor = self.option("wall_factor", 5).to_f ## f64
    slack = self.option("wall_slack", 120).to_f ## f64
    wall = (factor * budget + slack) * 1000.0 ## f64
    job["wall_ms"] = wall.to_i
    job["child"] = Child.spawn(["/usr/bin/env"] + self.environment(task, seed, budget, dir) + ["/bin/sh", "-c", script])
    job

  # The JSON object in a file, or nil.
  -> read_json(path)
    text = read_file(path)
    return nil if text == nil
    begin
      value = JSON.parse(text)
      return type(value) == "Hash" ? value : nil
    rescue e
      return nil

  # Turns a finished adapter into a record, verifies its claim and appends it.
  -> finish(job, ended)
    @finished += 1
    rec = self.classify(job, ended)
    dir = job["dir"]
    begin
      self.archive(job, rec) if rec["hit"] == true
      if !Record.append(self.records_path(job["algo"]), rec)
        raise "could not append benchmark record"
    rescue e
      @storage_error = "benchmark write failed; scratch retained at " + dir + ": " + e.to_s
      << @storage_error
      return nil
    @tally["runs"] += 1
    @tally["hits"] += 1 if rec["hit"] == true
    @tally["errors"] += 1 if rec["status"] != "ok"
    @tally["false_claims"] += 1 if rec["tool_hit"] == true && rec["exact"] == false
    system("rm -rf " + Shell.quote(dir)) if rec["status"] == "ok" && !self.option("keep_runs", false)
    verdict = rec["status"] != "ok" ? "error" : (rec["hit"] ? "hit" : "miss")
    << "\[" + @finished.to_s + "/" + @total.to_s + "\] " + job["algo"].name + " " + job["task"].id + " seed=" + job["seed"].to_s + " " + verdict + " cpu=" + Format.trimmed(ended.cpu_s, 3) + "s"
    ccall("w_flush")

  # Publish verified bytes before the record that will cause resume to skip this run.
  -> archive(job, rec)
    target = @out + "/schemes/" + job["algo"].slug
    File.mkdir_p(target)
    path = target + "/" + job["task"].slug + "-" + job["seed"].to_s + ".mfw"
    text = read_file(job["dir"] + "/scheme.mfw")
    raise "missing hit certificate" if text == nil
    digest = Crypto:SHA256.hexdigest(text)
    if rec["scheme_sha256"] != nil && rec["scheme_sha256"] != digest
      raise "certificate differs from the adapter digest"
    temporary = file_temp_for(path)
    raise "cannot stage certificate at " + path if temporary == nil
    begin
      raise "certificate write failed" unless write_file(temporary, text)
      copy = read_file(temporary)
      raise "certificate copy differs" if copy == nil || Crypto:SHA256.hexdigest(copy) != digest
      raise "certificate sync failed" unless file_fsync(temporary)
      File.atomic_replace(temporary, path)
    ensure
      File.rm(temporary) if File.exists?(temporary)
    rec["scheme_sha256"] = digest

  # Signals of the CPU limit that ends a run: SIGXCPU or SIGKILL of the adapter, as the shell's 128+signal.
  -> cpu_limit_exit?(ended)
    ended.code == 152 || ended.code == 137

  -> classify(job, ended)
    task = job["task"]
    algo = job["algo"]
    result = self.read_json(job["dir"] + "/result.json")
    cpu = ended.cpu_s ## f64
    tool_cpu = result == nil ? nil : result["cpu_s_tool"]
    cpu = tool_cpu.to_f if tool_cpu != nil && tool_cpu.to_f > 0.0
    error = nil
    if job["killed"]
      error = "wall-clock limit"
    elsif ended.signal != 0
      error = "adapter killed by signal " + ended.signal.to_s
    elsif ended.code != 0 && !self.cpu_limit_exit?(ended)
      error = "adapter exit status " + ended.code.to_s
    elsif result == nil && !self.cpu_limit_exit?(ended)
      error = "no result.json"
    result = {} if result == nil
    rec = {"schema" => 1, "experiment" => @experiment, "algo" => algo.name, "variant" => algo.variant, "task" => task.id, "index" => job["index"], "seed" => job["seed"], "status" => "ok", "error" => nil}
    rec["algo_command"] = algo.command
    rec["start_sha256"] = self.start_hash(task)
    rec["target_rank"] = task.target
    rec["start_rank"] = Start.rank(self.start_text(task))
    rec["budget_cpu_s"] = job["budget"]
    self.judge(rec, job, result, cpu, error)
    rec["cpu_s_total"] = cpu
    rec["cpu_s_tree"] = ended.cpu_s
    rec["cpu_s_to_hit"] = rec["hit"] == true ? cpu : nil
    rec["wall_s_total"] = Exit.seconds((Proc.now_ms() - job["child"].started_ms) * 1000)
    rec["load1"] = job["load1"]
    ["proposals_total", "proposals_to_hit", "flips_total", "flips_to_hit", "trace", "instr_retired", "cycles", "max_rss_kb", "scheme_sha256"].each -> (key)
      rec[key] = result[key]
    rec["exit_code"] = ended.code
    rec["signal"] = ended.signal == 0 ? nil : ended.signal
    rec["host"] = @host
    rec["commit"] = @commit
    rec["tool"] = result["tool"] == nil ? algo.family : result["tool"]
    rec

  # Sets status, hit, tool_hit, exact and best_rank. A hit needs the tool's claim,
  # a scheme of at most the target rank that the verifier accepts, and CPU time within the budget.
  -> judge(rec, job, result, cpu, error)
    task = job["task"]
    rec["best_rank"] = result["best_rank"]
    rec["tool_hit"] = result["hit"] == true
    rec["exact"] = nil
    rec["hit"] = false
    if error != nil
      rec["status"] = "error"
      rec["error"] = error
      return nil
    scheme = job["dir"] + "/scheme.mfw"
    if @verify != "none" && File.exists?(scheme) && (rec["tool_hit"] || @verify == "all")
      rec["exact"] = @verifier.exact?(scheme, task.n, task.m, task.p)
      if rec["exact"] == nil
        rec["status"] = "error"
        rec["error"] = "verifier " + @verifier.name + " could not run"
        return nil
    elsif rec["tool_hit"] && !File.exists?(scheme)
      rec["exact"] = false
      rec["error"] = "hit claimed without a scheme"
    within = cpu <= job["budget"]
    proven = @verify == "none" ? true : rec["exact"] == true
    small = File.exists?(scheme) ? Start.rank(read_file(scheme)) <= task.target : false
    rec["hit"] = rec["tool_hit"] && within && proven && (small || @verify == "none")
    rec["error"] = "scheme rank above the target" if rec["tool_hit"] && proven && !small && @verify != "none"
    nil
