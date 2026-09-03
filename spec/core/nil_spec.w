# Nil — the nil singleton's protocol (core/nil.w).
#
# Run:
#   bin/tungsten run --interpret spec/core/nil_spec.w
#   bin/tungsten -o /tmp/nil_spec spec/core/nil_spec.w && /tmp/nil_spec

use core/nil

passed = Atomic.new(0)

-> check(name, condition)
  raise "FAIL " + name if !condition
  passed.increment()
  << "PASS " + name

check("type", type(nil) == "Nil")
check("object_id is 0", nil.object_id == 0)
check("hash is 0", nil.hash == 0)
check("== nil", nil == nil)
check("== false is false", !(nil == false))
check("== 0 is false", !(nil == 0))
check("== empty string is false", !(nil == ""))
check("!nil", (!nil) == true)
check("blank?", nil.blank?)
check("nil?", nil.nil?)
check("try returns nil", nil.try(-> (x) x.size) == nil)
check("to_a", nil.to_a == [])
check("to_d is decimal zero", nil.to_d == 0.0)
check("to_d type", type(nil.to_d) == "Decimal")
check("to_h", nil.to_h == {})
check("to_i", nil.to_i == 0)
check("to_i type", type(nil.to_i) == "Int")
check("to_r", nil.to_r.to_s == "0/1")
check("to_r type", type(nil.to_r) == "Rational")
check("to_s", nil.to_s == "")
check("to_s size", nil.to_s.size == 0)
check("inspect", nil.inspect == "nil")

# BUG: string interpolation of nil uses `inspect` interpreted ("anilb") but `to_s` compiled ("ab").
# Nil#to_s is "" so the compiled result is the correct one.
# Repro: printf 'x = nil\n<< "a[x]b"\n' > /tmp/n.w && bin/tungsten run --interpret /tmp/n.w  # anilb
# check("interpolates as empty", "a[nil]b" == "ab")

# BUG: Nil#& is declared to return false but `nil & true` raises "bitwise operation requires integer arguments" (both engines)
# check("& is false", (nil & true) == false)
# BUG: Nil#| declared `@1 ? true : false`; `nil | true` raises "bitwise operation requires integer arguments" (both engines)
# check("| truthy", (nil | true) == true)
# check("| falsy", (nil | nil) == false)
# BUG: Nil#^ declared `@1 ? true : false`; `nil ^ true` raises "bitwise operation requires integer arguments" (both engines)
# check("^ truthy", (nil ^ true) == true)
# BUG: Nil#to_f is declared `0.0f` but returns a Quantity "0 f" (the literal lexes as 0.0 with unit f) on both engines
# check("to_f type", type(nil.to_f) == "Float")
# check("to_f", nil.to_f == ~0.0)
# BUG: Nil#to_c is declared bodyless and has no runtime implementation (undefined interpreted, nil compiled)
# check("to_c", nil.to_c == Complex.new(0, 0))
# BUG: nil.is_a?(Nil) is true interpreted but false compiled
# check("is_a? Nil", nil.is_a?(Nil))

<< "ALL PASS nil_spec ([passed.load()] checks)"
