# Forge spec helper — a minimal, working describe/it/expect harness.
#
# The tungsten-spec bit is not currently runnable under the self-hosted
# interpreter (its DSL is built on instance_eval, which the interpreter
# does not implement, and it references an undefined TungstenSpec class).
# Until it is, this file provides the subset of its surface the forge
# specs need: describe / it, expect(...).to / .not_to, and the eq /
# be_nil / raise_error matchers, with a pass/fail summary.
#
# Run a spec file directly:
#   bin/tungsten bits/tungsten-forge/spec/router_spec.w

use forge

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

-> raise_error(error_class)
  RaiseErrorMatcher.new(error_class)

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

# The interpreter surfaces raised errors to `rescue` as their message
# string, so the raised CLASS cannot be checked here yet — this matcher
# verifies that the call raised. The class argument is kept for API
# compatibility with tungsten-spec.
+ RaiseErrorMatcher
  ro :error_class

  -> new(@error_class)

  -> matches?(actual)
    raised = false
    begin
      actual.call
    rescue e
      raised = true
    raised

  -> failure_message(actual)
    "expected the block to raise, but nothing was raised"

  -> negated_failure_message(actual)
    "expected the block not to raise, but it did"
