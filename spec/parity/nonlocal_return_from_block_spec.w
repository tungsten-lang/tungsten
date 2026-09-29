# Control flow: non-local return from a block inside a method.
#
# Cross-engine parity spec (scripts/parity.sh).

-> find_first_even(xs)
  xs.each ->(x)
    return x if x % 2 == 0
  -1
<< "nonlocal [find_first_even([1, 3, 4, 5])] [find_first_even([1, 3])]"
