# Spec::Matchers — built-in matcher functions
# Each function returns a matcher object with matches?/failure_message.
#
# Usage:
#   expect(5).to eq(5)
#   expect(list).to include(3)
#   expect(nil).to be_nil
#   expect_block(-> <! "boom").to raise_error

in Tungsten:Spec

# --- Equality ---

[pure]
-> eq(expected)
  Matcher.new(
    name: "eq",
    matches: actual -> actual == expected,
    message: actual -> "expected #{actual.inspect} to equal #{expected.inspect}",
    negated: actual -> "expected #{actual.inspect} not to equal #{expected.inspect}"
  )

[pure]
-> eql(expected)
  Matcher.new(
    name: "eql",
    matches: actual -> actual.eql?(expected),
    message: actual -> "expected #{actual.inspect} to eql #{expected.inspect}",
    negated: actual -> "expected #{actual.inspect} not to eql #{expected.inspect}"
  )

[pure]
-> equal(expected)
  Matcher.new(
    name: "equal",
    matches: actual -> actual.equal?(expected),
    message: actual -> "expected #{actual.inspect} to be the same object as #{expected.inspect}",
    negated: actual -> "expected #{actual.inspect} not to be the same object as #{expected.inspect}"
  )

# --- Identity / truthiness ---

[pure]
-> be(expected)
  Matcher.new(
    name: "be",
    matches: actual -> actual.equal?(expected),
    message: actual -> "expected #{actual.inspect} to be #{expected.inspect}",
    negated: actual -> "expected #{actual.inspect} not to be #{expected.inspect}"
  )

[pure]
-> be_nil
  Matcher.new(
    name: "be_nil",
    matches: actual -> actual.nil?,
    message: actual -> "expected #{actual.inspect} to be nil",
    negated: actual -> "expected nil not to be nil"
  )

[pure]
-> be_truthy
  Matcher.new(
    name: "be_truthy",
    matches: actual -> !!actual,
    message: actual -> "expected #{actual.inspect} to be truthy",
    negated: actual -> "expected #{actual.inspect} to be falsy"
  )

[pure]
-> be_falsy
  Matcher.new(
    name: "be_falsy",
    matches: actual -> !actual,
    message: actual -> "expected #{actual.inspect} to be falsy",
    negated: actual -> "expected #{actual.inspect} to be truthy"
  )

[pure]
-> be_empty
  Matcher.new(
    name: "be_empty",
    matches: actual -> actual.empty?,
    message: actual -> "expected #{actual.inspect} to be empty",
    negated: actual -> "expected #{actual.inspect} not to be empty"
  )

# --- Type checking ---

[pure]
-> be_a(expected_class)
  Matcher.new(
    name: "be_a",
    matches: actual -> actual.is_a?(expected_class),
    message: actual -> "expected #{actual.inspect} to be a #{expected_class}",
    negated: actual -> "expected #{actual.inspect} not to be a #{expected_class}"
  )

[pure]
-> be_an(expected_class) = be_a(expected_class)

# --- Comparisons ---

[pure]
-> be_gt(expected)
  Matcher.new(
    name: "be >",
    matches: actual -> actual > expected,
    message: actual -> "expected #{actual} to be > #{expected}",
    negated: actual -> "expected #{actual} not to be > #{expected}"
  )

[pure]
-> be_lt(expected)
  Matcher.new(
    name: "be <",
    matches: actual -> actual < expected,
    message: actual -> "expected #{actual} to be < #{expected}",
    negated: actual -> "expected #{actual} not to be < #{expected}"
  )

[pure]
-> be_gte(expected)
  Matcher.new(
    name: "be >=",
    matches: actual -> actual >= expected,
    message: actual -> "expected #{actual} to be >= #{expected}",
    negated: actual -> "expected #{actual} not to be >= #{expected}"
  )

[pure]
-> be_lte(expected)
  Matcher.new(
    name: "be <=",
    matches: actual -> actual <= expected,
    message: actual -> "expected #{actual} to be <= #{expected}",
    negated: actual -> "expected #{actual} not to be <= #{expected}"
  )

[pure]
-> be_between(min, max)
  Matcher.new(
    name: "be_between",
    matches: actual -> actual >= min && actual <= max,
    message: actual -> "expected #{actual} to be between #{min} and #{max}",
    negated: actual -> "expected #{actual} not to be between #{min} and #{max}"
  )

# --- Collection matchers ---

