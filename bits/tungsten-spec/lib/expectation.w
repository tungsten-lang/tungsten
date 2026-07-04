# Spec::Expectation — expect(value).to / .not_to with matcher protocol
# The bridge between test values and matchers.

in Tungsten:Spec

# Top-level expect function — returns an Expectation wrapper
-> expect(actual)
  Expectation.new(actual)

# Expect a block to raise / yield / change
-> expect_block(&block)
  BlockExpectation.new(block)


+ Expectation
  ro :actual

  -> new(@actual)

  -> to(matcher)
    unless matcher.matches?(@actual)
      <! ExpectationFailed.new(matcher.failure_message(@actual))
    true

  -> not_to(matcher)
    if matcher.matches?(@actual)
      <! ExpectationFailed.new(matcher.negated_failure_message(@actual))
    true

  # Alias
  -> to_not(matcher) = not_to(matcher)


+ BlockExpectation
  ro :block

  -> new(@block)

  -> to(matcher)
    unless matcher.matches_block?(@block)
      <! ExpectationFailed.new(matcher.failure_message_for_block(@block))
    true

  -> not_to(matcher)
    if matcher.matches_block?(@block)
      <! ExpectationFailed.new(matcher.negated_failure_message_for_block(@block))
    true


+ ExpectationFailed < StandardError
  ro :message

  -> new(@message)
