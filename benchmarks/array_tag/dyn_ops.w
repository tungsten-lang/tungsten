# Boxed polymorphic array workload — construction, push, index, size,
# each, include? on arrays that survive as values (stored and reloaded
# through a cell so nothing elides). Exercises runtime array functions
# and dynamic dispatch on the hottest subtag → the W_TAG_ARRAY move must
# keep this at parity or better.

fn work(iters)
  cells = [0, 0, 0, 0]
  total = 0
  i = 0
  while i < iters
    a = [i, i + 1, i + 2]
    a.push(i & 7)
    a.push(i % 5)
    cells[i & 3] = a
    r = cells[i & 3]
    total = total + r[0] + r[2] + r[4] + r.size
    if r.include?(3)
      total = total + 1
    acc = 0
    r.each -> (x)
      acc = acc + x
    total = total + acc
    i += 1
  total

<< work(6000000)
