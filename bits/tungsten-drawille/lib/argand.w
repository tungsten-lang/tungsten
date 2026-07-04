# Argand — render a complex expression on the Argand (complex) plane.
#
# Every vector arrow, the modulus |z|, the argument arg(z), and the
# multiply-as-rotation geometry are computed in compiled Tungsten
# `Complex<f64>` — this bit dogfoods the hypercomplex tower. The integer
# canvas geometry (Bresenham lines) draws the result.
#
# The plane is square: a Canvas with `cols = 2·rows` has a pixel grid that
# is exactly as wide as it is tall (pixel_width == pixel_height), so the
# real/imaginary axes share one scale and the geometry isn't stretched.
#
# Input arrives as integers pre-scaled by `scale` (so 0.8 is passed as 800
# with scale 1000); the bit reconstructs the float components and does all
# the arithmetic itself. `ops` are the operators between the complex
# operands ("+","-","*","/"); the internal a+bi of each operand is already
# folded into one (re, im) pair by the caller.
#
# Output is the rendered plane followed by machine-readable value records,
# one per drawn vector, each line `@@ <role> <re> <im> <abs> <arg>` (arg in
# radians). The wit REPL parses the `@@` lines to print |z|/arg annotations
# and strips them from the display.

use canvas

+ Argand
  # Round a float pixel coordinate to the nearest integer (sign-correct).
  -> .round_i(v)
    Math.floor(v + ~0.5).to_i

  # World point (x, y) → integer pixel (px, py), y pointing up. The origin
  # sits at the pixel-grid centre; a world distance of `s` reaches the edge.
  -> .px(x, y, cx, cy, s)
    fx = cx.to_f + (x / s) * cx.to_f
    fy = cy.to_f - (y / s) * cy.to_f
    [round_i(fx), round_i(fy)]

  # Draw a vector arrow from the origin pixel to the tip, capped with a tiny
  # 3-pixel point: the tip plus two flankers one step back and one to each side
  # (perpendicular = (-sin, cos)). Just enough to read as a head without a
  # bulky triangle.
  -> .arrow(cnv, cx, cy, tx, ty)
    cnv.line(cx, cy, tx, ty)
    dx = tx - cx
    dy = ty - cy
    if dx == 0 && dy == 0
      return cnv
    ang = Math.atan2(dy.to_f, dx.to_f)
    bl = ~2.0
    hw = ~1.2
    px = ~0.0 - Math.sin(ang)
    py = Math.cos(ang)
    f1x = tx.to_f - bl * Math.cos(ang) + px * hw
    f1y = ty.to_f - bl * Math.sin(ang) + py * hw
    f2x = tx.to_f - bl * Math.cos(ang) - px * hw
    f2y = ty.to_f - bl * Math.sin(ang) - py * hw
    cnv.set(tx, ty)
    cnv.set(round_i(f1x), round_i(f1y))
    cnv.set(round_i(f2x), round_i(f2y))
    cnv

  # Draw the arc swept from world-angle a0 to a1 at world-radius r — the
  # rotation a multiplication applies, drawn in the bright layer.
  -> .arc(cnv, cx, cy, s, r, a0, a1)
    steps = 28
    i = 0
    while i <= steps
      t = a0 + (a1 - a0) * i.to_f / steps.to_f
      wx = r * Math.cos(t)
      wy = r * Math.sin(t)
      p = px(wx, wy, cx, cy, s)
      cnv.set(p[0], p[1])
      i = i + 1
    cnv

  # Build a Complex<f64> from a scaled-integer (re, im) pair.
  -> .complex_of(re_i, im_i, s)
    Complex<f64>.new([re_i.to_f / s, im_i.to_f / s])

  # Fold the operand list with the operators into the result value.
  -> .evaluate(operands, ops)
    result = operands[0]
    i = 0
    while i < ops.size()
      op = ops[i]
      b = operands[i + 1]
      if op == "+"
        result = result + b
      elsif op == "-"
        result = result - b
      elsif op == "*"
        result = result * b
      elsif op == "/"
        result = result / b
      i = i + 1
    result

  # Format a float to six decimals as a signed string (no Decimal use). Six
  # places keeps the |z|/arg records precise enough that the REPL's
  # radians→degrees conversion lands on the true angle (e.g. arg 0.927295 →
  # 53.13°, not 53.11° from a 3-place truncation).
  -> .fmt(x)
    neg = x < ~0.0
    v = x
    if neg
      v = ~0.0 - x
    scaled = round_i(v * ~1000000.0)
    whole = scaled / 1000000
    frac = scaled % 1000000
    fs = frac.to_s()
    while fs.size() < 6
      fs = "0" + fs
    s = whole.to_s() + "." + fs
    if neg
      s = "-" + s
    s

  # A machine-readable value record for one vector (arg in radians).
  -> .record(role, z)
    "@@ " + role + " " + fmt(z.real) + " " + fmt(z.imag) + " " + fmt(z.abs) + " " + fmt(z.arg)

  -> .render(re_ints, im_ints, ops, scale, rows, rot_deg)
    s = scale.to_f

    # Build operands and evaluate the expression — all in Tungsten.
    operands = []
    i = 0
    while i < re_ints.size()
      operands.push(complex_of(re_ints[i], im_ints[i], s))
      i = i + 1
    result = evaluate(operands, ops)

    # Rotation knob (the REPL's scrubbable `arg`): multiply the result by the
    # unit complex e^(iθ) = (cos θ, sin θ) — multiply-as-rotation, in Tungsten.
    # |result| is preserved; its argument shifts by θ.
    if rot_deg != 0
      rad = rot_deg.to_f * ~3.141592653589793 / ~180.0
      result = result * Complex<f64>.new([Math.cos(rad), Math.sin(rad)])

    # Vectors to draw: a lone operand shows just itself; an expression shows
    # every operand plus the result (so a product shows both factors rotating
    # into the product).
    is_product = ops.size() == 1 && ops[0] == "*"
    drawn = []
    roles = []
    if operands.size() == 1
      drawn.push(result)
      roles.push("z")
    else
      i = 0
      while i < operands.size()
        drawn.push(operands[i])
        roles.push("operand")
        i = i + 1
      drawn.push(result)
      roles.push("result")

    # World→pixel scale: the longest vector reaches ~87% of the half-width.
    max_mag = ~0.0
    i = 0
    while i < drawn.size()
      m = drawn[i].abs
      if m > max_mag
        max_mag = m
      i = i + 1
    if max_mag < ~0.0001
      max_mag = ~1.0
    sworld = max_mag * ~1.15

    cols = 2 * rows
    cnv = Canvas.new(cols, rows)
    pw = cnv.pixel_width()
    ph = cnv.pixel_height()
    cx = pw / 2
    cy = ph / 2

    # Rotation arc for a single product: sweep from the first factor's angle
    # to the product's angle at a small radius near the origin.
    if is_product
      a0 = operands[0].arg
      a1 = result.arg
      arc(cnv, cx, cy, sworld, sworld * ~0.22, a0, a1)

    # The vectors with arrowheads.
    i = 0
    while i < drawn.size()
      p = px(drawn[i].real, drawn[i].imag, cx, cy, sworld)
      arrow(cnv, cx, cy, p[0], p[1])
      i = i + 1

    # Emit: dim centred axes (real row + imaginary column, `+` at the
    # origin) under the bright braille vectors/arc.
    esc = 27.chr()
    dim = esc + "\[2m"
    bright = esc + "\[1m" + esc + "\[96m"
    reset = esc + "\[0m"

    axis_row = (cy / 4)
    axis_col = (cx / 2)

    out = "\n"
    row = 0
    while row < rows
      out = out + "  "
      col = 0
      while col < cols
        filled = !cnv.cell_empty?(col, row)
        if row == axis_row && col == axis_col
          out = out + dim + "+" + reset
        elsif filled
          out = out + bright + cnv.cell_char(col, row) + reset
        elsif row == axis_row
          out = out + dim + "-" + reset
        elsif col == axis_col
          out = out + dim + "|" + reset
        else
          out = out + " "
        col = col + 1
      out = out + "\n"
      row = row + 1

    # Value records — the |z|/arg the REPL annotates with, computed here.
    i = 0
    while i < drawn.size()
      out = out + record(roles[i], drawn[i]) + "\n"
      i = i + 1
    out
