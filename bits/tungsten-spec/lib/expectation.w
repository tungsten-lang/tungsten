# Spec expectations — expect(value).to / .not_to with the matcher protocol.
#
# A failed expectation does NOT raise: raising after any nested closure
# `.call` has run inside the same method chain segfaults the interpreter
# today (verified by probe; see spec.w header). Instead the failure message
# is flagged on $spec_current_failure and `it` picks it up after the block
# returns. Consequence: an example keeps executing past a failed expect
# (soft-fail); the FIRST failure is the one reported.

-> expect(actual)
  Expectation.new(actual)

# Expect a block to raise — pass a lambda, or use the attached-block form:
#   expect(-> () risky_call).to raise_error
#   expect_block(-> boom).to raise_error
-> expect_block(&)
  b = -> () &()
  Expectation.new(b)

+ Expectation
  ro :actual

  -> new(@actual)

  -> to(matcher)
    if !matcher.matches?(@actual)
      spec_flag_failure(matcher.failure_message(@actual))
      return false
    true

  -> not_to(matcher)
    if matcher.matches?(@actual)
      spec_flag_failure(matcher.negated_failure_message(@actual))
      return false
    true

  # Alias for not_to
  -> to_not(matcher)
    not_to(matcher)
