# Ulam spiral (for primes)

-> prime?(n)
  if n < 2
    return false
  if n == 2
    return true
  if n % 2 == 0
    return false
  d = 3
  while d * d <= n
    if n % d == 0
      return false
    d += 2
  true

-> ulam_cell(x, y)
  ax = x
  if ax < 0
    ax = -ax
  ay = y
  if ay < 0
    ay = -ay
  m = ax
  if ay > m
    m = ay
  if m == 0
    return 1
  base = (2 * m - 1) * (2 * m - 1)
  if x == m && y > -m
    base + (y + m)
  elsif y == m
    base + 2 * m + (m - x)
  elsif x == -m
    base + 4 * m + (m - y)
  else
    base + 6 * m + (x + m)

-> render_ulam(radius)
  y = radius
  while y >= -radius
    line = ""
    x = -radius
    while x <= radius
      v = ulam_cell(x, y)
      if prime?(v)
        line += "* "
      else
        line += ". "
      x += 1
    << line.strip
    y -= 1

render_ulam(3)

## expect stdout
## * . . . . . *
## . * . . . * .
## . . * . * . *
## . * . . * * .
## * . * . . . .
## . . . * . . .
## * . . . * . .
