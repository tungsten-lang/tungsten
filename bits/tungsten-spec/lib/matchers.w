# Spec matchers — each matcher function returns an object answering
# matches?(actual) / failure_message(actual) / negated_failure_message(actual).
#
# Every matcher is a concrete class with plain methods — NO stored lambdas.
# Calling a closure inside a matcher method and then unwinding an error
# through that method chain segfaults the interpreter today (see spec.w
# header), so the lambda-table style of the original design is off-limits.

# Structural equality helper: compiled Array == is identity-based, so fall
# back to comparing to_s renderings (same approach as the argon specs).
-> spec_values_equal(actual, expected)
  if actual == expected
    return true
  if actual != nil && expected != nil
    return actual.to_s == expected.to_s
  false

# --- Equality ---

-> eq(expected)
  EqMatcher.new(expected)

# eql/equal/be(value) — v1 aliases of eq (no separate identity semantics)
-> eql(expected)
  EqMatcher.new(expected)

-> equal(expected)
  EqMatcher.new(expected)

-> be(expected)
  EqMatcher.new(expected)

+ EqMatcher
  ro :expected

  -> new(@expected)

  -> matches?(actual)
    spec_values_equal(actual, @expected)

  -> failure_message(actual)
    "expected [@expected] but got [actual]"

  -> negated_failure_message(actual)
    "expected anything but [@expected]"

# --- Truthiness / nil ---

-> be_nil
  BeNilMatcher.new

+ BeNilMatcher
  -> new

  -> matches?(actual)
    actual == nil

  -> failure_message(actual)
    "expected nil but got [actual]"

  -> negated_failure_message(actual)
    "expected a value, got nil"

-> be_true
  BeTrueMatcher.new

+ BeTrueMatcher
  -> new

  -> matches?(actual)
    actual == true

  -> failure_message(actual)
    "expected true but got [actual]"

  -> negated_failure_message(actual)
    "expected anything but true"

-> be_false
  BeFalseMatcher.new

+ BeFalseMatcher
  -> new

  -> matches?(actual)
    actual == false

  -> failure_message(actual)
    "expected false but got [actual]"

  -> negated_failure_message(actual)
    "expected anything but false"

-> be_truthy
  BeTruthyMatcher.new

+ BeTruthyMatcher
  -> new

  -> matches?(actual)
    actual != nil && actual != false

  -> failure_message(actual)
    "expected [actual] to be truthy"

  -> negated_failure_message(actual)
    "expected [actual] to be falsy"

-> be_falsy
  BeFalsyMatcher.new

+ BeFalsyMatcher
  -> new

  -> matches?(actual)
    actual == nil || actual == false

  -> failure_message(actual)
    "expected [actual] to be falsy"

  -> negated_failure_message(actual)
    "expected [actual] to be truthy"

-> be_empty
  BeEmptyMatcher.new

+ BeEmptyMatcher
  -> new

  -> matches?(actual)
    actual.empty?

  -> failure_message(actual)
    "expected [actual] to be empty"

  -> negated_failure_message(actual)
    "expected [actual] not to be empty"

# --- Type ---

-> be_a(expected_class)
  BeAMatcher.new(expected_class)

-> be_an(expected_class)
  BeAMatcher.new(expected_class)

+ BeAMatcher
  ro :expected_class

  -> new(@expected_class)

  -> matches?(actual)
    actual.is_a?(@expected_class)

  -> failure_message(actual)
    "expected [actual] to be a [@expected_class]"

  -> negated_failure_message(actual)
    "expected [actual] not to be a [@expected_class]"

# --- Comparisons ---

-> be_gt(expected)
  CompareMatcher.new(:gt, ">", expected)

-> be_lt(expected)
  CompareMatcher.new(:lt, "<", expected)

-> be_gte(expected)
  CompareMatcher.new(:gte, ">=", expected)

-> be_lte(expected)
  CompareMatcher.new(:lte, "<=", expected)

+ CompareMatcher
  ro :op
  ro :op_text
  ro :expected

  -> new(@op, @op_text, @expected)

  -> matches?(actual)
    if @op == :gt
      return actual > @expected
    if @op == :lt
      return actual < @expected
    if @op == :gte
      return actual >= @expected
    if @op == :lte
      return actual <= @expected
    false

  -> failure_message(actual)
    "expected [actual] to be [@op_text] [@expected]"

  -> negated_failure_message(actual)
    "expected [actual] not to be [@op_text] [@expected]"

