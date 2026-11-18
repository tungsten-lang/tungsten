# Shared complete-miter fixtures for semantic and native lifecycle checks.

-> cone_fixture_rows(count = 1, other = 4)
  rows = [[-3, 1], [-3, 2], [3, -1, -2], [-4, 2], [-4, 1], [4, -2, -1]]
  i = 0
  while i < count
    a = 5 + 3 * i
    b = a + 1
    c = b + 1
    rows.push([0 - a, 3])
    rows.push([0 - a, 0 - other])
    rows.push([0 - b, -3])
    rows.push([0 - b, other])
    rows.push([c, a, b])
    i += 1
  previous = 7
  i = 1
  while i < count
    y = 4 + 3 * count + i
    rows.push([y, 0 - previous, 0 - 7 - 3 * i])
    previous = y
    i += 1
  rows.push([0 - previous])
  rows

-> cone_fixture_flat(rows, nv)
  total = 0
  rows.each -> (c) total += c.size
  lits = i64[total]
  offs = i64[rows.size]
  lens = i64[rows.size]
  i = 0
  at = 0
  while i < rows.size
    c = rows[i]
    offs[i] = at
    lens[i] = c.size
    j = 0
    while j < c.size
      lits[at] = c[j]
      at += 1
      j += 1
    i += 1
  { "nvars": nv, "flat_ncl": rows.size, "flat_nlits": total,
    "flat_lits": lits, "flat_offs": offs, "flat_lens": lens }

# The final two functions agree on almost every random pattern, but differ
# when input 1 is false and all inputs 2..31 are true. This is a genuine SAT
# miter, not a malformed encoding, and exposes biased simulation collisions.
-> cone_rare_rows
  rows = []
  previous = 2
  y = 33
  input = 3
  while input <= 31
    rows.push([0 - y, previous])
    rows.push([0 - y, input])
    rows.push([y, 0 - previous, 0 - input])
    previous = y
    y += 1
    input += 1
  rows.push([-62, -1]); rows.push([-62, -61]); rows.push([62, 1, 61])
  rows.push([-63, -1]); rows.push([-63, -1]); rows.push([63, 1, 1])
  rows.push([-64, 62]); rows.push([-64, -63])
  rows.push([-65, -62]); rows.push([-65, 63])
  rows.push([66, 64, 65]); rows.push([-66])
  rows
