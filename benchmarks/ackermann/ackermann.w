fn ackermann_nz(m, n)
  return ackermann(m - 1, 1) if n.zero?
  ackermann(m - 1, ackermann(m, n - 1))

fn ackermann(m, n)
  return n + 1 if m.zero?
  ackermann_nz(m, n)

<< ackermann(3, 12)
