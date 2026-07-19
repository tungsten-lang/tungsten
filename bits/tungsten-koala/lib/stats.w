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

  -> .min(values)
    clean = self.clean(values)
    return nil if clean.size == 0
    clean.min

  -> .max(values)
    clean = self.clean(values)
    return nil if clean.size == 0
    clean.max

  # Sample variance (n - 1 denominator).
  -> .var(values)
    clean = self.clean(values)
    return 0.to_f if clean.size <= 1
    m = self.mean(clean)
    total = 0.to_f
    clean.each -> (v)
      d = v.to_f - m
      total += d * d
    total / (clean.size - 1).to_f

  -> .std(values)
    Math.sqrt(self.var(values))
