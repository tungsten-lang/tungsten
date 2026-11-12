# metascore: tables, LaTeX fragments and pgfplots data from the JSONL records of
# metabench (bench/README.md, section 7).
#
#   metascore summary --in PATH[,PATH...] [--experiment NAME] [--reference ALGO] [--reps R]
#                     [--tsv FILE] [--md FILE] [--latex DIR] [--data DIR] [--axes ALGO,ALGO]
#                     [--matrix-tasks TASK,TASK] [--unverified] [--points G] [--decades D]
#
# PATH is a JSONL file or a directory of them. Hits count only when the verifier
# approved the scheme (`--unverified` also counts hits without a verdict).
use core/file
use core/system
use ../lib/metaflip/bench/cli
use ../lib/metaflip/bench/score
use ../lib/metaflip/bench/report
use ../lib/metaflip/bench/latex
use ../lib/metaflip/bench/pgf
use ../lib/metaflip/bench/proc

VALUED = ["--in", "--experiment", "--reference", "--reps", "--tsv", "--md", "--latex", "--data", "--points", "--decades", "--axes", "--matrix-tasks"]
FLAGS = ["--unverified"]

-> usage()
  << "usage: metascore summary --in PATH \[--experiment NAME\] \[--reference ALGO\] \[--reps R\] \[--tsv FILE\] \[--md FILE\] \[--latex DIR\] \[--data DIR\]"
  exit(2)

-> write_out(path, text)
  raise "cannot write " + path if !write_file(path, text)

args = argv()
usage() if args.size < 1 || args[0] != "summary"
opts = Cli.parse(args.slice(1, args.size - 1), VALUED, FLAGS)[1]
usage() if opts["--in"] == nil
records = Scoring.load(opts["--in"].split(","), opts["--experiment"])
if records.size == 0
  << "no records"
  exit(1)
scoring_options = {"reps" => Cli.integer(opts, "--reps", 2000), "require_exact" => opts["--unverified"] == nil}
scoring = Scoring.new(records, scoring_options)
reference = Cli.get(opts, "--reference", "metaflip/V0")
reference = "" if !scoring.algos.include?(reference)
<< "records: " + records.size.to_s + ", tasks: " + scoring.tasks.size.to_s + ", algorithms: " + scoring.algos.size.to_s + ", runs left out (status error): " + scoring.skipped.to_s + ", bootstrap replicates: " + scoring_options["reps"].to_s
summary = Report.summary(scoring)
<< ""
<< summary.text
comparison = reference == "" ? nil : Report.comparison(scoring, reference)
if comparison != nil && comparison.rows.size > 0
  << "against " + reference
  << comparison.text
profile = reference == "" ? Report.profile(scoring, scoring.algos[0]) : Report.profile(scoring, reference)
<< profile.text
write_out(opts["--tsv"], Report.summary_tsv(scoring).tsv) if opts["--tsv"] != nil
if opts["--md"] != nil
  text = "## Summary\n\n" + summary.markdown
  text = text + "\n## Against " + reference + "\n\n" + comparison.markdown if comparison != nil && comparison.rows.size > 0
  text = text + "\n## Performance profile\n\n" + profile.markdown
  write_out(opts["--md"], text)
if opts["--latex"] != nil
  File.mkdir_p(opts["--latex"])
  write_out(opts["--latex"] + "/summary.tex", Latex.summary(scoring, nil))
  scoring.tasks.each -> (task)
    write_out(opts["--latex"] + "/summary_" + Pgf.slug(task) + ".tex", Latex.summary(scoring, task))
  write_out(opts["--latex"] + "/ablation.tex", Latex.ablation(scoring, reference)) if comparison != nil && comparison.rows.size > 0
  matrix_tasks = opts["--matrix-tasks"] == nil ? nil : opts["--matrix-tasks"].split(",")
  write_out(opts["--latex"] + "/matrix.tex", Latex.matrix(scoring, reference, matrix_tasks)) if comparison != nil && comparison.rows.size > 0
  write_out(opts["--latex"] + "/axes.tex", Latex.axes(scoring, opts["--axes"].split(","))) if opts["--axes"] != nil
if opts["--data"] != nil
  files = Pgf.write_all(scoring, opts["--data"], Cli.integer(opts, "--points", 49), Cli.integer(opts, "--decades", 3))
  << "wrote " + files.to_s + " data files to " + opts["--data"]
