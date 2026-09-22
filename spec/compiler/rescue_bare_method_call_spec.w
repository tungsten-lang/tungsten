# A bare identifier inside a method body that names an instance method of the
# class hierarchy is an implicit `self.name` CALL, and that call can raise.
# Before 2026-09-22 the closed-world no-raise analysis (lowering/no_raise.w)
# summarized such a `:var` as a plain variable read, proved the `begin` body
# "cannot raise", and elided the landing pad — so `verify!`'s raise escaped
# `verified?`'s rescue in core/algebra (PMaximalOrderCertificate) and
# spec/core/algebra_prime_ideals_spec.w diverged between the engines.
#
# Run: `bin/tungsten -o /tmp/rbm spec/compiler/rescue_bare_method_call_spec.w && /tmp/rbm`
# and `bin/tungsten run --interpret $PWD/spec/compiler/rescue_bare_method_call_spec.w`

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

+ Base
  -> inherited_boom
    raise "inherited boom"

+ Checker < Base
  -> new(@flag)
    @cache = nil

  -> verify!
    return true if @cache == true
    if @flag < 2
      raise "boom flag"
    @cache = true
    true

  # The core certificate idiom: assignment from a bare `!` method call.
  -> verified?
    answer = false
    begin
      answer = verify!
    rescue error
      answer = false
    answer

  # Bare call as a statement, nothing assigned.
  -> bare_statement
    answer = true
    begin
      verify!
    rescue error
      answer = false
    answer

  # Bare call resolved through the superclass chain.
  -> bare_inherited
    answer = true
    begin
      inherited_boom
    rescue error
      answer = false
    answer

  # The rescued message must be the callee's, not a later one.
  -> rescued_message
    message = ""
    begin
      verify!
    rescue error
      message = "[error]"
    message

  # A local shadows the method: this begin body really cannot raise.
  -> shadowed_local
    inherited_boom = 7
    answer = 0
    begin
      answer = inherited_boom
    rescue error
      answer = -1
    answer

failing = Checker.new(1)
passing = Checker.new(5)
check("verified.raising", failing.verified?, false)
check("verified.passing", passing.verified?, true)
check("bare_statement", failing.bare_statement, false)
check("bare_inherited", failing.bare_inherited, false)
check("rescued_message", failing.rescued_message, "boom flag")
check("shadowed_local", failing.shadowed_local, 7)
<< "rescue_bare_method_call_spec: all checks passed"
