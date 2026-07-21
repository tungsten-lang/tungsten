# A `<<` at the START of a `->(params)` lambda body is a PUTS (print), not a
# left-shift. The lexer classifies `<<` as LSHIFT after a value-type token and
# PUTS_OP otherwise; the `)` closing a lambda param list is *not* a value, so
# the body-opening `<<` must stay a PUTS. Before the fix, `[1,2,3] ->(x) << x`
# raised `E_PARSE_UNEXPECTED_TOKEN` on the `<<`. A regression re-lexes it as
# LSHIFT and this file fails to parse — failing the spec at build time — but we
# also assert observable behavior below.
#
# Run: `bin/tungsten -o /tmp/lpb spec/compiler/lambda_puts_body_spec.w && /tmp/lpb`
#      `bin/tungsten run spec/compiler/lambda_puts_body_spec.w`  (interpreter)

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

# -- The reported bug: `<<` opens the single-expression body as a puts. The
# implicit `each` returns its receiver, so the whole expression yields the
# original array once the body parses and runs. --
# NOTE: `[...]` inside a double-quoted string interpolates, so every expected
# array rendering escapes its brackets as `\[ ... \]`.
r = [1, 2, 3] ->(x) << x * 2
check("puts_body.each_returns_receiver", r.to_s(), "\[1, 2, 3\]")

# -- A `.map` with a puts body runs the block per element (proving it's a
# callable block, not a shift or parse error). puts returns nil, so we assert
# on the result size — nil-element rendering differs across engines. --
m = [1, 2].map ->(x) << x
check("puts_body.map_runs_body", m.size(), 2)

# -- Multi-parameter param list closes the same way. --
mp = [4, 5] ->(a, b) << a
check("puts_body.multi_param_ok", mp.to_s(), "\[4, 5\]")

# -- Empty param list `->()` still marks the closing `)` as lambda params, so
# `<< 7` is a puts body (returning nil), not a shift. --
z = ->() << 7
check("puts_body.empty_params_ok", z.call == nil, true)

# -- A `(...)` value paren AFTER the puts must still lex as a value paren, not a
# second lambda-param list: `<< (x + 1)` prints x+1 and `each` returns [10]. --
n = [10] ->(x) << (x + 1)
check("puts_body.value_paren_after_puts", n.to_s(), "\[10\]")

# -- Regression guard for the LSHIFT direction: `<<` after an identifier inside
# the body is still append, not a puts. The lambda-params latch must clear
# after the first body token. --
acc = []
[1, 2, 3] ->(x) acc << x * 2
check("append_body.lshift_preserved", acc.to_s(), "\[2, 4, 6\]")

# -- A parenthesized value followed by `<<` (no lambda) is still a shift. --
check("shift.paren_value_still_lshift", (1 << 4), 16)

<< "lambda_puts_body_spec: all checks passed"
