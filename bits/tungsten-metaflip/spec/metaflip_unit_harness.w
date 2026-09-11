# Shared harness for the metaflip unit-test shards and the manifest guard.
#
# Metaflip's unit tests are standalone `spec/*_test.w` programs that exit 0 on
# success, not `_spec.w` suites, so the root gate (scripts/test-bit-specs.sh)
# never discovers them on its own. spec/metaflip_unit_shard<N>_spec.w are the
# discoverable wrappers: each runs one shard of spec/interpreted_tests.txt as
# child interpreter processes, the way the root gate runs any bit suite.
# spec/native_tests.txt lists the tests that cannot run interpreted, and
# spec/metaflip_test_manifest_spec.w keeps both manifests complete and
# disjoint so a newly added test must be classified.

# `__DIR__` is relative when the interpreter is handed a relative path, and
# the child command `cd`s into the bit root, so anchor both on absolute paths.
-> mfu_bit_root
  file_expand_path(__DIR__ + "/..")

# The root gate exports TUNGSTEN; standalone runs fall back to the monorepo's
# bin/tungsten relative to this file.
-> mfu_tungsten
  configured = env("TUNGSTEN")
  configured == nil || configured == "" ? file_expand_path(__DIR__ + "/../../../bin/tungsten") : configured

# Manifest rows are whitespace-separated columns; blank lines and `#` comments
# (whole-line or trailing) are ignored.
-> mfu_manifest_rows(name)
  rows = []
  read_file(__DIR__ + "/" + name).split("\n").each -> (raw)
    line = raw
    hash = line.index("#")
    line = line.slice(0, hash) if hash != nil
    fields = []
    line.split(" ").each -> (field)
      fields.push(field) if field.size > 0
    rows.push(fields) if fields.size > 0
  rows

-> mfu_shard_tests(shard)
  tests = []
  mfu_manifest_rows("interpreted_tests.txt").each -> (row)
    tests.push(row[1]) if row.size >= 2 && row[0].to_i == shard
  tests

# Per-run log directory: never a fixed path, so parallel shards and
# concurrent checkouts cannot clobber each other.
-> mfu_log_dir(shard)
  base = env("TMPDIR")
  base = "/tmp" if base == nil || base == ""
  pid = capture("echo $PPID").strip
  base + "/metaflip-unit-shard" + shard.to_s + "." + pid

-> mfu_now
  capture("date +%s").strip.to_i

# Runs every test of one shard, one child process at a time, from the bit
# root (the tests `use ../lib/...` relative to their file and write only to
# /tmp or argv-supplied paths). Returns the process exit status.
-> mfu_run_shard(shard)
  tests = mfu_shard_tests(shard)
  if tests.size == 0
    << "FAIL metaflip unit shard [shard]: no tests listed in spec/interpreted_tests.txt"
    exit(1)
  logs = mfu_log_dir(shard)
  if !system("mkdir -p '" + logs + "'")
    << "FAIL metaflip unit shard [shard]: cannot create " + logs
    exit(1)
  tungsten = mfu_tungsten
  root = mfu_bit_root
  failures = []
  tests.each -> (path)
    log = logs + "/" + path.split("/").last + ".log"
    started = mfu_now
    ok = system("cd '" + root + "' && env TUNGSTEN_INTERPRETED_SPEC=1 TUNGSTEN_SPEC_QUIET=1 '" + tungsten + "' run --interpret '" + path + "' > '" + log + "' 2>&1")
    elapsed = mfu_now - started
    if ok
      << "PASS " + path + " ([elapsed]s)"
    else
      failures.push(path)
      << "FAIL " + path + " ([elapsed]s) log: " + log
      << capture("tail -n 20 '" + log + "'")
  << "metaflip unit shard [shard]: [tests.size - failures.size] passed, [failures.size] failed"
  system("rm -rf '" + logs + "'") if failures.size == 0
  failures.size == 0 ? 0 : 1
