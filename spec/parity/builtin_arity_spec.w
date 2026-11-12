# Arity contracts on runtime builtins: a method implemented natively (a
# `w_ic_*` inline-cache row — Array#push, String#slice, Hash#keys,
# Int#times, …) or by a Core source body reached through type-class dispatch
# (Array#size, Array#first, Int#abs, Float#to_i) rejects a call with the
# wrong argument count on an erased receiver, on both engines, with the same
# rescuable message (a Core source method's message ends at "padded"):
#
#   'push' takes 1 argument, got 2 — arguments are never silently dropped or
#   padded; Array#push is a runtime builtin with a fixed signature, so fix the call
#
# Receivers are erased through an untyped container so neither engine can
# resolve the class statically (a statically known receiver is E_LOWER_ARITY
# at compile time on the compiled engine, before any output). A trailing
# block counts as one argument — that is how a block reaches a builtin.
#
# Variadic rows (max -1 in runtime/runtime.c and builtin_arity.w) would be
# unchecked above their minimum; no current row is variadic, so every builtin
# below has a closed contract.
#
# Cross-engine parity spec (scripts/parity.sh).

-> try(label, f)
  begin
    r = f.call
    << "[label] -> [r]"
  rescue e
    << "[label] ! [e]"

things = [[3, 1, 2], "hello", {a: 1}, 7, ~6.25]
arr = things[0]
s = things[1]
h = things[2]
n = things[3]
f = things[4]

# Array — native rows
try("arr.push", ->() arr.push)
try("arr.push(4, 5)", ->() arr.push(4, 5))
try("arr.pop(1)", ->() arr.pop(1))
try("arr.get(0, 1)", ->() arr.get(0, 1))
try("arr.sum(1, 2)", ->() arr.sum(1, 2))
try("arr.sort(1, 2)", ->() arr.sort(1, 2))
try("arr.count(1) -> block", ->() arr.count(1) -> (x) x > 1)
try("arr.include?", ->() arr.include?)
# Array — Core source bodies through type-class dispatch
try("arr.size(5)", ->() arr.size(5))
try("arr.first(10)", ->() arr.first(10))
try("arr.take", ->() arr.take)
# Array — accepted shapes still work
try("arr.push(4)", ->() arr.push(4))
try("arr.sum(10)", ->() arr.sum(10))
try("arr.count -> block", ->() arr.count -> (x) x > 1)
try("arr.sort -> block", ->() arr.sort -> (a, b) b <=> a)
try("arr.first", ->() arr.first)
try("arr.take(2)", ->() arr.take(2))

# String
try("s.size(1)", ->() s.size(1))
try("s.strip(1)", ->() s.strip(1))
try("s.include?", ->() s.include?)
try("s.slice(1, 2, 3)", ->() s.slice(1, 2, 3))
try("s.to_i(16, 2)", ->() s.to_i(16, 2))
try("s.index", ->() s.index)
try("s.slice(1, 2)", ->() s.slice(1, 2))
try("s.index(\"l\", 3)", ->() s.index("l", 3))
try("\"ff\".to_i(16)", ->() things[1].replace("hello", "ff").to_i(16))

# Hash
try("h.keys(1)", ->() h.keys(1))
try("h.values(1)", ->() h.values(1))
try("h.has_key?", ->() h.has_key?)
try("h.set(:b)", ->() h.set(:b))
try("h.has_key?(:a)", ->() h.has_key?(:a))

# Int
try("n.abs(1)", ->() n.abs(1))
try("n.isqrt(1)", ->() n.isqrt(1))
try("n.times(1, 2)", ->() n.times(1, 2))
try("n.abs", ->() n.abs)
try("n.isqrt", ->() n.isqrt)

# Float
try("f.to_i(1)", ->() f.to_i(1))
try("f.sqrt(1)", ->() f.sqrt(1))
try("f.to_s(1)", ->() f.to_s(1))
try("f.to_i", ->() f.to_i)
try("f.sqrt", ->() f.sqrt)
