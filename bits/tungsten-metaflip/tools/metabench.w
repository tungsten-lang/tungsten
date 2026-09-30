# metabench: run randomized flip-graph searches under a CPU budget and record
# one JSON line per run (bench/README.md).
#
#   metabench list   [--bench DIR]
#   metabench validate [--bench DIR]
#   metabench run    --experiment NAME --algo A[,B] --tasks tier1|tier2|tier3|all|ID[,ID]
#                    [--n N] [--jobs J] [--budget-scale X] [--out DIR] [--bench DIR]
#                    [--verifier NAME] [--verify hits|all|none] [--order-seed S]
#                    [--retry-errors] [--keep-runs] [--dry-run]
#                    [--wall-factor F] [--wall-slack S] [--compiler PATH]
#   metabench verify --scheme FILE --shape NxMxP [--verifier NAME] [--bench DIR]
#   metabench exec   [--report FILE] [--kill-after CPU_SECONDS] -- COMMAND [ARG...]
use ../lib/metaflip/bench/cli
use ../lib/metaflip/bench/exec
use ../lib/metaflip/bench/tables
use ../lib/metaflip/bench/runner
use ../lib/metaflip/bench/verifier
use ../lib/metaflip/bench/start
use ../lib/metaflip/bench/stats
use ../lib/metaflip/bench/format
use core/file
use core/crypto/sha256

VALUED = ["--report", "--kill-after", "--experiment", "--algo", "--tasks", "--n", "--jobs", "--budget-scale", "--out", "--bench", "--verifier", "--verify", "--order-seed", "--wall-factor", "--wall-slack", "--compiler", "--scheme", "--shape"]
FLAGS = ["--retry-errors", "--keep-runs", "--dry-run"]

-> usage()
  << "usage: metabench list|validate|run|verify|exec \[options\]; see bench/README.md"
  exit(2)

-> list_tables(bench)
  << "tasks (id, start, target, tier, runs, budget cpu s, calibration)"
  bench.tasks.each -> (t)
    << "  " + t.id + "  " + t.start + "  " + t.target.to_s + "  tier" + t.tier.to_s + "  " + t.runs.to_s + "  " + Format.trimmed(t.budget_cpu_s, 3) + "  " + t.calibration
  << "algorithms"
  bench.algos.each -> (a)
    << "  " + a.name + "  " + a.notes
  << "seeds"
  bench.seeds.each -> (row)
    << "  " + row["name"] + "  " + row["shape"] + "  rank " + row["rank"]

# Consistency of the tables: seeds match their hashes and shapes, targets lie below starts.
-> check_tables(bench)
  problems = []
  bench.seeds.each -> (row)
    text = read_file(bench.seed_path(row["name"]))
    if text == nil
      problems.push("seed " + row["name"] + ": file missing")
    else
      problems.push("seed " + row["name"] + ": sha256 differs") if Crypto:SHA256.hexdigest(text) != row["sha256"]
      problems.push("seed " + row["name"] + ": header differs from the table") if text.split("\n")[0] != "MFW1 " + row["shape"].split("x").join(" ") + " " + row["rank"]
  bench.tasks.each -> (t)
    problems.push("task " + t.id + ": id does not start with the shape " + t.shape) if !t.id.starts_with?(t.shape)
    if t.standard?
      problems.push("task " + t.id + ": target " + t.target.to_s + " not below the standard rank") if t.target >= t.n * t.m * t.p
    else
      rank = bench.seed_row(t.start)["rank"].to_i
      problems.push("task " + t.id + ": target " + t.target.to_s + " not below the seed rank " + rank.to_s) if t.target >= rank
      problems.push("task " + t.id + ": id is not shape@seed") if t.id != t.shape + "@" + t.start
    problems.push("task " + t.id + ": no seed base") if t.seed_base < 1
  bench.algos.each -> (a)
    problems.push("algorithm " + a.name + ": no adapter placeholder") if !a.command.include?("{out}") || !a.command.include?("{task}") || !a.command.include?("{seed}")
  problems.each -> (line)
    << "FAIL " + line
  return 1 if problems.size > 0
  << "ok: " + bench.tasks.size.to_s + " tasks, " + bench.algos.size.to_s + " algorithms, " + bench.seeds.size.to_s + " seeds"
  0

