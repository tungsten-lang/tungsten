# Flame spec helper — a minimal, working describe/it/expect harness.
#
# Mirrors bits/tungsten-forge/spec/spec_helper.w: the tungsten-spec bit
# is not currently runnable under the self-hosted interpreter, so this
# file provides the subset of its surface the flame specs need:
# describe / it, expect(...).to / .not_to, the eq / be_nil matchers,
# and a pass/fail summary.
#
# Run a spec file directly:
#   bin/tungsten bits/tungsten-flame/spec/parsing_spec.w

$spec_pass = 0
$spec_fail = 0
$spec_depth = 0

-> spec_indent
  s = ""
  i = 0
  while i < $spec_depth
    s = s + "  "
    i += 1
  s

-> describe(name, &)
  << spec_indent + name
  $spec_depth += 1
  &()
  $spec_depth -= 1

-> it(name, &)
  failed = nil
  begin
    &()
  rescue e
    failed = e
  if failed == nil
    $spec_pass += 1
    << spec_indent + "PASS " + name
  else
    $spec_fail += 1
    << spec_indent + "FAIL " + name + " — " + "[failed]"

# Prints the cumulative counts; exits non-zero when anything failed.
-> spec_summary
  << ""
  total = $spec_pass + $spec_fail
  << "[total] examples, [$spec_fail] failures"
  exit 1 if $spec_fail > 0

# --- Expectations ---

-> expect(actual)
  Expectation.new(actual)

+ Expectation
  ro :actual

  -> new(@actual)

  -> to(matcher)
    if !matcher.matches?(@actual)
      <! matcher.failure_message(@actual)
    true

  -> not_to(matcher)
    if matcher.matches?(@actual)
      <! matcher.negated_failure_message(@actual)
    true

# --- Matchers ---

-> eq(expected)
  EqMatcher.new(expected)

-> be_nil
  BeNilMatcher.new

+ EqMatcher
  ro :expected

  -> new(@expected)

  -> matches?(actual)
    actual == @expected

  -> failure_message(actual)
    "expected [@expected], got [actual]"

  -> negated_failure_message(actual)
    "expected anything but [@expected]"

+ BeNilMatcher
  -> new

  -> matches?(actual)
    actual == nil

  -> failure_message(actual)
    "expected nil, got [actual]"

  -> negated_failure_message(actual)
    "expected a value, got nil"
