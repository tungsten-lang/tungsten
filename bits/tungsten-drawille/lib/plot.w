# Plot — render a polynomial P(x) over a range as a braille line chart.
#
# `coeffs` is the dense coefficient list [c0, c1, c2, …] for
# P(x) = c0 + c1·x + c2·x² + …  — exactly the normal form the compiler's
# Σ-analysis produces, so `range/Σ(2x + 3)` plots with coeffs [3, 2].
#
# The curve is braille (2×4 sub-cell dots); the axes are dimmed `-` / `|`
# rather than box-drawing, so consecutive axis cells keep the small gaps those
# characters have. With `fill` (the `∫` form) the area under the curve down to
# the x-axis is stippled with a dim `·` — a subtle area-under-the-curve
# highlight, with the curve line itself left as sharp braille on top.
#
# Sampling is exact and float-free: P is evaluated at the precise fractional x
# of every pixel column via scaled-integer arithmetic (P(n/d)·dᵈᵉᵍ is an exact
# integer), so the line is smooth instead of stair-stepped by integer-x
# quantization. Values are exact (auto-promoting to BigInt).

use canvas

+ Plot
  # P(n/d)·d^deg as an exact integer (deg = highest power present). The common
  # d^deg scale cancels in the y-mapping, so only ratios matter.
  -> .eval_scaled(coeffs, n, d, deg)
    result = 0
    k = 0
    while k < coeffs.size()
      term = coeffs[k]
      i = 0
      while i < k
        term = term * n
        i += 1
      i = 0
      while i < deg - k
        term = term * d
        i += 1
      result = result + term
      k += 1
    result

  # Format a value scaled by 10 (tenths) as a one-decimal signed string.
  -> .fmt_decimal(x10)
    v = x10
    neg = false
    if v < 0
      neg = true
      v = 0 - v
    s = (v / 10).to_s() + "." + (v % 10).to_s()
    if neg
      s = "-" + s
    s

  # Map v in [lo_v, hi_v] onto 0..steps, rounded, clamped in-band.
  -> .scale(v, lo_v, hi_v, steps)
    span = hi_v - lo_v
    if span == 0
      span = 1
    s = ((v - lo_v) * steps + span / 2) / span
    if s < 0
      return 0
    if s > steps
      return steps
    s

  -> .render(lo, hi, coeffs, cols, rows, fill = false, margin = 0, zeros = [])
    canvas = Canvas.new(cols, rows)
    curvec = Canvas.new(cols, rows)
    pw = canvas.pixel_width()
    ph = canvas.pixel_height()
    # Show `margin` extra units of x on each side of the range in question.
    plo = lo - margin
    phi = hi + margin
    span = phi - plo
    if span == 0
      span = 1
    deg = coeffs.size() - 1
    if deg < 0
      deg = 0
    d = pw - 1
    if d < 1
      d = 1

    # Sample P at the exact fractional x = n/d of each pixel column.
    ys = []
    ymin = 0
    ymax = 0
    px = 0
    while px < pw
      n = plo * d + span * px
      y = eval_scaled(coeffs, n, d, deg)
      ys.push(y)
      if px == 0
        ymin = y
        ymax = y
      else
        if y < ymin
          ymin = y
        if y > ymax
          ymax = y
      px += 1

    # Always include y=0 so the x-axis is on-screen, and guard a flat curve.
    if ymin > 0
      ymin = 0
    if ymax < 0
      ymax = 0
    if ymax == ymin
      ymax = ymin + 1

    # Pixel row of the x-axis (y=0 → scaled 0, same units as ys).
    zero_py = (ph - 1) - scale(0, ymin, ymax, ph - 1)

    # Curve (one dot per column) and, for ∫, the area fill (a 50% braille
    # dither) both go into `canvas`; `curvec` marks the curve cells. A cell
    # holds one colour, so to hug with no gap the curve's own cell is drawn
    # bright (the top edge) and the fill-only cells below it dim.
    prev_py = -1
    px = 0
    while px < pw
      py = (ph - 1) - scale(ys[px], ymin, ymax, ph - 1)
      # Connect consecutive samples with a vertical run, so a steep column
      # (where the curve spans several pixel rows) stays continuous instead of
      # tearing into isolated dots with skipped rows.
      if prev_py < 0
        canvas.set(px, py)
        curvec.set(px, py)
      else
        y0 = prev_py
        y1 = py
        if y0 > y1
          y0 = py
          y1 = prev_py
        yy = y0
        while yy <= y1
          canvas.set(px, yy)
          curvec.set(px, yy)
          yy += 1
      prev_py = py
      if fill
        # Shade the AUC only across the integration interval [lo, hi] — x = n/d
        # where n = plo·d + span·px, so lo·d ≤ n ≤ hi·d keeps it off the margins.
        nx = plo * d + span * px
        if nx >= lo * d && nx <= hi * d
          a0 = py
          a1 = zero_py
          if a0 > a1
            a0 = zero_py
            a1 = py
          yy = a0
          while yy <= a1
            if (px + yy) % 2 == 0
              canvas.set(px, yy)
            yy += 1
      px += 1

    axis_row = zero_py / 4
    # Ticks + labels at the integration bounds only (the range in question);
    # the ±margin extension carries no ticks or labels.
    ticks = [lo, hi]
    tick_cols = [scale(lo, plo, phi, pw - 1) / 2, scale(hi, plo, phi, pw - 1) / 2]

    # y-axis labels — real values, scaled back by d^deg.
    pd = 1
    pp = 0
    while pp < deg
      pd = pd * d
      pp += 1
    ymax_s = (ymax / pd).to_s()
    ymin_s = (ymin / pd).to_s()
    gut = ymax_s.size()
    if ymin_s.size() > gut
      gut = ymin_s.size()

    # `\[` escapes the string-interpolation bracket so the ANSI code is a
    # literal `ESC [ … m`, not a `[expr]` interpolation.
    esc = 27.chr()
    dim = esc + "\[2m"
    white = esc + "\[1m" + esc + "\[97m"
    reset = esc + "\[0m"
    indent = "  "

    # Blank line, then each row: 2-space indent + a left y-label gutter (which
    # sits off the plot) + the plot cells.
    out = "\n"
    row = 0
    while row < rows
      ylab = ""
      if row == 0
        ylab = ymax_s
      elsif row == rows - 1
        ylab = ymin_s
      elsif row == axis_row
        ylab = "0"
      out = out + indent + dim + (" " * (gut - ylab.size())) + ylab + reset + " "
      col = 0
      while col < cols
        if row == axis_row
          if tick_cols.include?(col)
            out = out + dim + "+" + reset
          else
            out = out + dim + "-" + reset
        elsif !curvec.cell_empty?(col, row)
          # Bright curve from the curve-only layer, so the cell shows just the
          # function's dot(s) — not the fill dither that also lands in it.
          out = out + white + curvec.cell_char(col, row) + reset
        elsif fill && !canvas.cell_empty?(col, row)
          out = out + dim + canvas.cell_char(col, row) + reset
        else
          out = out + " "
        col += 1
      out = out + "\n"
      row += 1

    # x-axis label row: each tick value centered under its `+`.
    labelrow = []
    lc = 0
    while lc < cols
      labelrow.push(" ")
      lc += 1
    ti = 0
    while ti < ticks.size()
      s = ticks[ti].to_s()
      start = tick_cols[ti] - s.size() / 2
      if start < 0
        start = 0
      if start + s.size() > cols
        start = cols - s.size()
      if start < 0
        start = 0
      k = 0
      while k < s.size()
        labelrow[start + k] = s.slice(k, 1)
        k += 1
      ti += 1
    out = out + indent + (" " * (gut + 1)) + dim + labelrow.join("") + reset + "\n"

    # A number line of the polynomial's zeroes within [lo, hi] — passed in as
    # x·10 from the precise root finder — with `↑` markers and 1-decimal labels.
    zcols = []
    zlabs = []
    zi = 0
    while zi < zeros.size()
      z = zeros[zi]
      if z >= lo * 10 && z <= hi * 10
        zcols.push(scale(z, plo * 10, phi * 10, pw - 1) / 2)
        zlabs.push(fmt_decimal(z))
      zi += 1
    if zcols.size() > 0
      mk = []
      lb = []
      mc = 0
      while mc < cols
        mk.push(" ")
        lb.push(" ")
        mc += 1
      zi = 0
      while zi < zcols.size()
        col = zcols[zi]
        if col >= 0 && col < cols
          mk[col] = "↑"
        s = zlabs[zi]
        st = col - s.size() / 2
        if st < 0
          st = 0
        if st + s.size() > cols
          st = cols - s.size()
        if st < 0
          st = 0
        k = 0
        while k < s.size()
          lb[st + k] = s.slice(k, 1)
          k += 1
        zi += 1
      pre = " " * (gut + 1)
      out = out + indent + pre + dim + mk.join("") + reset + "\n"
      out = out + indent + pre + dim + lb.join("") + reset + "\n"
    out
