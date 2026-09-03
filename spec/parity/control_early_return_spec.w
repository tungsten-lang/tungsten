# Control flow: early return with postfix if, non-local return from a
# block inside a method, return of nil, return inside while.
#
# Cross-engine parity spec (scripts/parity.sh).

-> early(n)
  return "pos" if n > 0
  return "zero" if n == 0
  "neg"
<< "early [early(1)] [early(0)] [early(-1)]"
-> first_over(limit)
  i = 0
  while true
    i += 1
    return i if i * i > limit
<< "while.return [first_over(50)]"
-> bare_return(n)
  if n > 0
    return
  "kept"
<< "bare.return [bare_return(-1)] [bare_return(1) == nil]"
