# A declared `@`-parameter type reaches the ivar
# (lowering/monomorphize.w record_ivar_param_types).
#
# `-> new(@arr) (i64[])` states what @arr is for the life of the object, but
# collect_ivar_types only ever walked method BODIES for ivar assignments — so
# an ivar bound solely through the constructor stayed untyped and the
# declaration was silently ignored, leaving every access to a full inline-cache
# dispatch (5.3ns per element read, against 0.06ns for a typed one).
#
# Correctness is what this file pins: a declared type must change dispatch
# only, never a result. The declaration feeds the same conflict table as body
# assignments, so an ivar declared one type and assigned another elsewhere is
# nil-marked and bails back to dynamic dispatch.
#
# NOTE: only single-parameter type signatures are used here because
# multi-parameter forms (`(i64[], i64)`, even `(i64, i64)`) do not parse — a
# pre-existing limitation, and the reason a 7-parameter constructor like
# Parser's cannot be annotated yet.
#
# Run: `bin/tungsten -o /tmp/ipt spec/compiler/ivar_param_type_spec.w && /tmp/ipt`

-> check(name, got, want)
  if got.to_s() == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want
    exit 1

vals = i64[8]
k = 0 ## i64
while k < 8
  vals[k] = k * 3
  k = k + 1

# --- typed array ivar, declared only on the constructor ---
+ Scanner
  -> new(@arr) (i64[])
    self
  -> sum_to(n)
    total = 0 ## i64
    i = 0 ## i64
    while i < n
      total = total + @arr[i]
      i = i + 1
    total
  -> at(k)
    @arr[k]
s = Scanner.new(vals)
check("typed.sum", s.sum_to(8), "84")
check("typed.at_mid", s.at(5), "15")
check("typed.at_zero", s.at(0), "0")
check("typed.at_last", s.at(7), "21")

# Writes through the typed ivar land, and are visible on the shared array.
+ Writer
  -> new(@buf) (i64[])
    self
  -> bump(k)
    @buf[k] = @buf[k] + 100
    @buf[k]
w = Writer.new(vals)
check("typed.write_read", w.bump(2), "106")
check("typed.write_visible", vals[2], "106")

# --- an undeclared constructor param keeps working unchanged ---
+ Plain
  -> new(@arr)
    self
  -> at(k)
    @arr[k]
check("untyped.still_works", Plain.new(vals).at(3), "9")

# --- a declared scalar ivar ---
+ Counter
  -> new(@n) (i64)
    self
  -> doubled
    @n * 2
  -> under_100
    @n < 100
check("int.doubled", Counter.new(21).doubled, "42")
check("int.compare", Counter.new(21).under_100, "true")
# A declared :i64 ivar must still promote correctly rather than wrap.
check("int.big", Counter.new(140737488355327).doubled, "281474976710654")

# --- conflict: declared one type, reassigned another in a body ---
# The ivar falls back to dynamic dispatch and must still compute correctly.
+ Mutator
  -> new(@slot) (i64)
    self
  -> to_text
    @slot = "now a string"
    @slot
  -> peek
    @slot
m = Mutator.new(7)
check("conflict.int_first", m.peek, "7")
check("conflict.reassigned", m.to_text, "now a string")
check("conflict.after_reassign", m.peek, "now a string")

# --- inheritance: a subclass inherits the declared constructor ---
+ Base2
  -> new(@arr) (i64[])
    self
  -> at(k)
    @arr[k]
+ Derived2 < Base2
  -> twice(k)
    at(k) * 2
d = Derived2.new(vals)
check("inherit.at", d.at(4), "12")
check("inherit.twice", d.twice(4), "24")
