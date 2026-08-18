# Spec runner state and reporting.
# Examples run immediately as the spec file evaluates; this file holds the
# global counters, per-example reporting, and the end-of-run summary.
#
# There is no at_exit in the language yet, so a spec file must end with
# `spec_summary` (or `TungstenSpec.done`) to print totals and exit non-zero
# on failure.

$spec_pass = 0
$spec_fail = 0
$spec_pending_count = 0
$spec_depth = 0
$spec_failures = []
$spec_current_failure = nil
$spec_example_ordinal = 0
$spec_shard_count = nil
$spec_shard_index = nil
$spec_quiet = env("TUNGSTEN_SPEC_QUIET") == "1"

-> spec_set_shard(count, index)
  $spec_shard_count = count
  $spec_shard_index = index
  nil

# Optional process sharding for large suites. Each process still evaluates the
# whole spec file (so declarations and group setup are identical), but runs a
# disjoint subset of examples. The bit-suite harness uses this only for files
# whose tree-walk runtime would otherwise dominate the complete suite.
-> spec_example_runs_here?
  ordinal = $spec_example_ordinal
  count = $spec_shard_count
  index = $spec_shard_index
  $spec_example_ordinal += 1
  if count == nil
    count_text = env("TUNGSTEN_SPEC_SHARD_COUNT")
    index_text = env("TUNGSTEN_SPEC_SHARD_INDEX")
    count = count_text == nil ? 1 : count_text.to_i
    index = index_text == nil ? 0 : index_text.to_i
    if count < 1 || index < 0 || index >= count
      raise "invalid Tungsten-spec shard [index]/[count]"
    spec_set_shard(count, index)
  ordinal % count == index

# First failed expectation of the running example (see expectation.w for
# why failures are flagged rather than raised).
-> spec_flag_failure(msg)
  if $spec_current_failure == nil
    $spec_current_failure = msg
  nil

-> spec_clear_failure
  $spec_current_failure = nil
  nil

-> spec_indent
  s = ""
  i = 0
  while i < $spec_depth
    s = s + "  "
    i += 1
  s

# Depth mutators — a `$global` statement directly after a dedent misparses
# (parser bug: `$name` binds as a view-field postfix), so callers use these
# helpers where the `$` mutation is safely the first statement of a body.
-> spec_depth_up
  $spec_depth += 1
  nil

-> spec_depth_down
  $spec_depth -= 1
  nil

-> spec_record_pass(desc)
  $spec_pass += 1
  if !$spec_quiet
    << spec_indent + "PASS " + desc
  nil

-> spec_record_fail(desc, err)
  $spec_fail += 1
  $spec_failures.push("[desc] — [err]")
  << spec_indent + "FAIL " + desc + " — " + "[err]"

-> spec_record_pending(desc)
  $spec_pending_count += 1
  << spec_indent + "PEND " + desc
  nil

# Print cumulative counts; exit 1 when anything failed.
-> spec_summary
  << ""
  if $spec_failures.size > 0
    << "Failures:"
    i = 0
    while i < $spec_failures.size
      n = i + 1
      << "  [n]) " + $spec_failures[i]
      i += 1
    << ""
  total = $spec_pass + $spec_fail
  line = "[total] examples: [$spec_pass] passed, [$spec_fail] failed"
  if $spec_pending_count > 0
    line = line + ", [$spec_pending_count] pending"
  << line
  if $spec_fail > 0
    exit 1
  true

# Reset all counters (for running multiple suites in one process).
-> spec_reset
  $spec_pass = 0
  $spec_fail = 0
  $spec_pending_count = 0
  $spec_depth = 0
  $spec_failures = []
  $spec_example_ordinal = 0
  $spec_shard_count = nil
  $spec_shard_index = nil
  nil

# Configuration entry point — runs the block immediately; use it to
# register global hooks:
#   spec_configure() ->
#     before_each() -> ...
# Works on both engines.
-> spec_configure(&block)
  if block != nil
    block.call
    return nil
  &()
  nil

# Class-shaped facade kept for the documented API:
#   TungstenSpec.configure -> ...   (runs the block; use before_each inside)
#   TungstenSpec.done               (summary + exit code)
+ TungstenSpec
  -> .configure(&)
    &()
    nil

  -> .done
    spec_summary

  -> .summary
    spec_summary

  -> .reset
    spec_reset
