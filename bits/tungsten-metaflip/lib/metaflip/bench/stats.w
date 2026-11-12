# Statistics of the search benchmark. Every number is an IEEE double (`## f64`).
# A sample is a pair of typed arrays: the cost of each run on one axis and a
# hit flag (1.0 when the run reached the target, else 0.0). A censored run
# carries the cost it spent, so the expected running time with restarts (ERT)
# of a sample is its total cost divided by its hits.

# A closed interval.
+ Interval
  ro :lo, :hi
  -> new(@lo, @hi)

# Kaplan-Meier estimate of the time to target: the survival probability after
# each event time.
+ Survival
  ro :times, :levels
  -> new(@times, @levels)

  # Survival probability at time t.
  -> at(t) (f64) f64
    level = 1.0 ## f64
    i = 0 ## i64
    while i < @times.size && @times[i] <= t
      level = @levels[i]
      i += 1
    level

  # The first event time at which the survival probability is at most
  # 1 - q/100, or nil when the curve stays above it.
  -> quantile_time(q) (i64)
    hundred = 100.0 ## f64
    bound = (hundred - q.to_f) / hundred + 0.000000000001 ## f64
    i = 0 ## i64
    while i < @times.size
      if @levels[i] <= bound
        return @times[i]
      i += 1
    nil

+ Stats
  # The 97.5th percentile of the standard normal distribution.
  -> .z95() f64
    numerator = 1959963984540054 ## i64
    numerator.to_f / 1000000000000000.to_f

  # Infinity, the ERT of a sample without a hit.
  -> .inf() f64
    zero = 0.0 ## f64
    1.0 / zero

  # Wilson score interval, at 95%, of k successes in n trials.
  -> .wilson(k, n) (i64 i64)
    z = Stats.z95() ## f64
    trials = n.to_f ## f64
    p = k.to_f / trials ## f64
    scale = 1.0 + z * z / trials ## f64
    center = (p + z * z / (2.0 * trials)) / scale ## f64
    half = z * Math.sqrt(p * (1.0 - p) / trials + z * z / (4.0 * trials * trials)) / scale ## f64
    lo = center - half ## f64
    hi = center + half ## f64
    if lo < 0.0
      lo = 0.0
    if hi > 1.0
      hi = 1.0
    Interval.new(lo, hi)

  # Quantile q of an ascending array, interpolating linearly between order
  # statistics (numpy's default).
  -> .quantile(sorted, q) (f64[] f64) f64
    n = sorted.size ## i64
    h = (n - 1).to_f * q ## f64
    lo = Math.floor(h).to_i ## i64
    hi = lo + 1 ## i64
    if hi >= n
      hi = n - 1
    sorted[lo] + (h - lo.to_f) * (sorted[hi] - sorted[lo])

  # Total cost per hit; infinite without a hit.
  -> .ratio(total, hits) (f64 f64) f64
    if hits == 0.0
      return Stats.inf()
    total / hits

  # Expected running time with restarts of one sample.
  -> .ert(costs, hits) (f64[] f64[]) f64
    total = 0.0 ## f64
    wins = 0.0 ## f64
    i = 0 ## i64
    while i < costs.size
      total = total + costs[i]
      wins = wins + hits[i]
      i += 1
    Stats.ratio(total, wins)

  # 95% percentile interval of unsorted bootstrap replicates: with
  # k = floor(size / 40) the order statistics k and size-1-k.
  -> .percentile_interval(values) (f64[])
    sorted = values.sort
    k = sorted.size / 40 ## i64
    Interval.new(sorted[k], sorted[sorted.size - 1 - k])

  # One draw of the 63-bit LCG of the walker: the state lives in cell[0], the
  # output has 31 bits.
  -> .draw(cell) (i64[]) i64
    s = (cell[0] * 6364136223846793005 + 1442695040888963407) & 9223372036854775807 ## i64
    cell[0] = s
    (s >> 32) & 2147483647

  # A uniform index below n (multiply-shift range reduction).
  -> .pick(cell, n) (i64[] i64) i64
    (Stats.draw(cell) * n) >> 31

  # A generator cell seeded with `seed`.
  -> .generator(seed) (i64) i64[]
    cell = i64[1]
    cell[0] = seed & 9223372036854775807
    cell

  # FNV-1a over the bytes of a string, modulo 2^64 (as a signed integer).
  -> .fnv1a(text) (String) i64
    h = 0 - 3750763034362895579 ## i64
    i = 0 ## i64
    while i < text.size
      h = (h ^ text.byte_at(i)) * 1099511628211
      i += 1
    h

  # The FNV-1a hash folded to 62 bits: the seed of a bootstrap stream, for
  # example of a (task, algorithm) pair.
  -> .seed_of(text) (String) i64
    Stats.fnv1a(text) & 4611686018427387903

  # Resamples the runs once with replacement: [total cost, hits].
  -> .resample(costs, hits, cell) (f64[] f64[] i64[])
    n = costs.size ## i64
    total = 0.0 ## f64
    wins = 0.0 ## f64
    i = 0 ## i64
    while i < n
      j = Stats.pick(cell, n) ## i64
      total = total + costs[j]
      wins = wins + hits[j]
      i += 1
    [total, wins]

  # Bootstrap interval of the ERT: `reps` resamples of the runs.
  -> .ert_interval(costs, hits, seed, reps) (f64[] f64[] i64 i64)
    cell = Stats.generator(seed)
    values = f64[reps]
    r = 0 ## i64
    while r < reps
      draw = Stats.resample(costs, hits, cell)
      values[r] = Stats.ratio(draw[0], draw[1])
      r += 1
    Stats.percentile_interval(values)

  # The entries of `values` whose flag equals `want`, ascending.
  -> .select(values, flags, want) (f64[] f64[] f64) f64[]
    kept = 0 ## i64
    i = 0 ## i64
    while i < values.size
      if flags[i] == want
        kept += 1
      i += 1
    out = f64[kept]
    at = 0 ## i64
    i = 0
    while i < values.size
      if flags[i] == want
        out[at] = values[i]
        at += 1
      i += 1
    out.sort

  # Kaplan-Meier estimate from the time of each run and whether the run
  # reached the target then (1.0) or was censored (0.0). A censoring at the
  # time of an event stays in the risk set.
  -> .kaplan_meier(times, events) (f64[] f64[])
    hit_times = Stats.select(times, events, 1.0)
    cut_times = Stats.select(times, events, 0.0)
    total_hits = hit_times.size ## i64
    steps = f64[total_hits]
    levels = f64[total_hits]
    count = 0 ## i64
    level = 1.0 ## f64
    a = 0 ## i64
    b = 0 ## i64
    while a < total_hits
      t = hit_times[a] ## f64
      d = 0 ## i64
      while a + d < total_hits && hit_times[a + d] == t
        d += 1
      while b < cut_times.size && cut_times[b] < t
        b += 1
      at_risk = (total_hits - a + cut_times.size - b).to_f ## f64
      level = level * (at_risk - d.to_f) / at_risk
      steps[count] = t
      levels[count] = level
      count += 1
      a += d
    times_out = f64[count]
    levels_out = f64[count]
    i = 0 ## i64
    while i < count
      times_out[i] = steps[i]
      levels_out[i] = levels[i]
      i += 1
    Survival.new(times_out, levels_out)
