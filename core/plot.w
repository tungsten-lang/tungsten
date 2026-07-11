# Plot — terminal sparklines / heatmaps (zero-dep).
# Richer braille canvas: bits/tungsten-drawille (also defines Plot/Canvas —
# bit path wins when the bit is loaded; this core Plot is the fallback).

+ Plot
  # ASCII levels as a list of 1-char strings (avoids String#[] edge cases).
  # Full braille canvas: bits/tungsten-drawille.

  -> .spark_chars
    [".", ":", "-", "=", "+", "*", "#", "%", "@", "#"]

  -> .sparkline(xs)
    n = xs.size()
    if n == 0
      return ""
    lo = xs[0] + ~0.0
    hi = xs[0] + ~0.0
    i = 0
    while i < n
      v = xs[i] + ~0.0
      if v < lo
        lo = v
      if v > hi
        hi = v
      i = i + 1
    span = hi - lo
    if span == ~0.0
      span = ~1.0
    chars = Plot.spark_chars
    levels = chars.size()
    out = ""
    i = 0
    while i < n
      v = xs[i] + ~0.0
      t = (v - lo) / span
      ii = Math.floor(t * (levels - 1 + ~0.0)).to_i
      if ii < 0
        ii = 0
      if ii >= levels
        ii = levels - 1
      out = out + chars[ii]
      i = i + 1
    out

  # Simple ASCII heatmap for 2-D list-of-lists or Grid.
  -> .heatmap(rows, chars = " .:-=+*#%@")
    # rows: list of list of float
    m = rows.size()
    if m == 0
      return ""
    n = rows[0].size()
    lo = rows[0][0]
    hi = rows[0][0]
    i = 0
    while i < m
      j = 0
      while j < n
        v = rows[i][j]
        if v < lo
          lo = v
        if v > hi
          hi = v
        j = j + 1
      i = i + 1
    span = hi - lo
    if span == ~0.0
      span = ~1.0
    levels = chars.size()
    out = ""
    i = 0
    while i < m
      j = 0
      while j < n
        t = (rows[i][j] - lo) / span
        idx = Math.floor(t * (levels - ~1.0)).to_i
        if idx < 0
          idx = 0
        if idx >= levels
          idx = levels - 1
        out = out + chars[idx]
        j = j + 1
      out = out + "\n"
      i = i + 1
    out

  -> .array_plot(arr)
    # Array of numbers → sparkline string (also printed).
    xs = []
    i = 0
    while i < arr.size()
      xs = xs.push(arr[i] + ~0.0)
      i = i + 1
    s = Plot.sparkline(xs)
    << s
    s

  -> .grid_plot(a)
    if a.ndim == 1
      return Plot.array_plot(a.to_a)
    if a.ndim == 2
      s = Plot.heatmap(a.to_a)
      << s
      return s
    s = Plot.sparkline(a.materialize_flat())
    << s
    s

  # Line chart as coarse ASCII (rows × cols character grid).
  -> .line(xs, ys, cols = 60, rows = 15)
    n = xs.size()
    if n == 0
      return ""
    xlo = xs[0]
    xhi = xs[0]
    ylo = ys[0]
    yhi = ys[0]
    i = 0
    while i < n
      if xs[i] < xlo
        xlo = xs[i]
      if xs[i] > xhi
        xhi = xs[i]
      if ys[i] < ylo
        ylo = ys[i]
      if ys[i] > yhi
        yhi = ys[i]
      i = i + 1
    xspan = xhi - xlo
    yspan = yhi - ylo
    if xspan == ~0.0
      xspan = ~1.0
    if yspan == ~0.0
      yspan = ~1.0
    # grid of spaces
    grid = []
    r = 0
    while r < rows
      row = []
      c = 0
      while c < cols
        row = row.push(" ")
        c = c + 1
      grid = grid.push(row)
      r = r + 1
    i = 0
    while i < n
      c = Math.floor((xs[i] - xlo) / xspan * (cols - ~1.0)).to_i
      r = Math.floor((yhi - ys[i]) / yspan * (rows - ~1.0)).to_i
      if c < 0
        c = 0
      if c >= cols
        c = cols - 1
      if r < 0
        r = 0
      if r >= rows
        r = rows - 1
      grid[r][c] = "*"
      i = i + 1
    out = ""
    r = 0
    while r < rows
      c = 0
      while c < cols
        out = out + grid[r][c]
        c = c + 1
      out = out + "\n"
      r = r + 1
    << out
    out

# Monkey-patch style helpers on Array via free functions used by Grid#plot.
# Prefer `Plot.array_plot(arr)` explicitly from scripts.
