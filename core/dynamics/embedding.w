# Attractor reconstruction from scalar time series: Takens delay
# embedding, autocorrelation-based delay selection, and the
# Grassberger-Procaccia correlation dimension.

+ Dynamics
  # Delay-embed a scalar series into m-dimensional vectors with lag tau:
  # v_i = [s_i, s_{i+τ}, …, s_{i+(m−1)τ}].
  -> .embed(series, m, tau)
    out = []
    span = (m - 1) * tau
    i = 0
    while i + span < series.size()
      v = []
      j = 0
      while j < m
        v = v.push(series[i + j * tau])
        j = j + 1
      out = out.push(v)
      i = i + 1
    out

  # Normalized autocorrelation of a series for lags 0..max_lag.
  -> .autocorrelation(series, max_lag)
    n = series.size()
    mean = ~0.0
    i = 0
    while i < n
      mean = mean + series[i]
      i = i + 1
    mean = mean / n
    var = ~0.0
    i = 0
    while i < n
      d = series[i] - mean
      var = var + d * d
      i = i + 1
    out = []
    lag = 0
    while lag <= max_lag
      s = ~0.0
      i = 0
      while i + lag < n
        s = s + (series[i] - mean) * (series[i + lag] - mean)
        i = i + 1
      if var > ~0.0
        out = out.push(s / var)
      else
        out = out.push(~0.0)
      lag = lag + 1
    out

  # Suggested embedding delay: the first lag where autocorrelation
  # drops below 1/e (falls back to max_lag).
  -> .suggest_tau(series, max_lag)
    acf = Dynamics.autocorrelation(series, max_lag)
    thresh = ~0.36787944117144233
    lag = 1
    while lag <= max_lag
      if acf[lag] < thresh
        return lag
      lag = lag + 1
    max_lag

  # Correlation sum C(ε): fraction of point pairs (i < j) closer than ε.
  -> .correlation_sum(points, eps)
    n = points.size()
    if n < 2
      return ~0.0
    count = 0
    i = 0
    while i < n
      j = i + 1
      while j < n
        if Dynamics.vdist(points[i], points[j]) < eps
          count = count + 1
        j = j + 1
      i = i + 1
    (count * ~2.0) / (n * (n - 1))

  # Grassberger-Procaccia correlation dimension: least-squares slope of
  # ln C(ε) against ln ε over `neps` log-spaced radii in [eps_lo, eps_hi],
  # using only radii with 0 < C(ε) < 1 (the scaling region's usable part).
  -> .correlation_dimension(points, eps_lo, eps_hi, neps)
    lx = []
    ly = []
    k = 0
    while k < neps
      f = (k + ~0.0) / (neps - 1)
      eps = eps_lo * Math.exp(f * Math.log(eps_hi / eps_lo))
      cs = Dynamics.correlation_sum(points, eps)
      if cs > ~0.0
        if cs < ~1.0
          lx = lx.push(Math.log(eps))
          ly = ly.push(Math.log(cs))
      k = k + 1
    n = lx.size()
    if n < 2
      raise "Dynamics.correlation_dimension: no scaling region — widen [eps_lo, eps_hi]"
    sx = ~0.0
    sy = ~0.0
    sxx = ~0.0
    sxy = ~0.0
    i = 0
    while i < n
      sx = sx + lx[i]
      sy = sy + ly[i]
      sxx = sxx + lx[i] * lx[i]
      sxy = sxy + lx[i] * ly[i]
      i = i + 1
    den = n * sxx - sx * sx
    if den == ~0.0
      raise "Dynamics.correlation_dimension: degenerate radii"
    (n * sxy - sx * sy) / den
