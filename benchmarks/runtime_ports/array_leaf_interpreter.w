# Focused tree-walker coverage for direct Array view fields and ebits-aware
# indexing in the source-defined public leaves.

use core/array

-> fail_check(name, got, expected)
  << "FAIL [name]: got=[got] expected=[expected]"
  exit(1)

# Surplus arguments are an error on both engines (E_LOWER_ARITY at compile
# time where the callee is known; the interpreter raises at the call).
-> surplus_rejected?(f)
  begin
    f.call
    false
  rescue surplus_error
    true

-> check(name, got, expected)
  if got != expected || type(got) != type(expected)
    fail_check(name, got, expected)

empty = []
check("empty.size", empty.size, 0)
check("empty.empty", empty.empty?, true)
check("empty.first", empty.first, nil)
check("empty.last", empty.last, nil)

plain = [10, 20, 30, 40]
check("plain.size", plain.size, 4)
check("plain.cap", plain.cap, 8)
check("plain.empty", plain.empty?, false)
check("plain.first", plain.first, 10)
check("plain.last", plain.last, 40)
check("plain.first-extra rejected", surplus_rejected?(->() plain.first(1, 2, 3)), true)
check("plain.last-extra rejected", surplus_rejected?(->() plain.last(1, 2, 3)), true)

typed = u8[4]
typed[0] = 3
typed[1] = 129
typed[2] = 251
typed[3] = 17
check("typed.size", typed.size, 4)
check("typed.cap", typed.cap, 4)
check("typed.first", typed.first, 3)
check("typed.last", typed.last, 17)
check("typed.empty-extra rejected", surplus_rejected?(->() typed.empty?(1, 2, 3)), true)

bits = bool[3]
bits[0] = true
bits[1] = false
bits[2] = true
check("bool.first", bits.first, true)
check("bool.last", bits.last, true)

<< "interpreter: ok (plain/typed/empty arrays, exact types, and surplus arguments)"
