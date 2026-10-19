# Canvas vs Svg + rsvg-convert: frames per second for one moderately busy
# 1920x1080 video frame (a radial-gradient field, a full-frame still, 40
# stroked/filled shapes and dashed curves, a translucent panel, six text runs
# with outline strokes and Unicode).
#
#   benchmarks/canvas/run.sh [frames]       # builds --release, then runs
#
# Lanes (the same picture, animated by the frame index):
#   canvas        native draw into the bitmap (what an encoder would read)
#   canvas+png    native draw + write_png (ImageIO, sRGB tagged)
#   svg+rsvg      build the Svg, write it, rsvg-convert to PNG (today's path)
#
# It also prints the mean absolute per-channel difference between the
# native frame and rsvg's PNG of the same frame, as a parity figure.

W = 1920
H = 1080

-> panel_points(k, t)
  pts = []
  j = 0
  while j < 8
    x = 1120 + j * 90
    y = 760 + 80 * Math.sin(~0.6 * j + ~0.08 * t + k)
    pts.push([x, y])
    j += 1
  pts

-> frame_canvas(c, t, still)
  c.clear("#0e1116")
  c.rect(0, 0, W, H, fill: Canvas.radial(0.62, 0.45, 0.75, [[0, "#1c2533"], [1, "#0b0e13"]], units: :bbox))
  c.image(still, 960, 60, 900, 506, fit: :slice)
  c.rect(940, 40, 940, 546, fill: "none", stroke: "#8b949e", width: 3, rx: 18)
  i = 0
  while i < 24
    x = 80 + (i % 8) * 105
    y = 380 + (i / 8) * 105
    a = ~0.5 + ~0.5 * Math.sin(~0.1 * t + i)
    c.rect(x, y, 84, 84, fill: "#161b22", fill_opacity: ~0.95 * a, stroke: "#4fd1ff", width: 2, stroke_opacity: a, rx: 12)
    c.circle(x + 42, y + 42, 14 + 6 * a, fill: "#ffd166", stroke: "#0e1116", width: 2)
    i += 1
  k = 0
  while k < 4
    c.polyline(panel_points(k, t), stroke: "#ff8a5b", width: 4, linejoin: "round", linecap: "round", stroke_opacity: ~0.9)
    c.path("M " + (120 + k * 200).to_s + " 1000 C " + (220 + k * 200).to_s + " " + (880 - 10 * k).to_s + ", " + (320 + k * 200).to_s + " 1060, " + (420 + k * 200).to_s + " 960", stroke: "#8b949e", width: 3, fill: "none", dash: "10 8")
    k += 1
  c.rect(1100, 640, 760, 380, fill: "#000000", opacity: ~0.35, rx: 24)
  c.text(80, 160, "Superstrings and Shortest Paths", size: 72, weight: "bold", family: "Helvetica Neue, Helvetica, Arial, sans-serif", fill: "#ffffff", stroke: "#0b0e13", width: 6, linejoin: "round")
  c.text(80, 240, "every permutation of n symbols, as one string", size: 40, family: "Helvetica Neue, Helvetica, Arial, sans-serif", fill: "#d6dde4")
  c.text(80, 320, "L(n) ≥ n! + (n−1)! + (n−2)! + n − 3", size: 44, family: "STIX Two Text", fill: "#ffc24b")
  c.text(1140, 700, "frame " + t.to_s, size: 36, family: "Menlo", fill: "#4fd1ff")
  c.text(1140, 760, "αβγ √2 ≈ 1.414  x² ＜ y²", size: 40, family: "STIX Two Text", fill: "#ffffff")
  c.text(1860, 1040, "openai/math 128", size: 30, family: "Helvetica Neue, Helvetica, Arial, sans-serif", fill: "#aab4bf", anchor: "end")
  c

-> svg_text(svg, x, y, s, size, family, fill, extra)
  svg.raw("<text x=\"" + x.to_s + "\" y=\"" + y.to_s + "\" font-size=\"" + size.to_s + "\" font-family=\"" + family + "\" fill=\"" + fill + "\"" + extra + ">" + Svg.esc(s) + "</text>")

