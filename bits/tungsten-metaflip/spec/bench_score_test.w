# Scoring of records (lib/metaflip/bench/score.w and the writers): which runs
# count as hits, how costs and traces enter the samples, the summary,
# comparison and profile rows, and the shape of the LaTeX, TSV and pgfplots
# output. Prints FAIL lines and exits 1 on a mismatch, else PASS.
use ../lib/metaflip/bench/score
use ../lib/metaflip/bench/report
use ../lib/metaflip/bench/latex
use ../lib/metaflip/bench/pgf

counts = {"checks" => 0, "failures" => 0}

-> expect(counts, label, got, want)
  counts["checks"] += 1
  if got != want
    counts["failures"] += 1
    << "FAIL " + label + ": got " + got.to_s + " want " + want.to_s

-> near(a, b) (f64 f64) bool
  Math.abs(a - b) <= 0.000000001

# A record of a run of `algo` on task t1 (target 5, start 8, budget 10 s).
-> record(algo, seed, hit, cpu, exact, flips, trace)
  {"schema" => 1, "experiment" => "x", "algo" => algo, "variant" => "v", "task" => "t1", "index" => seed, "seed" => seed, "status" => "ok", "error" => nil, "target_rank" => 5, "start_rank" => 8, "budget_cpu_s" => 10, "hit" => hit, "tool_hit" => hit, "exact" => exact, "best_rank" => hit ? 5 : 7, "cpu_s_total" => cpu, "cpu_s_to_hit" => hit ? cpu : nil, "proposals_total" => flips * 2, "proposals_to_hit" => hit ? flips * 2 : nil, "flips_total" => flips, "flips_to_hit" => hit ? flips : nil, "trace" => trace, "instr_retired" => flips * 1000}

records = [
  record("A", 1, true, ~1.0, true, 100, [[~0.5, 10, 8, 7], [~1.0, 20, 16, 5]]),
  record("A", 2, true, ~2.0, true, 200, nil),
  record("A", 3, true, ~3.0, true, 300, [[~1.5, 10, 8, 6]]),
  record("A", 4, false, ~10.2, nil, 1000, [[~2.0, 40, 30, 7]]),
  record("A", 5, true, ~4.0, nil, 400, nil),
  record("B", 1, false, ~10.1, nil, 900, nil),
  record("B", 2, false, ~10.1, nil, 900, nil),
  record("B", 3, false, ~10.1, nil, 900, nil)
]
failed = record("A", 6, false, ~1.0, nil, 1, nil)
failed["status"] = "error"
records.push(failed)

scoring = Scoring.new(records, {"reps" => 200})
expect(counts, "tasks", scoring.tasks.to_s, ["t1"].to_s)
expect(counts, "algorithms", scoring.algos.to_s, ["A", "B"].to_s)
expect(counts, "runs with errors are left out", scoring.skipped, 1)
a = scoring.summary("t1", "A")
expect(counts, "runs of A", a["runs"], 5)
expect(counts, "unverified hits do not count", a["hits"], 3)
expect(counts, "ERT of A on cpu", near(a["ert_cpu"], (1.0 + 2.0 + 3.0 + 10.0 + 10.0) / 3.0), true)
expect(counts, "ERT of A on flips", near(a["ert_flips"], (100.0 + 200.0 + 300.0 + 1000.0 + 400.0) / 3.0), true)
expect(counts, "ERT of A on retired instructions", near(a["ert_instr"], 2000000.0 / 3.0), true)
expect(counts, "T50 of A", a["t50"], ~3.0)
b = scoring.summary("t1", "B")
expect(counts, "B never hits", b["hits"], 0)
expect(counts, "B has an infinite ERT", b["ert_cpu"] == Stats.inf(), true)

lenient = Scoring.new(records, {"reps" => 200, "require_exact" => false})
expect(counts, "unverified hits count when allowed", lenient.summary("t1", "A")["hits"], 4)

