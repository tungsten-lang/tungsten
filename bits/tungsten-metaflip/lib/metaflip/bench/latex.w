# LaTeX table bodies (booktabs) of a Scoring: numbers in math mode, thousands
# written `{,}`, so a paper can `\input` them without retyping a value.
use stats
use format
use report

+ Latex
  # Text with the characters that are special in LaTeX escaped.
  -> .escape(text)
    text.replace("\\", "\\textbackslash{}").replace("_", "\\_").replace("%", "\\%").replace("&", "\\&").replace("#", "\\#").replace("$", "\\$")

  # A number in math mode; large values with thousands groups, `\infty` for infinity, `--` when undefined.
  -> .number(x)
    return "--" if x == nil
    v = x.to_f ## f64
    return "$\\infty$" if v == Stats.inf()
    return "$" + Format.thousands_tex(Math.round(v).to_i) + "$" if v >= 1000.0
    "$" + Format.cost(v) + "$"

  -> .interval(iv)
    return "" if iv == nil
    " {\\scriptsize \[" + Latex.number(iv.lo) + ", " + Latex.number(iv.hi) + "\]}"

  # A percentage with one decimal below 10 %, else whole.
  -> .percent(x) (f64)
    scaled = x * 100.0 ## f64
    scaled < 10.0 ? Format.fixed(scaled, 1) : Format.fixed(scaled, 0)

  # The task id: its shape in math mode, then the name of a seed scheme.
  -> .task(id)
    parts = id.split("@")
    dims = parts[0].split("x")
    shape = "$" + dims.join("{\\times}") + "$"
    parts.size > 1 ? shape + " {\\scriptsize " + Latex.escape(parts[1]) + "}" : shape

  -> .algo(name)
    "\\texttt{" + Latex.escape(name) + "}"

  # Rows joined into a tabular with booktabs rules; `align` is the column specification.
  -> .tabular(align, header, rows, breaks)
    out = ["\\begin{tabular}{" + align + "}\\toprule", header.join(" & ") + "\\\\", "\\midrule"]
    rows.each_with_index -> (row, i)
      out.push("\\midrule") if breaks[i]
      out.push(row.join(" & ") + "\\\\")
    out.push("\\bottomrule\\end{tabular}")
    out.join("\n") + "\n"

  # One row per (task, algorithm): runs, hits, success rate with its Wilson 95% interval (%),
  # ERT in CPU seconds with its bootstrap interval, ERT in millions of flips and of proposals,
  # the Kaplan-Meier median time to target (CPU seconds) and millions of flips per CPU second.
  -> .summary(scoring, task_filter)
    rows = []
    breaks = []
    last = nil
    scoring.summaries.each -> (r)
      if task_filter == nil || r["task"] == task_filter
        w = r["success"]
        p = r["hits"].to_f / r["runs"].to_f
        rows.push([Latex.task(r["task"]), Latex.algo(r["algo"]), "$" + r["runs"].to_s + "$", "$" + r["hits"].to_s + "$", "$" + Latex.percent(p) + "$" + " {\\scriptsize \[$" + Latex.percent(w.lo) + "$, $" + Latex.percent(w.hi) + "$\]}", Latex.number(r["ert_cpu"]) + Latex.interval(r["ert_cpu_interval"]), Latex.scaled(r["ert_flips"], 1000000), Latex.scaled(r["ert_proposals"], 1000000), Latex.number(r["t50"]), Latex.scaled(r["flips_per_s"], 1000000)])
        breaks.push(last != nil && last != r["task"])
        last = r["task"]
    Latex.tabular("llrrrrrrrr", ["task", "algorithm", "$N$", "hits", "success (\\%)", "ERT (CPU s)", "ERT (Mflips)", "ERT (Mprop.)", "$T_{50}$ (s)", "Mflips/s"], rows, breaks)

  -> .scaled(x, divisor)
    return "--" if x == nil
    Latex.number(x.to_f / divisor.to_f)

  # One row per (task, algorithm) against the reference: hits of both, the success-rate
  # difference (percentage points) and the ERT ratio, each with a 95% bootstrap interval.
  -> .ablation(scoring, reference)
    rows = []
    breaks = []
    last = nil
    scoring.comparisons(reference).each -> (r)
      c = r["comparison"]
      d = c.difference_interval
      rows.push([Latex.task(r["task"]), Latex.algo(r["algo"]), "$" + r["hits"].to_s + "/" + r["runs"].to_s + "$", "$" + r["ref_hits"].to_s + "/" + r["ref_runs"].to_s + "$", "$" + Cell.percent(c.difference) + "$" + " {\\scriptsize \[$" + Cell.percent(d.lo) + "$, $" + Cell.percent(d.hi) + "$\]}", Latex.number(c.ratio) + Latex.interval(c.ratio_interval)])
      breaks.push(last != nil && last != r["task"])
      last = r["task"]
    Latex.tabular("llrrrr", ["task", "variant", "hits", "reference", "$\\Delta$ success (pp)", "ERT ratio"], rows, breaks)

  # The algorithm name without its `metaflip/` prefix.
  -> .short(algo)
    algo.slice(0, 8) == "metaflip" ? algo.slice(9, algo.size - 9) : algo

  # The group of an algorithm: the program (`km2022`, `tfg`) or, for the metaflip variants, the part of the name
  # before the first `-` (`slack` for `slack-2`).
  -> .group(algo)
    return algo.split("/")[0] if algo.slice(0, 8) != "metaflip"
    Latex.short(algo).split("-")[0]

  # A sort key that puts the settings of one group in numeric order: digit runs are numbers (`k` thousand,
  # `M` million), so `slack-2` precedes `slack-16` and `restart-100k` precedes `restart-1M`.
  -> .order_key(algo)
    name = algo.slice(0, 8) == "metaflip" ? Latex.short(algo) : algo
    cut = name.split("-")
    setting = cut.size > 1 ? cut.slice(1, cut.size - 1).join("-") : name.split("/").last()
    letters = ""
    digits = ""
    tail = ""
    i = 0 ## i64
    while i < setting.size
      ch = setting.slice(i, 1)
      if digits == "" && !"0123456789".include?(ch)
        letters = letters + ch
      elsif tail == "" && "0123456789".include?(ch)
        digits = digits + ch
      else
        tail = tail + ch
      i += 1
    number = digits == "" ? 0 : digits.to_i()
    number = number * 1000 if tail.slice(0, 1) == "k"
    number = number * 1000000 if tail.slice(0, 1) == "M"
    padded = "000000000000" + number.to_s()
    Latex.group(algo) + "\t" + letters + padded.slice(padded.size - 12, 12) + "\t" + setting

  # A ratio or cost as bare math text: `\infty` for infinity, thousands groups from 1000 on.
  -> .plain(x)
    v = x.to_f ## f64
    return "\\infty" if v == Stats.inf()
    return Format.thousands_tex(Math.round(v).to_i) if v >= 1000.0
    Format.cost(v)

  # One cell of the matrix: the ERT ratio, bold when its 95% interval excludes 1, followed by the success
  # rate in % when the variant missed the target in some runs.
  -> .ratio_cell(row)
    c = row["comparison"]
    return "--" if c.ratio == nil
    iv = c.ratio_interval
    inner = Latex.plain(c.ratio)
    inner = "\\mathbf{" + inner + "}" if iv != nil && (iv.lo > 1.0 || iv.hi < 1.0)
    cell = "$" + inner + "$"
    if row["hits"] < row["runs"]
      cell = cell + " {\\scriptsize (" + Latex.percent(row["hits"].to_f / row["runs"].to_f) + "\\%)}"
    cell

  # Matrix of ERT ratios against the reference: one row per algorithm (grouped, in numeric order of the
  # settings), one column per task.
  # With `selected` (an Array of task ids), only those columns, and only the algorithms that have a cell in one of them.
  -> .matrix(scoring, reference, selected = nil)
    cells = {}
    scoring.comparisons(reference).each -> (r)
      cells[r["task"] + "\t" + r["algo"]] = r
    tasks = scoring.tasks
    tasks = tasks.select(-> (t) selected.include?(t)) if selected != nil
    algos = scoring.algos.select(-> (a) a != reference).sort_by(-> (a) Latex.order_key(a))
    if selected != nil
      algos = algos.select -> (a)
        present = false
        tasks.each -> (t)
          present = true if cells.key?(t + "\t" + a)
        present
    rows = []
    breaks = []
    last = nil
    algos.each -> (algo)
      row = [Latex.algo(Latex.short(algo))]
      tasks.each -> (task)
        key = task + "\t" + algo
        row.push(cells.key?(key) ? Latex.ratio_cell(cells[key]) : "--")
      group = Latex.group(algo)
      breaks.push(last != nil && last != group)
      last = group
      rows.push(row)
    header = ["variant"]
    tasks.each -> (task)
      header.push(Latex.task(task))
    Latex.tabular("l" + "r" * tasks.size, header, rows, breaks)

  # The cost of reaching the target on each axis for the named algorithms: ERT in CPU seconds, in billions of
  # retired instructions and in millions of accepted flips, and millions of accepted flips per CPU second
  # (the speed of the implementation, which the other axes do not contain); one row per axis and algorithm, one
  # column per task.
  -> .axes(scoring, names)
    axes = [["ert_cpu", "ERT (CPU s)", 1.0], ["ert_instr", "ERT (Ginstr)", 1000000000.0], ["ert_flips", "ERT (Mflips)", 1000000.0], ["flips_per_s", "Mflips/s", 1000000.0]]
    rows = []
    breaks = []
    axes.each -> (axis)
      names.each_with_index -> (name, i)
        row = [i == 0 ? axis[1] : "", Latex.algo(Latex.short(name))]
        scoring.tasks.each -> (task)
          s = scoring.has?(task, name) ? scoring.summary(task, name) : nil
          row.push(s == nil || s[axis[0]] == nil ? "--" : Latex.number(s[axis[0]].to_f / axis[2]))
        breaks.push(i == 0 && rows.size > 0)
        rows.push(row)
    header = ["cost", "algorithm"]
    scoring.tasks.each -> (task)
      header.push(Latex.task(task))
    Latex.tabular("ll" + "r" * scoring.tasks.size, header, rows, breaks)
