# Stats — statistical functions over plain arrays (nils ignored)
+ Stats
  # Drop nils.
  -> .clean(values)
    out = []
    values.each -> (v)
      out.push(v) if v != nil
    out

  # Stable insertion sort — avoids engine-specific Array#sort gaps.
  -> .sorted(values)
    out = []
    values.each -> (v)
      inserted = false
      next_out = []
      out.each -> (u)
        if !inserted && v < u
          next_out.push(v)
          inserted = true
        next_out.push(u)
      next_out.push(v) if !inserted
      out = next_out
    out

  -> .sum(values)
    total = 0
    self.clean(values).each -> (v)
      total += v
    total

  -> .mean(values)
    clean = self.clean(values)
    return nil if clean.size == 0
    self.sum(clean).to_f / clean.size.to_f

  -> .median(values)
    s = self.sorted(self.clean(values))
    n = s.size
    return nil if n == 0
    mid = n / 2
    if n % 2 == 1
      s[mid]
    else
      (s[mid - 1] + s[mid]).to_f / 2.to_f

  # The p-th percentile as a float, p an INTEGER percent in 0..100.
  # Linear interpolation between the two nearest order statistics —
  # numpy's default 'linear' method (a.k.a. R type-7 / Excel
  # PERCENTILE.INC), so 25/50/75 match pandas' quartiles and 50 equals
  # the median. nils are dropped first; nil for an empty (or all-nil)
  # array. p is an integer percent, never a float fraction, so no float
  # literal is needed at the call site.
  #
  # The 0-based fractional rank p/100*(n-1) is split into an integer
  # floor and remainder with pure integer arithmetic, so only the final
  # interpolation touches floats:
  #   rank = span/100 where span = p*(n-1); floor = span/100 (int div),
  #   frac = (span % 100)/100.
  -> .percentile(values, p)
    s = self.sorted(self.clean(values))
    n = s.size
    out = nil
    valid_p = p != nil
    valid_p = type(p) == "Int" if valid_p
    valid_p = p >= 0 && p <= 100 if valid_p
    if n > 0 && valid_p
      span = p * (n - 1)
      lo = span / 100
      frac = (span % 100).to_f / 100.to_f
      hi = lo + 1
      hi = n - 1 if hi > n - 1
      out = s[lo].to_f + frac * (s[hi].to_f - s[lo].to_f)
    out

  # True when EVERY non-nil value is numeric (Integer or Float).
  # False for an empty or all-nil array. Checking the whole column is
  # important: accepting [1, "oops"] because its first cell is numeric
  # would let a string leak into Matrix arithmetic and model fitting.
  -> .numeric?(values)
    seen = false
    numeric = values != nil
    if numeric
      values.each -> (v)
        if v != nil
          seen = true
          t = type(v)
          numeric = false if t != "Int" && t != "Float"
    numeric && seen

  # Most frequent non-nil value; ties break to the first seen. Works
  # for strings/symbols too. nil for an empty or all-nil array.
  -> .mode(values)
    clean = self.clean(values)
    best = nil
    best_count = 0
    seen = []
    clean.each -> (v)
      if !seen.include?(v)
        seen.push(v)
        count = 0
        clean.each -> (u)
          count += 1 if u == v
        if count > best_count
          best = v
          best_count = count
    best

  -> .min(values)
    clean = self.clean(values)
    return nil if clean.size == 0
    clean.min

  -> .max(values)
    clean = self.clean(values)
    return nil if clean.size == 0
    clean.max

  # Sample variance (n - 1 denominator); 0.0 for fewer than 2 values.
  -> .var(values)
    clean = self.clean(values)
    out = 0.to_f
    if clean.size > 1
      m = self.mean(clean)
      total = 0.to_f
      clean.each -> (v)
        d = v.to_f - m
        total += d * d
      out = total / (clean.size - 1).to_f
    out

  -> .std(values)
    Math.sqrt(self.var(values))