[pure]
-> include(*expected)
  Matcher.new(
    name: "include",
    matches: actual -> expected.all?(e -> actual.include?(e)),
    message: actual -> "expected #{actual.inspect} to include #{expected.inspect}",
    negated: actual -> "expected #{actual.inspect} not to include #{expected.inspect}"
  )

[pure]
-> contain_exactly(*expected)
  Matcher.new(
    name: "contain_exactly",
    matches: actual -> actual.sort == expected.sort,
    message: actual -> "expected #{actual.inspect} to contain exactly #{expected.inspect}",
    negated: actual -> "expected #{actual.inspect} not to contain exactly #{expected.inspect}"
  )

[pure]
-> have_key(key)
  Matcher.new(
    name: "have_key",
    matches: actual -> actual.has_key?(key),
    message: actual -> "expected #{actual.inspect} to have key #{key.inspect}",
    negated: actual -> "expected #{actual.inspect} not to have key #{key.inspect}"
  )

[pure]
-> have_length(n)
  Matcher.new(
    name: "have_length",
    matches: actual -> actual.size == n,
    message: actual -> "expected #{actual.inspect} to have length #{n}, got #{actual.size}",
    negated: actual -> "expected #{actual.inspect} not to have length #{n}"
  )

# --- String matchers ---

[pure]
-> match(pattern)
  Matcher.new(
    name: "match",
    matches: actual -> actual.to_s.match?(pattern),
    message: actual -> "expected #{actual.inspect} to match #{pattern.inspect}",
    negated: actual -> "expected #{actual.inspect} not to match #{pattern.inspect}"
  )

[pure]
-> start_with(expected)
  Matcher.new(
    name: "start_with",
    matches: actual -> actual.to_s.starts_with?(expected),
    message: actual -> "expected #{actual.inspect} to start with #{expected.inspect}",
    negated: actual -> "expected #{actual.inspect} not to start with #{expected.inspect}"
  )

[pure]
-> end_with(expected)
  Matcher.new(
    name: "end_with",
    matches: actual -> actual.to_s.ends_with?(expected),
    message: actual -> "expected #{actual.inspect} to end with #{expected.inspect}",
    negated: actual -> "expected #{actual.inspect} not to end with #{expected.inspect}"
  )

# --- Respond to ---

[pure]
-> respond_to(*methods)
  Matcher.new(
    name: "respond_to",
    matches: actual -> methods.all?(m -> actual.respond_to?(m)),
    message: actual -> "expected #{actual.inspect} to respond to #{methods.inspect}",
    negated: actual -> "expected #{actual.inspect} not to respond to #{methods.inspect}"
  )

# --- Error matchers (for block expectations) ---

[pure]
-> raise_error(expected_class = nil, message: nil)
  BlockMatcher.new(
    name: "raise_error",
    matches_block: block ->
      begin
        block.call
        false
      rescue error
        class_ok = expected_class.nil? || error.is_a?(expected_class)
        msg_ok   = message.nil? || error.message.include?(message)
        class_ok && msg_ok,
    message: _block -> "expected block to raise #{expected_class || 'an error'}",
    negated: _block -> "expected block not to raise #{expected_class || 'an error'}"
  )

# --- Change matcher ---

-> change(object = nil, method = nil, &block)
  ChangeMatcher.new(object, method, block)

+ ChangeMatcher
  ro :object
  ro :method_name
  ro :value_fn

  -> new(@object, @method_name, @value_fn)

  -> by(amount)
    ChainedChangeMatcher.new(self, :by, amount)

  -> from(value)
    ChainedChangeMatcher.new(self, :from, value)

  -> matches_block?(block)
    before = current_value
    block.call
    after = current_value
    before != after

  -> current_value
    if @value_fn
      @value_fn.call
    else
      @object.send(@method_name)


# --- Matcher base ---

+ Matcher
  ro :name

  -> new(name:, matches:, message:, negated:)
    @name    = name
    @test    = matches
    @msg     = message
    @neg_msg = negated

  -> matches?(actual)
    @test.call(actual)

  -> failure_message(actual)
    @msg.call(actual)

  -> negated_failure_message(actual)
    @neg_msg.call(actual)


+ BlockMatcher
  ro :name

  -> new(name:, matches_block:, message:, negated:)
    @name       = name
    @test       = matches_block
    @msg        = message
    @neg_msg    = negated

  -> matches_block?(block)
    @test.call(block)

  -> failure_message_for_block(block)
    @msg.call(block)

  -> negated_failure_message_for_block(block)
    @neg_msg.call(block)
