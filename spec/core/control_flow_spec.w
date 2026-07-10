# Control flow: if/elsif/else, while, case/when, suffix if, break.
#
# Run: `bin/tungsten -o /tmp/cf spec/core/control_flow_spec.w && /tmp/cf`

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

# -- if / elsif / else --
-> classify(n)
  if n > 10
    "big"
  elsif n > 5
    "medium"
  else
    "small"

check("if.big", classify(12), "big")
check("if.medium", classify(7), "medium")
check("if.small", classify(2), "small")

# Nested if
-> abs_sign(n)
  if n >= 0
    if n == 0
      "zero"
    else
      "pos"
  else
    "neg"

check("if.nested.pos", abs_sign(3), "pos")
check("if.nested.zero", abs_sign(0), "zero")
check("if.nested.neg", abs_sign(-1), "neg")

# -- while --
-> sum_to(n)
  i = 0
  total = 0
  while i < n
    i += 1
    total += i
  total

check("while.sum_to_5", sum_to(5), 15)
check("while.sum_to_0", sum_to(0), 0)

# while + break
-> count_to_break(limit)
  i = 0
  while true
    if i == limit
      break
    i += 1
  i

check("while.break", count_to_break(5), 5)

# -- case / when (subject) --
-> color_kind(c)
  case c
  when "red"
    "warm"
  when "blue"
    "cool"
  when "green"
    "nature"
  else
    "unknown"

check("case.red", color_kind("red"), "warm")
check("case.blue", color_kind("blue"), "cool")
check("case.green", color_kind("green"), "nature")
check("case.else", color_kind("purple"), "unknown")

# Integer subject
-> label(n)
  case n
  when 1
    "one"
  when 2
    "two"
  when 3
    "three"
  else
    "other"

check("case.int.1", label(1), "one")
check("case.int.2", label(2), "two")
check("case.int.3", label(3), "three")
check("case.int.else", label(99), "other")

# -- subject-less cond-case --
-> size_band(n)
  case
  when n > 10
    "big"
  when n > 5
    "medium"
  else
    "small"

check("cond.big", size_band(20), "big")
check("cond.medium", size_band(7), "medium")
check("cond.small", size_band(1), "small")

# -- suffix if (statement modifier) --
-> maybe_double(n)
  out = n
  out = n * 2 if n > 0
  out

check("suffix_if.true", maybe_double(4), 8)
check("suffix_if.false", maybe_double(0), 0)
check("suffix_if.neg", maybe_double(-3), -3)

# suffix if on return
-> early(n)
  return "pos" if n > 0
  return "zero" if n == 0
  "neg"

check("suffix_return.pos", early(1), "pos")
check("suffix_return.zero", early(0), "zero")
check("suffix_return.neg", early(-2), "neg")

<< "control_flow_spec: all checks passed"
