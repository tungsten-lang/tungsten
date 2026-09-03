# Color — hue wheel, desaturation, darkening and 24-bit terminal escapes (core/color.w).
#
# `Color.hue_components` and `Color.bg` are pure source-level arithmetic and run on
# both engines. Everything that produces an actual Color value goes through
# `ccall("w_color_raw", ...)`, which the native interpreter does not implement, so
# those assertions sit behind a capability gate (see the BUG note below).
#
# Run:
#   bin/tungsten run --interpret spec/core/color_spec.w
#   bin/tungsten -o /tmp/color_spec spec/core/color_spec.w && /tmp/color_spec

use core/color

passed = Atomic.new(0)

-> check(name, condition)
  raise "FAIL " + name if !condition
  passed.increment()
  << "PASS " + name

# ---- hue wheel: 6 sextants of 60 degrees, full saturation ----
check("hue 0 is red", Color.hue_components(0) == [255, 0, 0])
check("hue 60 is yellow", Color.hue_components(60) == [255, 255, 0])
check("hue 120 is green", Color.hue_components(120) == [0, 255, 0])
check("hue 180 is cyan", Color.hue_components(180) == [0, 255, 255])
check("hue 240 is blue", Color.hue_components(240) == [0, 0, 255])
check("hue 300 is magenta", Color.hue_components(300) == [255, 0, 255])
check("hue wraps at 360", Color.hue_components(360) == Color.hue_components(0))
check("hue wraps at 720", Color.hue_components(720) == [255, 0, 0])
check("hue wraps negatives", Color.hue_components(-60) == Color.hue_components(300))
# f = (h % 60) * 255 / 60, integer division: 30 -> 127
check("hue 30 interpolates red to yellow", Color.hue_components(30) == [255, 127, 0])
check("hue 90 interpolates yellow to green", Color.hue_components(90) == [128, 255, 0])
check("hue 150 interpolates green to cyan", Color.hue_components(150) == [0, 255, 127])
check("hue 210 interpolates cyan to blue", Color.hue_components(210) == [0, 128, 255])
check("hue 270 interpolates blue to magenta", Color.hue_components(270) == [127, 0, 255])
check("hue 330 interpolates magenta to red", Color.hue_components(330) == [255, 0, 128])
check("every hue has three channels", Color.hue_components(17).size == 3)
check("hue components stay in range",
      Color.hue_components(200)[0] >= 0 && Color.hue_components(200)[1] <= 255)

# ---- bg: a 24-bit truecolor background escape wrapping a single space ----
check("bg is an escape-wrapped space", Color.bg(1, 2, 3) == "\e[48;2;1;2;3m \e[0m")
check("bg length", Color.bg(1, 2, 3).size == 18)
check("bg interpolates each channel", Color.bg(255, 0, 128) == "\e[48;2;255;0;128m \e[0m")

# ---- Color values (compiled engine only) ----
# BUG: `ccall("w_color_raw", ...)` is not in the native interpreter's ccall whitelist —
# Color.rgb/.from/.hue_rgb/.desat/.darken all raise "Unsupported ccall 'w_color_raw'
# in interpreter". The compiled engine implements them.
# Repro: printf 'use core/color\n<< Color.rgb(1, 2, 3)\n' > /tmp/c.w && bin/tungsten run --interpret /tmp/c.w
color_native = true
begin
  Color.rgb(1, 2, 3)
rescue e
  color_native = false

if color_native
  c = Color.rgb(1, 2, 3)
  check("rgb builds a Color", type(c) == "Color")
  check("rgb renders as hex", c.to_s == "#010203")
  check("from takes an array", Color.from([4, 5, 6]).to_s == "#040506")
  check("from equals rgb", Color.from([1, 2, 3]) == Color.rgb(1, 2, 3))
  check("white", Color.rgb(255, 255, 255).to_s == "#FFFFFF")
  check("black", Color.rgb(0, 0, 0).to_s == "#000000")
  check("hue_rgb wraps hue_components", Color.hue_rgb(0).to_s == "#FF0000")
  check("hue_rgb 120", Color.hue_rgb(120).to_s == "#00FF00")
  check("hue_rgb 240", Color.hue_rgb(240).to_s == "#0000FF")

  # desat blends toward mid-gray 128 by (100 - pct)%: pct 100 keeps the colour,
  # pct 0 collapses to gray, pct 50 lands halfway (integer division truncates).
  check("desat 100 is a no-op", Color.desat([255, 0, 0], 100).to_s == "#FF0000")
  check("desat 0 is mid gray", Color.desat([255, 0, 0], 0).to_s == "#808080")
  check("desat 50 is halfway", Color.desat([255, 0, 0], 50).to_s == "#C04040")
  check("desat leaves gray alone", Color.desat([128, 128, 128], 30).to_s == "#808080")

  # darken scales each channel by pct/100.
  check("darken 100 is a no-op", Color.darken([200, 100, 50], 100).to_s == "#C86432")
  check("darken 50 halves each channel", Color.darken([200, 100, 50], 50).to_s == "#643219")
  check("darken 0 is black", Color.darken([200, 100, 50], 0).to_s == "#000000")
  check("darken truncates", Color.darken([255, 255, 255], 33).to_s == "#545454")
else
  << "SKIP Color value surface (interpreter: w_color_raw ccall unsupported)"

<< "ALL PASS color_spec ([passed.load()] checks)"
