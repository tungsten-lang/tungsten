# Ackermann function

-> ack(m, n)
  if m == 0
    n + 1
  elsif n == 0
    ack(m - 1, 1)
  else
    ack(m - 1, ack(m, n - 1))

(0..3).each -> (m)
  line = (0..6).map -> (n) "ack([m], [n]) = [ack(m, n)]"
  << line.join("  ")

## expect skip compiled-only for now — the Ruby interpreter (which runs this harness) can't execute it; try `bin/tungsten ackermann.w`
## expect stdout
## ack(0, 0) = 1  ack(0, 1) = 2  ack(0, 2) = 3  ack(0, 3) = 4  ack(0, 4) = 5  ack(0, 5) = 6  ack(0, 6) = 7
## ack(1, 0) = 2  ack(1, 1) = 3  ack(1, 2) = 4  ack(1, 3) = 5  ack(1, 4) = 6  ack(1, 5) = 7  ack(1, 6) = 8
## ack(2, 0) = 3  ack(2, 1) = 5  ack(2, 2) = 7  ack(2, 3) = 9  ack(2, 4) = 11  ack(2, 5) = 13  ack(2, 6) = 15
## ack(3, 0) = 5  ack(3, 1) = 13  ack(3, 2) = 29  ack(3, 3) = 61  ack(3, 4) = 125  ack(3, 5) = 253  ack(3, 6) = 509
