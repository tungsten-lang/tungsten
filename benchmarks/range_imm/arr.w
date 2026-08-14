# Escaped-range workload — ranges that survive as VALUES.
#
# Each range is stored through an array cell and reloaded before use, so
# neither pipeline fusion nor range-elision (#49) can substitute the
# literal: the compiler must materialize the range value itself. Today
# that value is an eagerly-built Array (lower_range); once immediate
# Range producers land, the same shape becomes an O(1) packed value.
#
# Reads exercised per iteration: first, last, size, include?, sum.
# Prints a checksum so before/after runs validate against each other.

fn work(iters, len)
  cells = [0, 0, 0, 0, 0, 0, 0, 0]
  total = 0
  i = 0
  while i < iters
    lo = i % 1000
    hi = lo + len
    cells[i & 7] = (lo..hi)
    r = cells[i & 7]
    total = total + r.first + r.last + r.size
    if r.include?(lo + 32)
      total = total + 1
    total = total + r.sum
    i += 1
  total

<< work(2000000, 64)