-> frame_svg(t, still_href)
  svg = Svg.new(W, H)
  svg.rect(0, 0, W, H, {fill: "#0e1116"})
  svg.raw("<defs><radialGradient id=\"fieldg\" cx=\"0.62\" cy=\"0.45\" r=\"0.75\"><stop offset=\"0\" stop-color=\"#1c2533\"/><stop offset=\"1\" stop-color=\"#0b0e13\"/></radialGradient></defs>")
  svg.rect(0, 0, W, H, {fill: "url(#fieldg)"})
  svg.raw("<image x=\"960\" y=\"60\" width=\"900\" height=\"506\" href=\"" + still_href + "\" preserveAspectRatio=\"xMidYMid slice\"/>")
  svg.rect(940, 40, 940, 546, {fill: "none", stroke: "#8b949e", width: 3, rx: 18})
  i = 0
  while i < 24
    x = 80 + (i % 8) * 105
    y = 380 + (i / 8) * 105
    a = ~0.5 + ~0.5 * Math.sin(~0.1 * t + i)
    svg.rect(x, y, 84, 84, {fill: "#161b22", fill_opacity: ~0.95 * a, stroke: "#4fd1ff", width: 2, stroke_opacity: a, rx: 12})
    svg.circle(x + 42, y + 42, 14 + 6 * a, {fill: "#ffd166", stroke: "#0e1116", width: 2})
    i += 1
  k = 0
  while k < 4
    svg.polyline(panel_points(k, t), {stroke: "#ff8a5b", width: 4, linejoin: "round", linecap: "round", stroke_opacity: ~0.9})
    svg.path("M " + (120 + k * 200).to_s + " 1000 C " + (220 + k * 200).to_s + " " + (880 - 10 * k).to_s + ", " + (320 + k * 200).to_s + " 1060, " + (420 + k * 200).to_s + " 960", {stroke: "#8b949e", width: 3, fill: "none", dash: "10 8"})
    k += 1
  svg.rect(1100, 640, 760, 380, {fill: "#000000", opacity: ~0.35, rx: 24})
  helv = "Helvetica Neue, Helvetica, Arial, sans-serif"
  svg_text(svg, 80, 160, "Superstrings and Shortest Paths", 72, helv, "#ffffff", " font-weight=\"bold\" stroke=\"#0b0e13\" stroke-width=\"6\" stroke-linejoin=\"round\" paint-order=\"stroke\"")
  svg_text(svg, 80, 240, "every permutation of n symbols, as one string", 40, helv, "#d6dde4", "")
  svg_text(svg, 80, 320, "L(n) ≥ n! + (n−1)! + (n−2)! + n − 3", 44, "STIX Two Text", "#ffc24b", "")
  svg_text(svg, 1140, 700, "frame " + t.to_s, 36, "Menlo", "#4fd1ff", "")
  svg_text(svg, 1140, 760, "αβγ √2 ≈ 1.414  x² ＜ y²", 40, "STIX Two Text", "#ffffff", "")
  svg_text(svg, 1860, 1040, "openai/math 128", 30, helv, "#aab4bf", " text-anchor=\"end\"")
  svg

-> make_still(path)
  s = Canvas.new(1600, 900)
  s.rect(0, 0, 1600, 900, fill: Canvas.linear(0, 0, 1, 1, [[0, "#2b4162"], [0.5, "#b07d62"], [1, "#12100e"]], units: :bbox))
  i = 0
  while i < 60
    s.circle(80 + (i * 137) % 1500, 60 + (i * 89) % 800, 20 + (i * 7) % 60, fill: "#ffffff", fill_opacity: ~0.12, stroke: "#000000", width: 3, stroke_opacity: ~0.3)
    i += 1
  s.write_png(path)
  s.close

-> mean_abs_diff(a, b)
  n = a.size
  sum = 0 ## i64
  i = 0 ## i64
  while i < n
    d = a[i] - b[i]
    d = 0 - d if d < 0
    sum += d
    i += 1
  sum / (n + ~0.0)

args = argv()
frames = 60
frames = args[0].to_i if args.size > 0
dir = "/tmp/tungsten_canvas_bench"
system("mkdir -p " + dir)
still = dir + "/still.png"
make_still(still)

<< "Canvas vs Svg+rsvg, 1920x1080, [frames] frames per lane"

# warm: font resolution, image decode, rsvg's first launch
c = Canvas.new(W, H)
frame_canvas(c, 0, still)
frame_svg(0, "still.png").write_png(dir + "/warm.png", 1)

t0 = clock()
f = 0
while f < frames
  frame_canvas(c, f, still)
  f += 1
t1 = clock()
native = frames / (t1 - t0)
<< "canvas        [Motion.fixed(native, 1)] frames/s  ([Motion.fixed((t1 - t0) * ~1000.0 / frames, 2)] ms/frame)"

t0 = clock()
f = 0
while f < frames
  frame_canvas(c, f, still)
  c.write_png(dir + "/native_" + f.to_s + ".png")
  f += 1
t1 = clock()
native_png = frames / (t1 - t0)
<< "canvas+png    [Motion.fixed(native_png, 1)] frames/s  ([Motion.fixed((t1 - t0) * ~1000.0 / frames, 2)] ms/frame)"

t0 = clock()
f = 0
while f < frames
  frame_svg(f, "still.png").write_png(dir + "/rsvg_" + f.to_s + ".png", 1)
  f += 1
t1 = clock()
rsvg = frames / (t1 - t0)
<< "svg+rsvg      [Motion.fixed(rsvg, 1)] frames/s  ([Motion.fixed((t1 - t0) * ~1000.0 / frames, 2)] ms/frame)"

<< "speedup       [Motion.fixed(native / rsvg, 1)]x draw-only, [Motion.fixed(native_png / rsvg, 1)]x with PNG output"

last = frames - 1
frame_canvas(c, last, still)
ref = Canvas.load_image(dir + "/rsvg_" + last.to_s + ".png")
<< "parity        mean |native - rsvg| = [Motion.fixed(mean_abs_diff(c.bytes, ref.bytes), 2)] / 255 per channel (frame [last])"
c.write_png(dir + "/last_native.png")
system("cp " + dir + "/rsvg_" + last.to_s + ".png " + dir + "/last_rsvg.png")
c.close
system("rm -f " + dir + "/native_*.png " + dir + "/rsvg_*.png")
<< "frames        " + dir + "/last_native.png, " + dir + "/last_rsvg.png"