-> be_between(min, max)
  BeBetweenMatcher.new(min, max)

+ BeBetweenMatcher
  ro :min
  ro :max

  -> new(@min, @max)

  -> matches?(actual)
    actual >= @min && actual <= @max

  -> failure_message(actual)
    "expected [actual] to be between [@min] and [@max]"

  -> negated_failure_message(actual)
    "expected [actual] not to be between [@min] and [@max]"

# --- Collections / strings ---

-> include(expected)
  IncludeMatcher.new(expected)

+ IncludeMatcher
  ro :expected

  -> new(@expected)

  -> matches?(actual)
    actual.include?(@expected)

  -> failure_message(actual)
    "expected [actual] to include [@expected]"

  -> negated_failure_message(actual)
    "expected [actual] not to include [@expected]"

# v1: takes an array argument; order-insensitive via sort
-> contain_exactly(expected)
  ContainExactlyMatcher.new(expected)

+ ContainExactlyMatcher
  ro :expected

  -> new(@expected)

  -> matches?(actual)
    spec_values_equal(actual.sort, @expected.sort)

  -> failure_message(actual)
    "expected [actual] to contain exactly [@expected]"

  -> negated_failure_message(actual)
    "expected [actual] not to contain exactly [@expected]"

-> have_key(key)
  HaveKeyMatcher.new(key)

+ HaveKeyMatcher
  ro :key

  -> new(@key)

  -> matches?(actual)
    actual.has_key?(@key)

  -> failure_message(actual)
    "expected [actual] to have key [@key]"

  -> negated_failure_message(actual)
    "expected [actual] not to have key [@key]"

-> have_length(count)
  HaveLengthMatcher.new(count)

-> have_size(count)
  HaveLengthMatcher.new(count)

+ HaveLengthMatcher
  ro :count

  -> new(@count)

  -> matches?(actual)
    actual.size == @count

  -> failure_message(actual)
    "expected [actual] to have length [@count], got [actual.size]"

  -> negated_failure_message(actual)
    "expected [actual] not to have length [@count]"

# v1: substring match on to_s renderings (no regex objects here yet)
-> match(pattern)
  SubstringMatcher.new(pattern)

+ SubstringMatcher
  ro :pattern

  -> new(@pattern)

  -> matches?(actual)
    actual.to_s.include?(@pattern.to_s)

  -> failure_message(actual)
    "expected [actual] to match [@pattern]"

  -> negated_failure_message(actual)
    "expected [actual] not to match [@pattern]"

-> start_with(expected)
  StartWithMatcher.new(expected)

+ StartWithMatcher
  ro :expected

  -> new(@expected)

  -> matches?(actual)
    actual.to_s.starts_with?(@expected)

  -> failure_message(actual)
    "expected [actual] to start with [@expected]"

  -> negated_failure_message(actual)
    "expected [actual] not to start with [@expected]"

-> end_with(expected)
  EndWithMatcher.new(expected)

+ EndWithMatcher
  ro :expected

  -> new(@expected)

  -> matches?(actual)
    actual.to_s.ends_with?(@expected)

  -> failure_message(actual)
    "expected [actual] to end with [@expected]"

  -> negated_failure_message(actual)
    "expected [actual] not to end with [@expected]"

-> respond_to(method_name)
  RespondToMatcher.new(method_name)

+ RespondToMatcher
  ro :method_name

  -> new(@method_name)

  -> matches?(actual)
    actual.respond_to?(@method_name)

  -> failure_message(actual)
    "expected [actual] to respond to [@method_name]"

  -> negated_failure_message(actual)
    "expected [actual] not to respond to [@method_name]"

# --- Errors ---
# The interpreter surfaces raised errors to `rescue` as message strings, so
# the raised CLASS cannot be checked yet; this verifies that the call raised.
# The class argument is kept for API compatibility.

-> raise_error(expected_class = nil)
  RaiseErrorMatcher.new(expected_class)

+ RaiseErrorMatcher
  ro :expected_class

  -> new(@expected_class)

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
    "expected the block not to raise, but it raised"