args = argv()
usage() if args.size < 1
command = args[0]
# `exec` takes the measured command after a bare `--`.
split_at = args.index("--")
words = split_at == nil ? args.slice(1, args.size - 1) : args.slice(1, split_at - 1)
parsed = Cli.parse(words, VALUED, FLAGS)
opts = parsed[1]
here = __DIR__
bench = Bench.open(File.expand_path(Cli.get(opts, "--bench", here + "/../bench")))
if command == "list"
  list_tables(bench)
elsif command == "validate"
  exit(check_tables(bench))
elsif command == "verify"
  shape = Cli.get(opts, "--shape", "").split("x")
  usage() if shape.size != 3 || opts["--scheme"] == nil
  verdict = Verifier.exact?(bench, Cli.get(opts, "--verifier", "ruby"), opts["--scheme"], shape[0].to_i, shape[1].to_i, shape[2].to_i)
  << (verdict == nil ? "unknown" : (verdict ? "exact" : "not exact"))
  exit(verdict == nil ? 2 : (verdict ? 0 : 1))
elsif command == "exec"
  usage() if split_at == nil || split_at + 1 >= args.size
  kill_after = opts["--kill-after"] == nil ? nil : opts["--kill-after"].to_f
  kill_after = nil if kill_after != nil && kill_after <= 0.0
  exit(Exec.run(args.slice(split_at + 1, args.size - split_at - 1), kill_after, Cli.get(opts, "--report", "/dev/null")))
elsif command == "run"
  usage() if opts["--experiment"] == nil
  runner_options = {"experiment" => opts["--experiment"], "bit_root" => File.expand_path(here + "/..")}
  runner_options["out"] = opts["--out"] if opts["--out"] != nil
  runner_options["jobs"] = Cli.integer(opts, "--jobs", 4)
  runner_options["scale"] = Cli.number(opts, "--budget-scale", 1.0)
  runner_options["runs"] = Cli.integer(opts, "--n", nil) if opts["--n"] != nil
  runner_options["verifier"] = Cli.get(opts, "--verifier", "ruby")
  runner_options["verify"] = Cli.get(opts, "--verify", "hits")
  runner_options["order_seed"] = Cli.integer(opts, "--order-seed", nil) if opts["--order-seed"] != nil
  runner_options["retry_errors"] = true if opts["--retry-errors"] != nil
  runner_options["keep_runs"] = true if opts["--keep-runs"] != nil
  runner_options["dry_run"] = true if opts["--dry-run"] != nil
  runner_options["wall_factor"] = Cli.number(opts, "--wall-factor", 5.0)
  runner_options["wall_slack"] = Cli.number(opts, "--wall-slack", 120.0)
  runner_options["compiler"] = opts["--compiler"] if opts["--compiler"] != nil
  if runner_options["compiler"] == nil
    found = env("METAFLIP_TUNGSTEN")
    found = env("TUNGSTEN_BIN") if found == nil || found == ""
    found = env("TUNGSTEN") if found == nil || found == ""
    runner_options["compiler"] = found if found != nil && found != ""
  algos = bench.select_algos(Cli.get(opts, "--algo", "metaflip/V0"))
  tasks = bench.select_tasks(Cli.get(opts, "--tasks", "tier1"))
  runner = Runner.new(bench, runner_options)
  finished = runner.run(algos, tasks)
  tally = runner.tally
  << "runs " + tally["runs"].to_s + ", hits " + tally["hits"].to_s + ", errors " + tally["errors"].to_s + ", unverified claims " + tally["false_claims"].to_s + "; records in " + runner.out
  exit(finished ? 0 : 130)
else
  usage()
