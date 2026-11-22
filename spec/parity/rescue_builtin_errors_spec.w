# Errors raised by builtins are rescuable on every engine, as the Core error
# class with its message: Array#insert before the start (IndexError), an
# integer division by zero, and a surplus argument to Array#first on an
# erased receiver (the arity contract). The Ruby implementation used to let
# Ruby's native IndexError escape `rescue` and silently ran first(n).
#
# Cross-engine parity spec (scripts/parity.sh; also --engines ...,ruby).

-> first_of(xs, n)
  xs.first(n)

-> divide(a, b)
  a / b

begin
  [1, 2].insert(-4, 0)
rescue e
  << "caught " + e.class_name + ": " + e.message
<< "after insert"

begin
  divide(1, 0)
rescue e
  << "caught " + e.class_name + ": " + e.message

begin
  first_of([1, 2], -1)
  << "FAIL first(-1) did not raise"
rescue e
  << "caught " + e.to_s
<< [3, 4].first
