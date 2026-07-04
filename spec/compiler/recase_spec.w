# Dogfood for the `recase [expr]` keyword — re-run the enclosing case.
#
#   recase expr  -> re-dispatch with expr as the new subject.
#   recase       -> re-dispatch after re-evaluating the original subject
#                   (so `case next()` advances instead of infinite-looping);
#                   on a subject-less cond-case, re-tests the conditions.
#
# `recase` only terminates when the dispatched value can change — either the
# recased expression or the re-evaluated subject must evolve toward a
# non-recasing arm. Mutable state uses one-element array cells (top-level class
# vars aren't allowed).
#
# Run: `bin/tungsten -o /tmp/rc spec/compiler/recase_spec.w && /tmp/rc`
#      `bin/tungsten run spec/compiler/recase_spec.w`  (interpreter)

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()

# -- recase expr: decrement a cell and re-dispatch on the new value until it
# lands on a terminating arm. --
-> countdown(cell)
  case cell[0]
  when 0
    "zero"
  when 1
    "one"
  when 2
    "two"
  else
    cell[0] = cell[0] - 1
    recase cell[0]

check("recase_expr.steps_down", countdown([5]), "two")
check("recase_expr.big_steps_down", countdown([20]), "two")
check("recase_expr.direct_one", countdown([1]), "one")
check("recase_expr.direct_zero", countdown([0]), "zero")

# -- recase to a constant that hits a terminating arm (no mutation needed). --
-> jump(start)
  case start
  when 0
    "done"
  else
    recase 0

check("recase_expr.constant_target", jump(9), "done")

# -- bare recase over a stateful subject: skip "ws" tokens by re-evaluating
# advance() (which mutates the position cell), return on the first real token. --
-> advance(toks, pos)
  t = toks[pos[0]]
  pos[0] = pos[0] + 1
  t

-> first_real(toks, pos)
  case advance(toks, pos)
  when "ws"
    recase
  else
    "got:" + toks[pos[0] - 1]

check("bare_recase.skips_ws", first_real(["ws", "ws", "id", "num"], [0]), "got:id")

# -- subject-less cond-case: bare recase re-tests the conditions until the
# counter cell crosses the threshold. --
-> ramp(c)
  case
  when c[0] >= 3
    c[0]
  else
    c[0] = c[0] + 1
    recase

check("cond_recase.ramps_to_3", ramp([0]), 3)

# -- nested case: an inner recase re-dispatches ONLY the inner case. --
-> nested(outer)
  case outer
  when "a"
    case 2
    when 0
      "inner-done"
    else
      recase 0
  else
    "outer-else"

check("nested.inner_recase_only", nested("a"), "inner-done")
check("nested.outer_unaffected", nested("z"), "outer-else")

# -- loop-carried LOCAL across the re-dispatch back-edge: `total` is a plain
# local (not a heap cell) mutated in an arm and read after re-dispatch. This is
# the SSA-phi-at-the-header risk; it must survive each recase. 3+2+1 == 6. --
-> accumulate(cell)
  total = 0
  case cell[0]
  when 0
    total
  else
    total = total + cell[0]
    cell[0] = cell[0] - 1
    recase cell[0]

check("recase.carries_local", accumulate([3]), 6)

# -- recase inside an `if` inside an arm (the detection scanner must find it). --
-> guarded(cell)
  case cell[0]
  when 0
    "done"
  else
    if cell[0] > 0
      cell[0] = cell[0] - 1
      recase cell[0]
    "neg"

check("recase_in_if.terminates", guarded([3]), "done")
