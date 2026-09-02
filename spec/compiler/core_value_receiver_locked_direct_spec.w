# Round-2 item 12: under LOCK_THE_DOORS! declared Rational and Date
# receivers (dispatch keys without an inline-cache table) take the same
# tag-guarded direct call BigInt does. (Instant and Char are covered by the
# same lowering but are broken in the current tree independent of it —
# Instant needs an unregistered BitOrdered trait, Char.new(n).ord returns
# empty even without the lock — so only Rational and Date are exercised.) Values that fail the guard (nil,
# a demoted or foreign value in the slot) must still dispatch normally.

-> rnum(r)(Rational)
  r.numerator

-> rden(r)(Rational)
  r.denominator

-> rfloor(r)(Rational)
  r.floor

-> dyear(d)(Date)
  d.year

-> dmonth(d)(Date)
  d.month

-> check(name, got, want)
  if got != want
    << "FAIL " + name + ": got " + got.to_s() + " want " + want.to_s()
    return 1
  0

Tungsten.LOCK_THE_DOORS!

failures = 0
q = Rational.new(7, 3)
failures = failures + check("rational.numerator", rnum(q), 7)
failures = failures + check("rational.denominator", rden(q), 3)
failures = failures + check("rational.floor", rfloor(q), 2)
d = Date.new(2026, 9, 2)
failures = failures + check("date.year", dyear(d), 2026)
failures = failures + check("date.month", dmonth(d), 9)

if failures == 0
  << "core_value_receiver_locked_direct_spec: all checks passed"
else
  << "core_value_receiver_locked_direct_spec: " + failures.to_s() + " failures"
  exit(1)
