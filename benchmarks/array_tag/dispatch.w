# IC-dispatch-heavy array workload: method calls on receivers the
# compiler cannot statically type (reloaded from a cell), so every call
# goes through w_method_dispatch / inline caches keyed by
# w_dispatch_key. The tag move keeps the key (0x0A) stable — this
# must not regress.

fn work(iters)
  cells = [0, 0]
  cells[0] = [1, 2, 3, 4, 5, 6, 7, 8]
  cells[1] = [9, 10, 11, 12]
  total = 0
  i = 0
  while i < iters
    r = cells[i & 1]
    total = total + r.first + r.last + r.size + r.sum
    if r.empty?
      total = total - 1000
    i += 1
  total

<< work(12000000)
