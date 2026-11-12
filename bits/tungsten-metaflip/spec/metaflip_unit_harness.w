# Shared harness for the metaflip unit-test shards and the manifest guard.
#
# Metaflip's unit tests are standalone `spec/*_test.w` programs that exit 0 on
# success, not `_spec.w` suites, so the root gate (scripts/test-bit-specs.sh)
# never discovers them on its own. Two families of discoverable wrappers run
# them, each wrapper one shard, one child process per test, from the bit root:
#
#   spec/metaflip_unit_shard<N>_spec.w     the tests of spec/interpreted_tests.txt,
#                                          as child interpreters
#   spec/metaflip_native_shard<N>_spec.w   the tests of spec/native_tests.txt that
#                                          need the compiled engine and no
#                                          arguments, as `bin/tungsten spec/x_test.w`
#                                          (compiled through WIRE, run from the
#                                          bit's build cache)
#
# The root gate runs every wrapper itself through the interpreter; what the
# wrapper starts is the engine the manifest names. spec/native_tests.txt also
# lists the tests no wrapper can run (they need arguments or a GPU), and
# spec/metaflip_test_manifest_spec.w keeps both manifests complete and
# disjoint, so a newly added test must be classified, and a runnable one must
# be in a shard that has a wrapper.

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

# Rows of spec/native_tests.txt are `path reason` or, for the reasons that
# leave a test runnable as it stands, `path reason shard`.
-> mfu_native_runnable?(reason)
  reason == "native" || reason == "timeout"

-> mfu_native_shard_tests(shard)
  tests = []
  mfu_manifest_rows("native_tests.txt").each -> (row)
    tests.push(row[0]) if row.size == 3 && mfu_native_runnable?(row[1]) && row[2].to_i == shard
  tests

# Per-run log directory: never a fixed path, so parallel shards and
# concurrent checkouts cannot clobber each other.
-> mfu_log_dir(kind, shard)
  base = env("TMPDIR")
  base = "/tmp" if base == nil || base == ""
  pid = capture("echo $PPID").strip
  base + "/metaflip-" + kind + "-shard" + shard.to_s + "." + pid

-> mfu_now
  capture("date +%s").strip.to_i

# Seconds after which one compiled test is stopped (SIGALRM): the root gate's
# watchdog (300 s per suite) only stops the wrapper, so without a bound of its
# own a test that hangs would outlive the gate. No test can need longer than
# the whole suite is allowed. METAFLIP_NATIVE_TEST_TIMEOUT overrides it (raise
# it together with BIT_SPEC_TIMEOUT_SECONDS on a heavily loaded machine); 0
# runs the tests unbounded.
-> mfu_native_timeout
  configured = env("METAFLIP_NATIVE_TEST_TIMEOUT")
  configured == nil || configured == "" ? 300 : configured.to_i

# The command line of one test, without the output redirection. Interpreted:
# a child interpreter with the spec environment of the root gate. Compiled: a
# plain `tungsten spec/x_test.w` with that environment removed (the wrapper
# itself runs under it) and no terminal to read from.
-> mfu_command(kind, tungsten, path)
  if kind == "unit"
    return "env TUNGSTEN_INTERPRETED_SPEC=1 TUNGSTEN_SPEC_QUIET=1 '" + tungsten + "' run --interpret '" + path + "'"
  bound = mfu_native_timeout
  guard = bound > 0 ? "perl -e 'alarm shift; exec @ARGV' " + bound.to_s + " " : ""
  guard + "env -u TUNGSTEN_INTERPRETED_SPEC -u TUNGSTEN_SPEC_QUIET '" + tungsten + "' '" + path + "' < /dev/null"

# Runs the tests of one shard, one child process at a time, from the bit
# root (the tests `use ../lib/...` relative to their file and write only to
# /tmp or argv-supplied paths). kind is "unit" (interpreted) or "native"
# (compiled). Returns the process exit status.
-> mfu_run_tests(kind, shard, tests, manifest)
  if tests.size == 0
    << "FAIL metaflip [kind] shard [shard]: no tests listed in spec/" + manifest
    exit(1)
  logs = mfu_log_dir(kind, shard)
  if !system("mkdir -p '" + logs + "'")
    << "FAIL metaflip [kind] shard [shard]: cannot create " + logs
    exit(1)
  tungsten = mfu_tungsten
  root = mfu_bit_root
  failures = []
  tests.each -> (path)
    log = logs + "/" + path.split("/").last + ".log"
    started = mfu_now
    ok = system("cd '" + root + "' && " + mfu_command(kind, tungsten, path) + " > '" + log + "' 2>&1")
    elapsed = mfu_now - started
    if ok
      << "PASS " + path + " ([elapsed]s)"
    else
      failures.push(path)
      << "FAIL " + path + " ([elapsed]s) log: " + log
      << capture("tail -n 20 '" + log + "'")
  << "metaflip [kind] shard [shard]: [tests.size - failures.size] passed, [failures.size] failed"
  system("rm -rf '" + logs + "'") if failures.size == 0
  failures.size == 0 ? 0 : 1

# One shard of spec/interpreted_tests.txt, as child interpreters.
-> mfu_run_shard(shard)
  mfu_run_tests("unit", shard, mfu_shard_tests(shard), "interpreted_tests.txt")

# One shard of the runnable tests of spec/native_tests.txt, compiled.
-> mfu_run_native_shard(shard)
  mfu_run_tests("native", shard, mfu_native_shard_tests(shard), "native_tests.txt")
