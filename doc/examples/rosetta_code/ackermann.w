# Ackermann function

-> ack(m, n)
  if m.zero?
    n + 1
  elsif n.zero?
    ack(m - 1, 1)
  else
    ack(m - 1, ack(m, n - 1))

0..3 ->(m)
  0..6 ->(n)
    print "ack([m], [n]) = [ack(m, n)]  "

  <<

## expect skip currently unsupported in this runtime
