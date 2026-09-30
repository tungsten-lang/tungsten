# Plain-text, Markdown and TSV tables of a Scoring (bench/README.md, section 7).
use stats
use format

# A table of strings: a header and rows, rendered as aligned text, Markdown or TSV.
+ Table
  ro :headers, :rows

  -> new(@headers)
    @rows = []

  -> add(row)
    @rows.push(row)

  -> widths
    out = @headers.map -> (h)
      h.size
    @rows.each -> (row)
      row.each_with_index -> (cell, i)
        out[i] = cell.size if cell.size > out[i]
    out

  # Left-aligned first two columns, right-aligned numbers.
  -> pad(cell, width, index)
    fill = " " * (width - cell.size)
    index < 2 ? cell + fill : fill + cell

  -> line(cells, widths)
    parts = []
    cells.each_with_index -> (cell, i)
      parts.push(self.pad(cell, widths[i], i))
    parts.join("  ")

  -> text
    widths = self.widths
    rule = []
    widths.each -> (w)
      rule.push("-" * w)
    out = [self.line(@headers, widths), rule.join("  ")]
    @rows.each -> (row)
      out.push(self.line(row, widths))
    out.join("\n") + "\n"

  -> markdown
    rule = []
    @headers.each -> (h)
      rule.push(" --- |")
    out = ["| " + @headers.join(" | ") + " |", "|" + rule.join("")]
    @rows.each -> (row)
      out.push("| " + row.join(" | ") + " |")
    out.join("\n") + "\n"

  -> tsv
    out = [@headers.join("\t")]
    @rows.each -> (row)
      out.push(row.join("\t"))
    out.join("\n") + "\n"

# How the numbers of a report are written.
+ Cell
  # A cost or ratio: `-` when undefined, `inf` when infinite.
  -> .cost(x)
    return "-" if x == nil
    Format.cost(x.to_f)

  -> .interval(iv)
    return "-" if iv == nil
    "\[" + Cell.cost(iv.lo) + ", " + Cell.cost(iv.hi) + "\]"

  -> .percent(x) (f64)
    Format.fixed(x * 100.0, 1)

  -> .scaled(x, divisor)
    return "-" if x == nil
    Cell.cost(x.to_f / divisor.to_f)

  # Full-precision form for TSV files.
  -> .exact(x)
    return "" if x == nil
    Format.trimmed(x.to_f, 6)

+ Report
  # Text form of the summary rows of a Scoring.
  -> .summary(scoring)
    t = Table.new(["task", "algo", "runs", "hits", "success%", "95% CI", "ERT cpu s", "95% CI", "ERT Ginstr", "ERT Mprop", "ERT Mflips", "T50 s", "Mprop/s", "Mflips/s", "AUC"])
    scoring.summaries.each -> (r)
      w = r["success"]
      t.add([r["task"], r["algo"], r["runs"].to_s, r["hits"].to_s, Cell.percent(r["hits"].to_f / r["runs"].to_f), "\[" + Cell.percent(w.lo) + ", " + Cell.percent(w.hi) + "\]", Cell.cost(r["ert_cpu"]), Cell.interval(r["ert_cpu_interval"]), Cell.scaled(r["ert_instr"], 1000000000), Cell.scaled(r["ert_proposals"], 1000000), Cell.scaled(r["ert_flips"], 1000000), Cell.cost(r["t50"]), Cell.scaled(r["proposals_per_s"], 1000000), Cell.scaled(r["flips_per_s"], 1000000), Format.fixed(r["auc"].to_f, 3)])
    t

  # Tab-separated summary with full-precision numbers.
  -> .summary_tsv(scoring)
    t = Table.new(["task", "algo", "runs", "hits", "success", "success_lo", "success_hi", "ert_cpu_s", "ert_cpu_lo", "ert_cpu_hi", "ert_instr", "ert_proposals", "ert_flips", "t25_s", "t50_s", "t75_s", "proposals_per_s", "flips_per_s", "auc"])
    scoring.summaries.each -> (r)
      w = r["success"]
      iv = r["ert_cpu_interval"]
      t.add([r["task"], r["algo"], r["runs"].to_s, r["hits"].to_s, Cell.exact(r["hits"].to_f / r["runs"].to_f), Cell.exact(w.lo), Cell.exact(w.hi), Cell.exact(r["ert_cpu"]), iv == nil ? "" : Cell.exact(iv.lo), iv == nil ? "" : Cell.exact(iv.hi), Cell.exact(r["ert_instr"]), Cell.exact(r["ert_proposals"]), Cell.exact(r["ert_flips"]), Cell.exact(r["t25"]), Cell.exact(r["t50"]), Cell.exact(r["t75"]), Cell.exact(r["proposals_per_s"]), Cell.exact(r["flips_per_s"]), Cell.exact(r["auc"])])
    t

  # Comparison of every algorithm with the reference, per task.
  -> .comparison(scoring, reference)
    t = Table.new(["task", "algo", "hits", "ref hits", "d success pp", "95% CI", "ERT ratio", "95% CI", "kept"])
    scoring.comparisons(reference).each -> (r)
      c = r["comparison"]
      t.add([r["task"], r["algo"], r["hits"].to_s + "/" + r["runs"].to_s, r["ref_hits"].to_s + "/" + r["ref_runs"].to_s, Cell.percent(c.difference), "\[" + Cell.percent(c.difference_interval.lo) + ", " + Cell.percent(c.difference_interval.hi) + "\]", Cell.cost(c.ratio), Cell.interval(c.ratio_interval), c.kept.to_s])
    t

  # Performance profile and geometric means over the tasks.
  -> .profile(scoring, reference)
    profile = scoring.profile
    t = Table.new(["algo", "tasks", "solved", "rho(1)", "rho(2)", "rho(4)", "rho(10)", "geomean vs " + reference, "over"])
    scoring.algos.each -> (algo)
      g = profile.geomean(algo, reference)
      solved = profile.ratios(algo).size
      t.add([algo, profile.included.size.to_s, solved.to_s, Cell.percent(profile.rho(algo, 1.0)), Cell.percent(profile.rho(algo, 2.0)), Cell.percent(profile.rho(algo, 4.0)), Cell.percent(profile.rho(algo, 10.0)), Cell.cost(g[0]), g[1].to_s])
    t
