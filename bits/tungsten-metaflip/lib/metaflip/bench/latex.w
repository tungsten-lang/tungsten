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
