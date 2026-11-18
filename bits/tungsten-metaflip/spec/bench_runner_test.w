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

# Timing. Every budget rule below is stated in CPU time, which a loaded machine
# does not stretch: `late` burns a calibrated 1.3 CPU-seconds against the
# budget of 1 (spec/fixtures/bench/fake_adapter.sh), `spin` runs into the
# runner's `ulimit -t` of 3 CPU-seconds. Wall-clock time is another matter (at
# a load of 50 on 18 cores one CPU-second took 4 to 9 s here), so the adapters
# that work get a wall limit only a hang can reach (3 s + 600 s of slack), and
# the one adapter that does hang, which uses no CPU and so is not slowed by
# load either, gets its own experiment with a wall limit of 4 s.
options = {"experiment" => "unit", "out" => out, "jobs" => 3, "runs" => 9, "verifier" => "ruby", "wall_factor" => 3, "wall_slack" => 600, "bit_root" => here + "/.."}

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

changed = Runner.new(bench, options.merge({"scale" => 2}))
rejected = false
begin
  changed.plan(fast, tasks)
rescue e
  rejected = e.to_s.include?("incompatible resume")
expect(counts, "budget changes fail during planning", rejected, true)
# Existing records can lack newer fields, or the task/adapter can have changed.
coin_config = bench.select_algos("fake/coin")[0]
mutations = [{"target_rank" => 6}, {"start_sha256" => "different"}, {"algo_command" => "new flags"}, {"start_sha256" => nil}]
mutations.each -> (mutation)
  rejected = false
  begin
    runner.check_resume(coin[0].merge(mutation), tasks[0], coin_config)
  rescue e
    rejected = e.to_s.include?("incompatible resume")
  expect(counts, "resume detects " + mutation.keys[0], rejected, true)
coin.each -> (rec)
  if rec["hit"]
    path = out + "/schemes/fake.coin/2x2x2-" + rec["seed"].to_s + ".mfw"
    expect(counts, "archived digest", rec["scheme_sha256"], Crypto:SHA256.hexdigest(read_file(path)))

# Make schemes a regular file so that the certificate cannot be published.
broken_out = root + "/broken"
File.mkdir_p(broken_out)
write_file(broken_out + "/schemes", "occupied")
single = options.merge({"out" => broken_out, "jobs" => 1, "runs" => 1})
coin_algo = bench.select_algos("fake/coin")
failed = false
begin
  Runner.new(bench, single).run(coin_algo, tasks)
rescue e
  failed = e.to_s.include?("scratch retained")
expect(counts, "publication failure stops the run", failed, true)
expect(counts, "failed hit was never appended", records_of(broken_out, "fake.coin").size, 0)
scratch = broken_out + "/runs/fake.coin/2x2x2/1002/scheme.mfw"
expect(counts, "failed hit retained for recovery", File.exists?(scratch), true)
File.rm(broken_out + "/schemes")
expect(counts, "retry succeeds", Runner.new(bench, single).run(coin_algo, tasks), true)
expect(counts, "retry preserves original scratch", File.exists?(scratch), true)

# Point the journal at a missing directory to fail the append after publication.
+ BrokenJournalRunner < Runner
  -> records_path(algo)
    self.out + "/missing-parent/journal.jsonl"

journal_out = root + "/journal"
failed = false
begin
  BrokenJournalRunner.new(bench, single.merge({"out" => journal_out})).run(coin_algo, tasks)
rescue e
  failed = e.to_s.include?("scratch retained")
expect(counts, "append failure stops the run", failed, true)
expect(counts, "certificate published before append", File.exists?(journal_out + "/schemes/fake.coin/2x2x2-1002.mfw"), true)
expect(counts, "append failure preserves scratch", File.exists?(journal_out + "/runs/fake.coin/2x2x2/1002/scheme.mfw"), true)

# 3. Budget enforcement: a CPU-bound loop, ended by the CPU limit, two seeds.
spin_options = options.merge({"experiment" => "spin", "runs" => 2, "jobs" => 2})
spin_runner = Runner.new(bench, spin_options)
expect(counts, "spin experiment completes", spin_runner.run(bench.select_algos("fake/spin"), tasks), true)
spin = records_of(out, "fake.spin")
expect(counts, "spin records", spin.size, 2)
spin.each -> (rec)
  expect(counts, "spin is censored", rec["hit"], false)
  expect(counts, "spin ends by the CPU limit", rec["status"], "ok")
  expect(counts, "spin used at least the budget", rec["cpu_s_total"] >= 1.0, true)

# 4. A hang, ended by the wall-clock limit (3 * 1 s + 1 s of slack), two seeds.
hang_options = options.merge({"experiment" => "hang", "runs" => 2, "jobs" => 2, "wall_slack" => 1})
hang_runner = Runner.new(bench, hang_options)
expect(counts, "hang experiment completes", hang_runner.run(bench.select_algos("fake/hang"), tasks), true)
hang = records_of(out, "fake.hang")
expect(counts, "hang records", hang.size, 2)
expect(counts, "hang is an error", count_where(hang, "error", "wall-clock limit"), 2)
hang.each -> (rec)
  expect(counts, "hang used no CPU", rec["cpu_s_total"] < 0.5, true)
  expect(counts, "hang ended at the wall limit", rec["wall_s_total"] >= 4.0, true)
expect(counts, "records file is valid JSONL", Record.encode(Record.parse(Record.encode(spin[0]))), Record.encode(spin[0]))

shell("rm -rf " + Shell.quote(root))
if counts["failures"] > 0
  << "FAIL " + counts["failures"].to_s + " of " + counts["checks"].to_s + " runner checks"
  exit(1)
<< "PASS bench runner: " + counts["checks"].to_s + " checks"
