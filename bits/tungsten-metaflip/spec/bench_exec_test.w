# The measured child of the benchmark (lib/metaflip/bench/exec.w, proc.w): exit
# status pass-through, CPU time from the resource usage, retired instructions,
# the CPU-time kill and the shell quoting used to start adapters. Prints FAIL
# lines and exits 1 on a mismatch, else PASS.
use core/file
use core/json
use core/system
use ../lib/metaflip/bench/exec
use ../lib/metaflip/bench/proc

counts = {"checks" => 0, "failures" => 0}

-> expect(counts, label, got, want)
  counts["checks"] += 1
  if got != want
    counts["failures"] += 1
    << "FAIL " + label + ": got " + got.to_s + " want " + want.to_s

tmp = env("TMPDIR")
tmp = "/tmp" if tmp == nil || tmp == ""
dir = capture("mktemp -d " + Shell.quote(tmp + "/metaflip-bench-exec-XXXXXX")).strip
report = dir + "/report.json"

# A short command: status is passed through, the report is exact JSON.
status = Exec.run(["/bin/sh", "-c", "i=0; while test $i -lt 20000; do i=$((i+1)); done; exit 3"], nil, report)
expect(counts, "exit status passes through", status, 3)
r = JSON.parse(read_file(report))
expect(counts, "report says exit 3", r["exit"], 3)
expect(counts, "report says not killed", r["killed"], false)
expect(counts, "CPU time is positive", r["cpu_s"] > 0.0, true)
expect(counts, "CPU time is plausible", r["cpu_s"] < 5.0, true)
expect(counts, "user + system add up", Math.abs(r["user_s"] + r["sys_s"] - r["cpu_s"]) < 0.000002, true)
expect(counts, "retired instructions are counted", r["instr_retired"] > 1000000, true)
expect(counts, "cycles are counted", r["cycles"] > 1000000, true)
expect(counts, "resident set is reported", r["max_rss_kb"] > 0, true)
expect(counts, "wall time is at least the CPU time", r["wall_s"] + 0.05 >= r["cpu_s"], true)

# A CPU-bound loop is killed after its CPU limit, measured on the child alone.
status = Exec.run(["/bin/sh", "-c", "while :; do :; done"], 0.3, report)
r = JSON.parse(read_file(report))
expect(counts, "the loop was killed", r["killed"], true)
expect(counts, "status after a kill", status, 128 + 9)
expect(counts, "CPU time reaches the limit", r["cpu_s"] >= 0.3, true)
expect(counts, "CPU time stops near the limit", r["cpu_s"] < 1.5, true)

# Descendants count in the CPU time of the tree.
status = Exec.run(["/bin/sh", "-c", "sh -c 'i=0; while test $i -lt 30000; do i=$((i+1)); done'; exit 0"], nil, report)
child_tree = JSON.parse(read_file(report))
expect(counts, "tree run succeeds", status, 0)
expect(counts, "descendants are metered", child_tree["cpu_s"] > 0.02, true)

# Shell words and paths.
expect(counts, "quote", Shell.quote("a b'c"), "'a b'\"'\"'c'")
expect(counts, "expand", Shell.expand("x {a} {b}", {"a" => "1 2", "b" => 3}), "x '1 2' '3'")
expect(counts, "dirname", Paths.dirname("/a/b/c.w"), "/a/b")
expect(counts, "dirname of a bare name", Paths.dirname("c.w"), ".")
expect(counts, "dirname of a root file", Paths.dirname("/c.w"), "/")
expect(counts, "basename", Paths.basename("/a/b/c.w"), "c.w")
expect(counts, "load average", Proc.load1() >= 0.0, true)

system("rm -rf " + Shell.quote(dir))
if counts["failures"] > 0
  << "FAIL " + counts["failures"].to_s + " of " + counts["checks"].to_s + " exec checks"
  exit(1)
<< "PASS bench exec: " + counts["checks"].to_s + " checks"
