# `clock_ms` must work as a BARE name, on both engines.
#
# Regression: the zero-arg builtin was registered nowhere — not in
# `mod[:known_calls]` (compiler/lib/lowering.w) and not in `builtin_names` plus
# its `when` arm (compiler/lib/builtins.w) — even though the runtime extern
# `__w_clock_ms` existed and `clock_ms()` WITH parens worked. A bare `clock_ms`
# parsed as an unassigned variable and silently evaluated to nil, so
# `clock_ms - t0` died with "expected int, got nil".
#
# Bare is the idiomatic form (Tungsten takes no empty parens on zero-arg calls),
# so the broken spelling was the one everybody writes.
#
# Run: `bin/tungsten -o /tmp/cms spec/core/clock_ms_spec.w && /tmp/cms`
#      `bin/tungsten run spec/core/clock_ms_spec.w`   (engine parity)

-> check(name, ok)
  if ok
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

t0 = clock_ms
check("clock_ms.not_nil", t0 != nil)
check("clock_ms.positive", t0 > 0)

# Monotonic, and arithmetic on the result works (the original failure mode was
# a nil operand here, not a wrong value).
t1 = clock_ms
check("clock_ms.monotonic", t1 >= t0)
delta = t1 - t0
check("clock_ms.subtractable", delta >= 0)

# Milliseconds, not seconds: a plausible epoch-ish magnitude rules out a unit
# mix-up with `clock` (which returns float seconds).
check("clock_ms.milliseconds", t0 > 1000)

# The paren form must keep working too — it always did, and the fix must not
# trade one spelling for the other.
t2 = clock_ms()
check("clock_ms.parens_still_work", t2 >= t1)
