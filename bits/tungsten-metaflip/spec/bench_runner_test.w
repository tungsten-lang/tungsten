# End-to-end test of the benchmark runner (lib/metaflip/bench) with a fake
# adapter: known success pattern, false claims, a late hit, a crash, a
# CPU-bound loop that never ends and a hang. Checks the records, the
# exactness gate, the budget rules, resumption and the randomized run order.
# Prints FAIL lines and exits 1 on a mismatch, else PASS.
use core/file
use core/system
use ../lib/metaflip/bench/tables
use ../lib/metaflip/bench/record
use ../lib/metaflip/bench/runner
use ../lib/metaflip/bench/plan
use ../lib/metaflip/bench/stats

# Failure and check counters (a Hash, so helper functions can update it).
counts = {"checks" => 0, "failures" => 0}

-> expect(counts, label, got, want)
  counts["checks"] += 1
  if got != want
    counts["failures"] += 1
    << "FAIL " + label + ": got " + got.to_s + " want " + want.to_s

-> shell(command)
  system(command)

-> records_of(out, name)
  Record.load(out + "/" + name + ".jsonl")

# Number of records for which `check` holds.
-> count_where(records, key, value)
  n = 0
  records.each -> (rec)
    n += 1 if rec[key] == value
  n

here = __DIR__
fixtures = here + "/fixtures/bench"
tmp = env("TMPDIR")
tmp = "/tmp" if tmp == nil || tmp == ""
root = capture("mktemp -d " + Shell.quote(tmp + "/metaflip-bench-runner-XXXXXX")).strip
if root == ""
  << "FAIL cannot create scratch directory"
  exit(1)
bench_dir = root + "/bench"
File.mkdir_p(bench_dir)
verifier = "ruby " + here + "/../tools/verify_tensor.rb --shape {shape} {scheme}"
write_file(bench_dir + "/tasks.tsv", "id\tn\tm\tp\tstart\ttarget\ttier\truns\tbudget_cpu_s\tseed_base\ttarget_source\tcalibration\n2x2x2\t2\t2\t2\tstandard\t7\t1\t9\t1\t1002\tStrassen\tuncalibrated\n")
write_file(bench_dir + "/seeds.tsv", "name\tshape\trank\tfile\tsha256\tsource\n")
write_file(bench_dir + "/verifiers.tsv", "name\tcommand\tnot_exact_marker\nruby\t" + verifier + "\tTensor verification failed\n")
rows = "algo\tcommand\tnotes\n"
["coin", "liar-wrong", "liar-big", "late", "crash", "spin", "hang"].each -> (mode)
  rows = rows + "fake/" + mode + "\tsh " + fixtures + "/fake_adapter.sh " + mode + " {task} {seed} {budget} {out}\tfake\n"
write_file(bench_dir + "/algos.tsv", rows)
bench = Bench.open(bench_dir)
out = root + "/out"
tasks = bench.select_tasks("2x2x2")

options = {"experiment" => "unit", "out" => out, "jobs" => 3, "runs" => 9, "verifier" => "ruby", "wall_factor" => 3, "wall_slack" => 1, "bit_root" => here + "/.."}

# 1. Fast modes: seeds 1002..1010, every third seed hits.
fast = bench.select_algos("fake/coin,fake/liar-wrong,fake/liar-big,fake/late,fake/crash")
runner = Runner.new(bench, options)
jobs = runner.plan(fast, tasks)
expect(counts, "planned jobs", jobs.size, 45)
first = jobs[0]["seed"]
blocks_ok = true
i = 0 ## i64
while i < jobs.size
  blocks_ok = false if jobs[i]["seed"] != jobs[i - i % 5]["seed"]
  i += 1
expect(counts, "blocks of one seed hold every algorithm", blocks_ok, true)
again = Runner.new(bench, options).plan(fast, tasks)
same = true
jobs.each_with_index -> (job, k)
  same = false if job["seed"] != again[k]["seed"] || job["algo"].name != again[k]["algo"].name
expect(counts, "the run order is a function of the order seed", same, true)
other = Runner.new(bench, options.merge({"order_seed" => 99})).plan(fast, tasks)
differs = false
jobs.each_with_index -> (job, k)
  differs = true if job["seed"] != other[k]["seed"] || job["algo"].name != other[k]["algo"].name
expect(counts, "another order seed gives another order", differs, true)
expect(counts, "the order is not sorted by seed", jobs[0]["seed"] != 1002 || jobs[5]["seed"] != 1003 || jobs[10]["seed"] != 1004, true)

