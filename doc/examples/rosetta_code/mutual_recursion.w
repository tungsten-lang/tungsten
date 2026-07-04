# Mutual recursion (Hofstadter Female and Male sequences)

-> f(n)
  if n == 0
    1
  else
    n - m(f(n - 1))

-> m(n)
  if n == 0
    0
  else
    n - f(m(n - 1))

0.upto(20) { |i|
  print "F([i])=[f(i)] "
}
puts ""
0.upto(20) { |i|
  print "M([i])=[m(i)] "
}
puts ""

## expect skip currently unsupported in this runtime
