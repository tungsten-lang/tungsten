# The benchmark definition: tasks.tsv, seeds.tsv, algos.tsv and verifiers.tsv
# of a bench directory (bench/README.md, section 2).
use core/file
use core/crypto/sha256

# A tab-separated file with a header line; `#` lines and blank lines are skipped.
+ Tsv
  -> .load(path)
    text = read_file(path)
    raise "cannot read " + path if text == nil
    header = nil
    rows = []
    text.split("\n").each -> (line)
      if line != "" && !line.starts_with?("#")
        cells = line.split("\t")
        if header == nil
          header = cells
        else
          row = {}
          i = 0 ## i64
          while i < header.size
            row[header[i]] = i < cells.size ? cells[i] : ""
            i += 1
          rows.push(row)
    rows

# One benchmark task: format n x m x p, start scheme, target rank and budget.
+ Task
  ro :id, :n, :m, :p, :start, :target, :tier, :runs, :budget_cpu_s, :seed_base, :target_source, :calibration

  -> .of(row)
    Task.new(row["id"], row["n"].to_i, row["m"].to_i, row["p"].to_i, row["start"], row["target"].to_i, row["tier"].to_i, row["runs"].to_i, row["budget_cpu_s"].to_f, row["seed_base"].to_i, row["target_source"], row["calibration"])

  -> new(@id, @n, @m, @p, @start, @target, @tier, @runs, @budget_cpu_s, @seed_base, @target_source, @calibration)

  -> shape
    @n.to_s + "x" + @m.to_s + "x" + @p.to_s

  # The rank of the start scheme: nmp for the standard algorithm, else the rank of the seed.
  -> standard?
    @start == "standard"

  # A file-name safe form of the id.
  -> slug
    @id.replace("@", "_at_")

# One algorithm: `algo/variant`, its adapter command and a note.
+ Algo
  ro :name, :command, :notes

  -> .of(row)
    Algo.new(row["algo"], row["command"], row["notes"])

  -> new(@name, @command, @notes)

  # The part before the first slash, and the rest.
  -> family
    @name.split("/")[0]

  -> variant
    parts = @name.split("/")
    parts.size > 1 ? parts[1] : ""

  # A file-name safe form of the name.
  -> slug
    @name.replace("/", ".")

# The tables of one bench directory.
+ Bench
  ro :dir, :tasks, :algos, :seeds, :verifiers

  -> .open(dir)
    tasks = Tsv.load(dir + "/tasks.tsv").map -> (row)
      Task.of(row)
    algos = Tsv.load(dir + "/algos.tsv").map -> (row)
      Algo.of(row)
    Bench.new(dir, tasks, algos, Tsv.load(dir + "/seeds.tsv"), Tsv.load(dir + "/verifiers.tsv"))

  -> new(@dir, @tasks, @algos, @seeds, @verifiers)

  -> task(id)
    found = nil
    @tasks.each -> (t)
      found = t if t.id == id
    raise "unknown task " + id if found == nil
    found

  -> algo(name)
    found = nil
    @algos.each -> (a)
      found = a if a.name == name
    raise "unknown algorithm " + name if found == nil
    found

  # Tasks named by a comma separated list of ids and groups (`tier1`, `tier2`, `tier3`, `all`).
  -> select_tasks(spec)
    chosen = []
    spec.split(",").each -> (item)
      if item == "all"
        @tasks.each -> (t)
          chosen.push(t)
      elsif item.starts_with?("tier")
        level = item.slice(4, item.size - 4).to_i
        @tasks.each -> (t)
          chosen.push(t) if t.tier == level
      else
        chosen.push(self.task(item))
    chosen

  # Algorithms named by a comma separated list of names; `all` selects every one.
  -> select_algos(spec)
    chosen = []
    spec.split(",").each -> (item)
      if item == "all"
        @algos.each -> (a)
          chosen.push(a)
      else
        chosen.push(self.algo(item))
    chosen

  # The seed row `name` of seeds.tsv.
  -> seed_row(name)
    found = nil
    @seeds.each -> (row)
      found = row if row["name"] == name
    raise "unknown seed " + name if found == nil
    found

  # Absolute path of the seed scheme `name`.
  -> seed_path(name)
    file = self.seed_row(name)["file"]
    file.starts_with?("/") ? file : @dir + "/" + file

  # The verifier row `name` of verifiers.tsv.
  -> verifier_row(name)
    found = nil
    @verifiers.each -> (row)
      found = row if row["name"] == name
    raise "unknown verifier " + name if found == nil
    found