expect(counts, "fast experiment completes", runner.run(fast, tasks), true)
coin = records_of(out, "fake.coin")
expect(counts, "coin records", coin.size, 9)
expect(counts, "coin hits", count_where(coin, "hit", true), 3)
expect(counts, "coin verified hits", count_where(coin, "exact", true), 3)
coin.each -> (rec)
  expect(counts, "coin status " + rec["seed"].to_s, rec["status"], "ok")
  expect(counts, "coin hit iff seed % 3 == 0 " + rec["seed"].to_s, rec["hit"], rec["seed"] % 3 == 0)
  if rec["hit"]
    expect(counts, "hit time is the measured CPU", rec["cpu_s_to_hit"], rec["cpu_s_total"])
    expect(counts, "flips to hit", rec["flips_to_hit"], 60)
    expect(counts, "proposals to hit", rec["proposals_to_hit"], 100)
  else
    expect(counts, "miss has no hit time", rec["cpu_s_to_hit"], nil)
  expect(counts, "budget recorded", rec["budget_cpu_s"], 1)
  expect(counts, "target recorded", rec["target_rank"], 2 * 2 * 2 - 1)
  expect(counts, "start rank recorded", rec["start_rank"], 8)
  expect(counts, "CPU time measured", rec["cpu_s_total"] > 0.0, true)
  expect(counts, "load recorded", rec["load1"] >= 0.0, true)
wrong = records_of(out, "fake.liar-wrong")
expect(counts, "wrong-scheme claims are rejected", count_where(wrong, "exact", false), 9)
expect(counts, "wrong-scheme claims are not hits", count_where(wrong, "hit", true), 0)
expect(counts, "wrong-scheme claims are tool hits", count_where(wrong, "tool_hit", true), 9)
big = records_of(out, "fake.liar-big")
expect(counts, "rank-8 claims verify as exact", count_where(big, "exact", true), 9)
expect(counts, "rank-8 claims are not hits", count_where(big, "hit", true), 0)
expect(counts, "rank-8 claims say why", count_where(big, "error", "scheme rank above the target"), 9)
late = records_of(out, "fake.late")
expect(counts, "late hits are tool hits", count_where(late, "tool_hit", true), 9)
expect(counts, "late hits are censored", count_where(late, "hit", true), 0)
expect(counts, "late hits over budget", count_where(late, "status", "ok"), 9)
late.each -> (rec)
  expect(counts, "late run used more CPU than the budget", rec["cpu_s_total"] > 1.0, true)
crash = records_of(out, "fake.crash")
expect(counts, "crashes are errors", count_where(crash, "status", "error"), 9)
expect(counts, "crash reason", count_where(crash, "error", "adapter exit status 3"), 9)
expect(counts, "false claims counted", runner.tally["false_claims"], 9)
expect(counts, "hits counted", runner.tally["hits"], 3)
expect(counts, "errors counted", runner.tally["errors"], 9)
expect(counts, "schemes of hits are kept", capture("ls " + Shell.quote(out + "/schemes/fake.coin") + " | wc -l").strip.to_i, 3)
expect(counts, "clean runs leave no scratch directories", capture("ls " + Shell.quote(out + "/runs/fake.coin/2x2x2") + " 2>/dev/null | wc -l").strip.to_i, 0)

# 2. Resumption: nothing left; a larger run count adds only the new seeds.
expect(counts, "nothing left to run", Runner.new(bench, options).plan(fast, tasks).size, 0)
more = Runner.new(bench, options.merge({"runs" => 12})).plan(fast, tasks)
expect(counts, "resumed jobs", more.size, 15)
fresh = true
more.each -> (job)
  fresh = false if job["seed"] < 1011
expect(counts, "resumed seeds are new", fresh, true)
retry_plan = Runner.new(bench, options.merge({"retry_errors" => true})).plan(fast, tasks)
expect(counts, "errors are retried on request", retry_plan.size, 9)

# 3. Budget enforcement: a CPU-bound loop and a hang, two seeds each.
slow = bench.select_algos("fake/spin,fake/hang")
slow_options = options.merge({"experiment" => "slow", "runs" => 2, "jobs" => 4})
slow_runner = Runner.new(bench, slow_options)
expect(counts, "slow experiment completes", slow_runner.run(slow, tasks), true)
spin = records_of(out, "fake.spin")
expect(counts, "spin records", spin.size, 2)
spin.each -> (rec)
  expect(counts, "spin is censored", rec["hit"], false)
  expect(counts, "spin ends by the CPU limit", rec["status"], "ok")
  expect(counts, "spin used at least the budget", rec["cpu_s_total"] >= 1.0, true)
hang = records_of(out, "fake.hang")
expect(counts, "hang is an error", count_where(hang, "error", "wall-clock limit"), 2)
expect(counts, "hang used no CPU", hang[0]["cpu_s_total"] < 0.5, true)
expect(counts, "records file is valid JSONL", Record.encode(Record.parse(Record.encode(spin[0]))), Record.encode(spin[0]))

shell("rm -rf " + Shell.quote(root))
if counts["failures"] > 0
  << "FAIL " + counts["failures"].to_s + " of " + counts["checks"].to_s + " runner checks"
  exit(1)
<< "PASS bench runner: " + counts["checks"].to_s + " checks"
