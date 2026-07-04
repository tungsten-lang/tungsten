# Stats — statistical functions

in Tungsten:Koala

+ Stats
  -> .sum(values)
    values = values.to_a if values.respond_to?(:to_a)
    values.reject(&:nil?).sum

  -> .mean(values)
    clean = self.clean(values)
    clean.sum.to_f / clean.size

  -> .median(values)
    sorted = self.clean(values).sort
    n = sorted.size
    return nil if n == 0
    if n.odd?
      sorted[n / 2]
    else
      (sorted[n / 2 - 1] + sorted[n / 2]) / 2.0

  -> .std(values)
    Math.sqrt(self.var(values))

  -> .var(values)
    clean = self.clean(values)
    return 0.0 if clean.size <= 1
    m = self.mean(clean)
    clean.map(-> (v) (v - m) ** 2).sum / (clean.size - 1)

  -> .min(values)
    self.clean(values).min

  -> .max(values)
    self.clean(values).max

  -> .percentile(values, p)
    sorted = self.clean(values).sort
    return nil if sorted.empty?
    k = (p / 100.0 * (sorted.size - 1))
    f = k.floor
    c = k.ceil
    if f == c
      sorted[f]
    else
      sorted[f] * (c - k) + sorted[c] * (k - f)

  -> .quantile(values, q) self.percentile(values, q * 100)

  # Pearson correlation coefficient.
  -> .corr(x, y)
    x = self.clean(x)
    y = self.clean(y)
    n = [x.size, y.size].min
    x = x.take(n)
    y = y.take(n)
    mx = self.mean(x)
    my = self.mean(y)
    cov = (0...n).map(-> (i) (x[i] - mx) * (y[i] - my)).sum / (n - 1)
    cov / (self.std(x) * self.std(y))

  # Covariance.
  -> .cov(x, y)
    x = self.clean(x)
    y = self.clean(y)
    n = [x.size, y.size].min
    mx = self.mean(x)
    my = self.mean(y)
    (0...n).map(-> (i) (x[i] - mx) * (y[i] - my)).sum / (n - 1)

  # Covariance matrix for a DataFrame.
  -> .cov_matrix(df)
    cols = df.columns
    n = cols.size
    result = Matrix.zeros(n, n)
    n.times -> (i)
      n.times -> (j)
        result[i, j] = self.cov(df[cols[i]].to_a, df[cols[j]].to_a)
    result

  # Correlation matrix for a DataFrame.
  -> .corr_matrix(df)
    cols = df.columns
    n = cols.size
    result = Matrix.zeros(n, n)
    n.times -> (i)
      n.times -> (j)
        result[i, j] = self.corr(df[cols[i]].to_a, df[cols[j]].to_a)
    result

  # Describe a Series — summary statistics.
  -> .describe(series)
    values = series.to_a
    {
      count:  values.reject(&:nil?).size,
      mean:   self.mean(values),
      std:    self.std(values),
      min:    self.min(values),
      q25:    self.percentile(values, 25),
      median: self.median(values),
      q75:    self.percentile(values, 75),
      max:    self.max(values)
    }

  # Mode — most frequent value(s).
  -> .mode(values)
    clean = self.clean(values)
    tally = clean.tally
    max_count = tally.values.max
    tally.select(-> (_, v) v == max_count).keys

  # Skewness.
  -> .skewness(values)
    clean = self.clean(values)
    n = clean.size
    m = self.mean(clean)
    s = self.std(clean)
    return 0.0 if s == 0
    (clean.map(-> (v) ((v - m) / s) ** 3).sum) * n / ((n - 1) * (n - 2))

  # Kurtosis (excess).
  -> .kurtosis(values)
    clean = self.clean(values)
    n = clean.size
    m = self.mean(clean)
    s = self.std(clean)
    return 0.0 if s == 0
    (clean.map(-> (v) ((v - m) / s) ** 4).sum / n) - 3.0

  [private]

  -> .clean(values)
    values = values.to_a if values.respond_to?(:to_a)
    values.reject(&:nil?)
