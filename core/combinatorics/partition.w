# Integer partitions, Young diagrams, and symmetric-group characters.
#
# A partition is an Array of positive Ints in nonincreasing order; the empty
# partition is []. Everything here is exact. Character values come from the
# Murnaghan–Nakayama rule on beta sets (bead positions λ_i + L − i for a
# fixed number L of beads), which is also how border strips are added and
# removed: a strip of size k moves one bead from x to x ± k, and its sign is
# (−1)^(number of beads strictly between the two positions).
#
#   IntegerPartition.all(5)                  # [[5], [4, 1], [3, 2], …, [1, 1, 1, 1, 1]]
#   IntegerPartition.character([3, 2, 1], [3, 3])
#   IntegerPartition.kronecker([2, 1], [2, 1], [1, 1, 1])   # 1
#
# Fast vectorised Kronecker/plethysm recursions belong in callers; this file
# supplies the exact reference values and the strip tables they need.

+ IntegerPartition
  # All partitions of n in reverse lexicographic order (largest first).
  -> .all(n)
    IntegerPartition.all_bounded(n, n, n)

  # Partitions of n with at most max_len parts, each part at most max_part.
  -> .all_bounded(n, max_len, max_part)
    found = []
    IntegerPartition.fill_partitions(n, max_len, max_part, [], found)
    found

  -> .fill_partitions(n, max_len, max_part, prefix, found)
    if n == 0
      found.push(IntegerPartition.copy(prefix))
      return nil
    return nil if max_len == 0
    k = n
    k = max_part if max_part < k
    while k >= 1
      prefix.push(k)
      IntegerPartition.fill_partitions(n - k, max_len - 1, k, prefix, found)
      prefix.pop
      k -= 1
    nil

  -> .count(n)
    # p(n) by Euler's pentagonal recurrence.
    p = [1]
    m = 1
    while m <= n
      total = p[0] * 0
      j = 1
      while true
        g1 = j * (3 * j - 1) / 2
        g2 = j * (3 * j + 1) / 2
        break if g1 > m
        sign = 1
        sign = -1 if j % 2 == 0
        total = total + sign * p[m - g1]
        total = total + sign * p[m - g2] if g2 <= m
        j += 1
      p.push(total)
      m += 1
    p[n]

  -> .copy(p)
    out = []
    p.each -> (x)
      out.push(x)
    out

  -> .key(p)
    p.join(",")

  -> .size(p)
    s = 0
    p.each -> (x)
      s += x
    s

  -> .conjugate(p)
    out = []
    return out if p.size == 0
    j = 1
    while j <= p[0]
      c = 0
      p.each -> (x)
        c += 1 if x >= j
      out.push(c)
      j += 1
    out

  -> .self_conjugate?(p)
    IntegerPartition.same?(p, IntegerPartition.conjugate(p))

  -> .same?(a, b)
    return false if a.size != b.size
    i = 0
    while i < a.size
      return false if a[i] != b[i]
      i += 1
    true

  # a dominates b (same size): every prefix sum of a is at least b's.
  -> .dominates?(a, b)
    sa = 0
    sb = 0
    i = 0
    n = a.size
    n = b.size if b.size > n
    while i < n
      sa += a[i] if i < a.size
      sb += b[i] if i < b.size
      return false if sa < sb
      i += 1
    true

  -> .staircase(m)
    out = []
    k = m
    while k >= 1
      out.push(k)
      k -= 1
    out

  -> .hook_lengths(p)
    c = IntegerPartition.conjugate(p)
    rows = []
    i = 0
    while i < p.size
      row = []
      j = 0
      while j < p[i]
        row.push(p[i] - j - 1 + c[j] - i - 1 + 1)
        j += 1
      rows.push(row)
      i += 1
    rows

  # Number of standard Young tableaux, by the hook length formula (exact).
  -> .dimension(p)
    n = IntegerPartition.size(p)
    num = IntegerPartition.factorial(n)
    den = num / num
    IntegerPartition.hook_lengths(p).each -> (row)
      row.each -> (h)
        den = den * h
    num / den

  -> .factorial(n)
    f = n * 0 + 1
    i = 2
    while i <= n
      f = f * i
      i += 1
    f

  # z_μ = ∏ j^{m_j} m_j!, the centralizer order of a permutation of cycle type μ.
  -> .z(mu)
    counts = {}
    mu.each -> (x)
      counts[x] = (counts[x] || 0) + 1
    z = mu.size * 0 + 1
    counts.keys.each -> (j)
      m = counts[j]
      i = 0
      while i < m
        z = z * j
        i += 1
      z = z * IntegerPartition.factorial(m)
    z

  -> .class_size(mu)
    IntegerPartition.factorial(IntegerPartition.size(mu)) / IntegerPartition.z(mu)

  # Beta set with `beads` beads (beads ≥ number of parts), decreasing.
  -> .beta(p, beads)
    out = []
    i = 0
    while i < beads
      part = 0
      part = p[i] if i < p.size
      out.push(part + beads - 1 - i)
      i += 1
    out

  -> .from_beta(bs)
    sorted = bs.sort.reverse
    out = []
    l = sorted.size
    i = 0
    while i < l
      part = sorted[i] - (l - 1 - i)
      out.push(part) if part > 0
      i += 1
    out

  # Every way to add a border strip of size k: list of [partition, sign],
  # where sign = (−1)^(leg length). With max_len > 0 only results with at
  # most max_len parts are kept (rows never decrease, so this truncation is
  # exact for products of strip additions).
  -> .add_border_strips(p, k, max_len = 0)
    beads = p.size + k
    beads = max_len if max_len > 0 && max_len < beads
    return [] if p.size > beads
    bs = IntegerPartition.beta(p, beads)
    occupied = {}
    bs.each -> (b)
      occupied[b] = true
    found = []
    bs.each -> (b)
      t = b + k
      if !occupied[t]
        between = 0
        bs.each -> (c)
          between += 1 if c > b && c < t
        nb = bs.map ->(c) c
        idx = nb.index(b)
        nb[idx] = t
        sign = 1
        sign = -1 if between % 2 == 1
        found.push([IntegerPartition.from_beta(nb), sign])
    found

  # Every way to remove a border strip of size k: list of [partition, sign].
  -> .remove_border_strips(p, k)
    beads = p.size
    bs = IntegerPartition.beta(p, beads)
    occupied = {}
    bs.each -> (b)
      occupied[b] = true
    found = []
    bs.each -> (b)
      t = b - k
      if t >= 0 && !occupied[t]
        between = 0
        bs.each -> (c)
          between += 1 if c > t && c < b
        nb = bs.map ->(c) c
        idx = nb.index(b)
        nb[idx] = t
        sign = 1
        sign = -1 if between % 2 == 1
        found.push([IntegerPartition.from_beta(nb), sign])
    found

  # χ^λ(μ) by the Murnaghan–Nakayama rule, memoised on (λ, remaining μ).
  -> .character(lam, mu)
    return 0 if IntegerPartition.size(lam) != IntegerPartition.size(mu)
    memo = {}
    IntegerPartition.mn(lam, mu, 0, memo)

  -> .mn(lam, mu, i, memo)
    return 1 if i >= mu.size
    key = IntegerPartition.key(lam) + "|" + i.to_s
    hit = memo[key]
    return hit if hit != nil
    total = 0
    IntegerPartition.remove_border_strips(lam, mu[i]).each -> (pair)
      total = total + pair[1] * IntegerPartition.mn(pair[0], mu, i + 1, memo)
    memo[key] = total
    total

  # g(a, b, c) = (1/n!) Σ_μ |C_μ| χ^a(μ) χ^b(μ) χ^c(μ), exact. Reference
  # implementation for small n; it computes the full character columns.
  -> .kronecker(a, b, c)
    n = IntegerPartition.size(a)
    total = 0 * IntegerPartition.factorial(n)
    IntegerPartition.all(n).each -> (mu)
      term = IntegerPartition.class_size(mu) * IntegerPartition.character(a, mu)
      term = term * IntegerPartition.character(b, mu) * IntegerPartition.character(c, mu)
      total = total + term
    total / IntegerPartition.factorial(n)
