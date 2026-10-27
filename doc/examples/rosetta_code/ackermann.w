# Ackermann function

-> ack(m, n)
  if m == 0
    n + 1
  elsif n == 0
    ack(m - 1, 1)
  else
    ack(m - 1, ack(m, n - 1))

-> show_ack()
  (0..3).each -> (m)
    parts = []
    (0..4).each -> (n)
      parts.push("ack([m], [n]) = [ack(m, n)]")
    << parts.join("  ")

show_ack()

## expect stdout
## ack(0, 0) = 1  ack(0, 1) = 2  ack(0, 2) = 3  ack(0, 3) = 4  ack(0, 4) = 5
## ack(1, 0) = 2  ack(1, 1) = 3  ack(1, 2) = 4  ack(1, 3) = 5  ack(1, 4) = 6
## ack(2, 0) = 3  ack(2, 1) = 5  ack(2, 2) = 7  ack(2, 3) = 9  ack(2, 4) = 11
## ack(3, 0) = 5  ack(3, 1) = 13  ack(3, 2) = 29  ack(3, 3) = 61  ack(3, 4) = 125