# The trace of a hit without a final entry ends at the target; a missing trace stays at the start rank.
sample = scoring.sample("t1", "A")
expect(counts, "trace before the first entry", sample.rank_at(0, 0.25), ~8.0)
expect(counts, "trace after an entry", sample.rank_at(0, 0.75), ~7.0)
expect(counts, "trace ends at the target", sample.rank_at(0, 1.0), ~5.0)
expect(counts, "hit without a trace reaches the target", sample.rank_at(1, 2.0), ~5.0)
expect(counts, "hit without a trace starts at the start rank", sample.rank_at(1, 1.9), ~8.0)
expect(counts, "censored run keeps its last entry", sample.rank_at(3, 9.0), ~7.0)

# Records of one task must share their budget.
odd = record("A", 9, true, ~1.0, true, 1, nil)
odd["budget_cpu_s"] = 20
mixed = false
begin
  Scoring.new(records + [odd], {"reps" => 200})
rescue e
  mixed = true
expect(counts, "mixed budgets are refused", mixed, true)

comparisons = scoring.comparisons("B")
expect(counts, "one comparison", comparisons.size, 1)
c = comparisons[0]["comparison"]
expect(counts, "difference in success", near(c.difference, 0.6), true)
expect(counts, "ratio against a reference without hits is undefined", c.ratio, nil)
profile = scoring.profile
expect(counts, "profile includes the task", profile.included.size, 1)
expect(counts, "A solves it", profile.rho("A", 1.0), ~1.0)
expect(counts, "B does not", profile.rho("B", 1000.0), ~0.0)

# Output shapes.
tsv = Report.summary_tsv(scoring).tsv
expect(counts, "tsv header", tsv.starts_with?("task\talgo\truns\thits\t"), true)
expect(counts, "tsv rows", tsv.strip.split("\n").size, 3)
text = Report.summary(scoring).text
expect(counts, "text table has a rule line", text.split("\n")[1].starts_with?("----"), true)
tex = Latex.summary(scoring, nil)
expect(counts, "latex begins with a tabular", tex.starts_with?("\\begin{tabular}{llrrrrrrrr}\\toprule"), true)
expect(counts, "latex ends with the rule", tex.ends_with?("\\bottomrule\\end{tabular}\n"), true)
expect(counts, "latex task shape", tex.include?("$t1$") || tex.include?("t1"), true)
expect(counts, "latex escapes names", Latex.algo("guard_none"), "\\texttt{guard\\_none}")
expect(counts, "latex thousands", Latex.number(12345.6), "$12{,}346$")
expect(counts, "latex infinity", Latex.number(Stats.inf()), "$\\infty$")
expect(counts, "latex undefined", Latex.number(nil), "--")
expect(counts, "latex task with a seed", Latex.task("9x9x9@perminov486"), "$9{\\times}9{\\times}9$ {\\scriptsize perminov486}")
ablation = Latex.ablation(scoring, "B")
expect(counts, "ablation tabular", ablation.include?("$\\Delta$ success (pp)"), true)
survival = Pgf.survival(scoring, "t1", "A")
expect(counts, "survival header", survival.split("\n")[0], "t survival")
expect(counts, "survival starts at one", survival.split("\n")[1], "0 1")
descent = Pgf.descent(scoring, "t1", "A", 13, 3)
expect(counts, "descent has a header and 13 rows", descent.strip.split("\n").size, 14)
expect(counts, "descent starts at the start rank", descent.split("\n")[1].split(" ")[1], "8")
steps = Pgf.profile(scoring, profile, "A", 10)
expect(counts, "profile header", steps.split("\n")[0], "tau rho")
expect(counts, "profile of an unsolved task is flat", Pgf.profile(scoring, profile, "B", 10).strip.split("\n").size, 3)

if counts["failures"] > 0
  << "FAIL " + counts["failures"].to_s + " of " + counts["checks"].to_s + " score checks"
  exit(1)
<< "PASS bench score: " + counts["checks"].to_s + " checks"
