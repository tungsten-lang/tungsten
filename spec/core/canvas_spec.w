# spec: compiled -- Canvas draws through runtime/quartz.c (CoreGraphics/CoreText), linked only into compiled programs
# spec: interpreter-rejects -- Canvas is compiled-only
# Canvas — native drawing into an RGBA bitmap (core/canvas.w, runtime/quartz.c).
#
# Checks real pixels: exact fill colours, anti-aliased edges, gradient
# endpoints, stroke width, dashes, clipping, transforms, blend modes, image
# decode and draw, text ink against its measured box, Unicode fallback, PNG
# round trip with the colour space embedded, and no native leak over 2,000
# create/draw/close cycles. On a non-Apple build the bridge is a stub, and the
# spec checks the clear "needs macOS" error instead.
#
# Run:
#   bin/tungsten spec/core/canvas_spec.w

passed = Atomic.new(0)

-> check(name, condition)
  raise "FAIL " + name if !condition
  passed.increment()
  << "PASS " + name

-> near(a, b, tol)
  d = a - b
  d = ~0.0 - d if d < 0
  d <= tol

-> alpha_at(bytes, w, x, y)
  bytes[(y * w + x) * 4 + 3]

# Bounding box [x0, y0, x1, y1] (device pixels, inclusive) of pixels with
# alpha > 0, or nil.
-> ink_box(c)
  w = c.pixel_width
  h = c.pixel_height
  b = c.bytes
  x0 = w
  y0 = h
  x1 = -1
  y1 = -1
  y = 0
  while y < h
    x = 0
    while x < w
      if alpha_at(b, w, x, y) > 0
        x0 = x if x < x0
        x1 = x if x > x1
        y0 = y if y < y0
        y1 = y if y > y1
      x += 1
    y += 1
  return nil if x1 < 0
  [x0, y0, x1, y1]

-> find_bytes(bytes, pat)
  n = bytes.size
  m = pat.size
  i = 0
  while i + m <= n
    j = 0
    while j < m && bytes[i + j] == pat[j]
      j += 1
    return true if j == m
    i += 1
  false

if !Canvas.available?
  msg = nil
  begin
    Canvas.new(10, 10)
  rescue e
    msg = e.to_s
  check("stub raises a clear error", msg != nil && msg.index("needs macOS") != nil)
  << "ALL PASS canvas_spec ([passed.load()] checks, stub build)"
  exit(0)

TMP = "/tmp/tungsten_canvas_spec_" + OS.capture("echo $PPID").strip()

# ---- construction, info, solid fills ----
c = Canvas.new(64, 64)
check("pixel size", c.pixel_width == 64 && c.pixel_height == 64)
check("default space and depth", c.space == "srgb" && c.depth == "8")
check("starts transparent", c.pixel(5, 5) == [0, 0, 0, 0])
c.rect(8, 8, 16, 16, fill: "#ff8a5b")
check("filled rect exact colour", c.pixel(12, 12) == [255, 138, 91, 255])
check("outside the rect stays clear", c.pixel(30, 30)[3] == 0)
c.rect(30, 8, 8, 8, fill: #1C2533)
check("Color literal fill", c.pixel(33, 11) == [28, 37, 51, 255])
c.rect(40, 8, 8, 8, fill: 0x00FF00)
check("0xRRGGBB fill", c.pixel(43, 11) == [0, 255, 0, 255])
c.rect(50, 8, 8, 8, fill: [~0.0, ~0.0, ~1.0])
check("[r, g, b] fill", c.pixel(53, 11) == [0, 0, 255, 255])
c.rect(8, 30, 8, 8, fill: "steelblue")
check("named colour", c.pixel(11, 33) == [70, 130, 180, 255])
c.rect(20, 30, 8, 8, fill: "rgba(255, 0, 0, 0.5)")
p = c.pixel(23, 33)
check("rgba() alpha", p[0] == 255 && near(p[3], 128, 1))
c.rect(32, 30, 8, 8, fill: "#00f", fill_opacity: 0.25)
check("fill_opacity", near(c.pixel(35, 33)[3], 64, 1))
check("pixel outside canvas is nil", c.pixel(64, 0) == nil)
c.clear("#123456")
check("clear fills every pixel", c.pixel(0, 0) == [18, 52, 86, 255] && c.pixel(63, 63) == [18, 52, 86, 255])
c.clear
check("clear() makes it transparent", c.pixel(10, 10) == [0, 0, 0, 0])

# ---- anti-aliasing ----
c.rect(10.5, 10, 10, 10, fill: "#fff")
a = c.pixel(10, 15)[3]
check("anti-aliased edge has intermediate alpha", a > 100 && a < 155)
check("interior of the AA rect is opaque", c.pixel(15, 15)[3] == 255)
c.clear
c.circle(32, 32, 20, fill: "#fff")
edge = 0
x = 0
while x < 64
  al = c.pixel(x, 32 - 14)[3]
  edge += 1 if al > 0 && al < 255
  x += 1
check("circle edge pixels are partially covered", edge >= 2)

# ---- gradients ----
g = Canvas.new(256, 16)
g.rect(0, 0, 256, 16, fill: Canvas.linear(0, 0, 256, 0, [[0, "#000000"], [1, "#ffffff"]]))
check("linear gradient start", g.pixel(0, 8)[0] <= 2)
check("linear gradient end", g.pixel(255, 8)[0] >= 253)
check("linear gradient middle", near(g.pixel(128, 8)[0], 128, 3))
g.clear
g.rect(0, 0, 256, 16, fill: Canvas.linear(0, 0, 1, 0, [[0, "#ff0000"], [1, "#0000ff"]], units: :bbox))
check("bbox gradient spans the shape", g.pixel(1, 8)[0] > 250 && g.pixel(254, 8)[2] > 250)
g.clear
g.rect(0, 0, 256, 16, fill: Canvas.linear(0, 0, 256, 0, [[0, "#000", 0], [1, "#000", 1]]))
check("stop opacity", g.pixel(2, 8)[3] < 6 && g.pixel(253, 8)[3] > 249)
g.close
r = Canvas.new(64, 64)
r.rect(0, 0, 64, 64, fill: Canvas.radial(32, 32, 30, [[0, "#ffffff"], [1, "#000000"]]))
check("radial gradient centre", r.pixel(32, 32)[0] >= 250)
check("radial gradient pads past the radius", r.pixel(1, 1)[0] <= 2 && r.pixel(1, 1)[3] == 255)
r.close

# ---- strokes ----
s = Canvas.new(64, 64)
s.line(8, 32, 56, 32, stroke: "#fff", width: 10)
check("stroke covers its width", s.pixel(30, 27)[3] == 255 && s.pixel(30, 36)[3] == 255)
check("stroke stops at its width", s.pixel(30, 26)[3] == 0 && s.pixel(30, 37)[3] == 0)
check("butt caps end at the endpoints", s.pixel(7, 32)[3] == 0 && s.pixel(8, 32)[3] == 255)
s.clear
s.line(8, 32, 56, 32, stroke: "#fff", width: 10, linecap: "round")
check("round caps extend past the endpoints", s.pixel(5, 32)[3] == 255)
s.clear
check("a line without a stroke paints nothing", s.line(0, 0, 60, 60).pixel(30, 30)[3] == 0)
s.line(0, 10, 64, 10, stroke: "#fff", width: 2, dash: "8 8")
check("dash on", s.pixel(4, 10)[3] == 255)
check("dash off", s.pixel(12, 10)[3] == 0)
check("dash on again", s.pixel(20, 10)[3] == 255)
s.clear
s.rect(16, 16, 32, 32, fill: "#f00", stroke: "#00f", width: 4)
check("fill then stroke: stroke on top at the edge", s.pixel(16, 32) == [0, 0, 255, 255])
check("fill inside", s.pixel(32, 32) == [255, 0, 0, 255])
s.clear
s.rect(16, 16, 32, 32, fill: "#f00", stroke: "#00f", width: 4, opacity: 0.5)
check("group opacity does not double up where stroke covers fill", near(s.pixel(17, 32)[3], 128, 2) && s.pixel(17, 32)[0] < 3)
s.close

# ---- paths ----
q = Canvas.new(64, 64)
q.path("M10 10 h20 v20 h-20 z", fill: "#fff")
check("svg path relative commands", q.pixel(20, 20)[3] == 255 && q.pixel(35, 20)[3] == 0)
q.begin_path.add_path("M 10 40 A 20 20 0 0 1 50 40")
b = q.path_bounds
check("svg arc sweeps through the top", near(b[1], 20, 0.5) && near(b[0], 10, 0.01) && near(b[2], 40, 0.01))
q.begin_path.add_path("M 10 40 a 20 20 0 0 0 40 0")
b = q.path_bounds
check("svg arc with sweep 0 goes the other way", near(b[1] + b[3], 60, 0.5))
q.clear
q.begin_path.add_rect(4, 4, 56, 56).add_rect(20, 20, 24, 24)
q.paint(fill: "#fff", rule: :evenodd)
check("even-odd leaves a hole", q.pixel(32, 32)[3] == 0 && q.pixel(8, 8)[3] == 255)
q.clear
q.paint(fill: "#fff")
check("non-zero fills the hole", q.pixel(32, 32)[3] == 255)
check("contains?", q.contains?(32, 32) && !q.contains?(32, 32, :evenodd))
q.clear
q.begin_path.move_to(10, 10).line_to(50, 10).quad_to(60, 30, 50, 50).curve_to(40, 60, 20, 60, 10, 50).close_path
q.fill("#0f0")
check("move/line/quad/curve fill", q.pixel(30, 30) == [0, 255, 0, 255])
q.clear
q.begin_path.arc(32, 32, 16, 0, π, false)
q.fill("#fff")
check("arc clockwise on screen fills the lower half", q.pixel(32, 40)[3] == 255 && q.pixel(32, 24)[3] == 0)
q.clear
q.polygon([[0, 0], [60, 0], [0, 60]], fill: "#fff")
check("polygon", q.pixel(10, 10)[3] == 255 && q.pixel(50, 50)[3] == 0)
q.clear
q.polyline([0, 32, 63, 32], stroke: "#fff", width: 2)
check("polyline from a flat list, unfilled", q.pixel(32, 32)[3] == 255 && q.pixel(32, 40)[3] == 0)
msg = nil
begin
  q.path("M 10 10 Q 5")
rescue e
  msg = e.to_s
check("bad path data raises", msg != nil && msg.index("expects 4 numbers") != nil)
q.close

# ---- clip, transform, state ----
t = Canvas.new(64, 64)
t.save
t.clip_rect(0, 0, 32, 64)
t.rect(0, 0, 64, 64, fill: "#fff")
t.restore
check("clip keeps the inside", t.pixel(16, 16)[3] == 255)
check("clip removes the outside", t.pixel(48, 16)[3] == 0)
t.rect(40, 40, 8, 8, fill: "#fff")
check("restore removes the clip", t.pixel(44, 44)[3] == 255)
t.clear
t.save
t.translate(20, 10)
t.rect(0, 0, 4, 4, fill: "#fff")
check("translate", t.pixel(21, 11)[3] == 255 && t.pixel(1, 1)[3] == 0)
t.rotate(π / 2)
t.rect(10, 0, 4, 4, fill: "#f00")
check("rotate quarter turn clockwise", t.pixel(17, 21) == [255, 0, 0, 255])
check("ctm reflects the transform", near(t.ctm[4], 20, 0.001) && near(t.ctm[1], 1, 0.001))
t.restore
check("restore resets the transform", near(t.ctm[4], 0, 0.001))
t.clear
t.transform(2, 0, 0, 2, 10, 10)
t.rect(0, 0, 2, 2, fill: "#fff")
check("matrix transform", t.pixel(13, 13)[3] == 255 && t.pixel(15, 15)[3] == 0)
t.reset
check("reset clears the transform", near(t.ctm[0], 1, 0.001) && near(t.ctm[4], 0, 0.001))
t.clear("#fff")
t.alpha = 0.5
t.rect(0, 0, 8, 8, fill: "#000")
check("global alpha", near(t.pixel(4, 4)[0], 128, 1))
t.alpha = 1
t.clear("#ffffff")
t.rect(0, 0, 32, 32, fill: "#ff0000")
t.rect(0, 0, 32, 32, fill: "#00ff00", blend: :multiply)
check("multiply blend", t.pixel(4, 4) == [0, 0, 0, 255])
t.rect(32, 0, 32, 32, fill: "#ff0000")
t.rect(32, 0, 32, 32, fill: "#00ff00", blend: "screen")
check("screen blend", t.pixel(40, 4) == [255, 255, 0, 255])
check("per-shape blend is restored", t.rect(0, 40, 8, 8, fill: "#00f").pixel(4, 44) == [0, 0, 255, 255])
t.close
hi = Canvas.new(16, 16, scale: 2)
check("scale doubles the pixels", hi.pixel_width == 32 && hi.pixel_height == 32)
hi.rect(1, 1, 2, 2, fill: "#fff")
check("user units map to device pixels", hi.pixel(2, 2)[3] == 255 && hi.pixel(5, 5)[3] == 255 && hi.pixel(6, 6)[3] == 0)
hi.close

# ---- depths and colour spaces ----
d16 = Canvas.new(8, 8, depth: 16)
d16.rect(0, 0, 8, 8, fill: "#ff8000")
p = d16.pixel(2, 2)
check("16-bit canvas", d16.depth == "16" && p[0] == 65535 && near(p[1], 32896, 2) && p[3] == 65535)
d16.close
df = Canvas.new(8, 8, depth: "float", space: "extended_linear_srgb")
df.rect(0, 0, 8, 8, fill: [~2.0, ~0.5, ~0.0])
p = df.pixel(2, 2)
check("float canvas keeps extended values", df.depth == "float" && near(p[0], 2, 0.001) && near(p[1], 0.5, 0.001))
df.close
dh = Canvas.new(8, 8, depth: "half", space: "linear_srgb")
dh.rect(0, 0, 8, 8, fill: [~0.25, ~0.5, ~0.75])
p = dh.pixel(2, 2)
check("half-float canvas", dh.depth == "half" && near(p[0], 0.25, 0.001) && near(p[2], 0.75, 0.001))
dh.close
p3 = Canvas.new(8, 8, space: "display_p3")
p3.rect(0, 0, 8, 8, fill: "#ff0000")
check("unmanaged colours are code values in the canvas space", p3.pixel(1, 1) == [255, 0, 0, 255])
p3.close
p3m = Canvas.new(8, 8, space: "display_p3", manage: true)
p3m.rect(0, 0, 8, 8, fill: "#ff0000")
p = p3m.pixel(1, 1)
check("managed sRGB red lands inside P3", p[0] < 250 && p[0] > 220 && p[1] > 30)
p3m.close
msg = nil
begin
  Canvas.new(8, 8, space: "cmyk")
rescue e
  msg = e.to_s
check("unknown space raises with the list", msg != nil && msg.index("display_p3") != nil)
msg = nil
begin
  Canvas.new(8, 8).rect(0, 0, 1, 1, fill: "#12")
rescue e
  msg = e.to_s
check("bad colour raises", msg != nil && msg.index("bad fill colour") != nil)

# ---- images ----
src = Canvas.new(40, 20)
src.rect(0, 0, 20, 20, fill: "#ff0000")
src.rect(20, 0, 20, 20, fill: "#0000ff")
src.write_png(TMP + "_src.png")
img = Canvas.load_image(TMP + "_src.png")
check("load_image size", img.width == 40 && img.height == 20)
check("load_image caches by path", Canvas.load_image(TMP + "_src.png").handle == img.handle)
dst = Canvas.new(80, 40)
dst.image(img, 0, 0, 80, 40, fit: :fill, quality: :none)
check("image drawn stretched: left red", dst.pixel(10, 20) == [255, 0, 0, 255])
check("image drawn stretched: right blue", dst.pixel(70, 20) == [0, 0, 255, 255])
check("image is upright (not flipped)", dst.pixel(70, 2) == [0, 0, 255, 255])
dst.clear
dst.image(img, 0, 0, 40, 40)
check("meet letterboxes", dst.pixel(20, 5)[3] == 0 && dst.pixel(5, 20)[0] == 255 && dst.pixel(35, 20)[2] == 255)
dst.clear
dst.image(img, 0, 0, 20, 20, fit: :slice, quality: :none)
check("slice crops to the box", dst.pixel(2, 10)[0] == 255 && dst.pixel(18, 10)[2] == 255 && dst.pixel(25, 10)[3] == 0)
dst.clear
dst.image(TMP + "_src.png", 0, 0, nil, nil, src: [20, 0, 20, 20])
check("source crop", dst.pixel(5, 5) == [0, 0, 255, 255] && dst.pixel(25, 5)[3] == 0)
dst.clear
dst.image(src, 10, 10)
check("draw another canvas", dst.pixel(15, 15) == [255, 0, 0, 255])
dst.clear
dst.image(img, 0, 0, 40, 20, fit: :fill, opacity: 0.5)
check("image opacity", near(dst.pixel(5, 5)[3], 128, 1))
check("image bytes", img.bytes.size == 40 * 20 * 4 && img.bytes[0] == 255 && img.bytes[3] == 255)
dst.close
src.close
before = Canvas.stats[:images]
img.release
check("release drops the cached image", Canvas.stats[:images] == before - 1)
msg = nil
begin
  Canvas.new(4, 4).image(img, 0, 0)
rescue e
  msg = e.to_s
check("a released image raises", msg != nil && msg.index("released") != nil)
msg = nil
begin
  Canvas.load_image(TMP + "_missing.png")
rescue e
  msg = e.to_s
check("missing file raises", msg != nil && msg.index("cannot read") != nil)

# ---- text ----
tx = Canvas.new(300, 100)
w2 = tx.text_width("ab", size: 40)
w3 = tx.text_width("abc", size: 40)
check("measured width grows with the string", w3 > w2 && w2 > 0)
check("spacing widens the advance", tx.text_width("abc", size: 40, spacing: 5) > w3 + 10)
check("bold is wider than regular", tx.text_width("Hamburg", size: 40, weight: "bold", family: "Helvetica Neue") > tx.text_width("Hamburg", size: 40, family: "Helvetica Neue"))
m = tx.measure_text("Hamburg", size: 40, family: "Helvetica Neue")
check("metrics: ascent/descent", m[:ascent] > 25 && m[:descent] > 5 && m[:top] < -20 && m[:bottom] > 5)
tx.text(20, 60, "Hamburg", size: 40, family: "Helvetica Neue", fill: "#fff")
box = ink_box(tx)
# the first fully covered pixel of the H stem, 10 units above the baseline
stem_x = box[0]
stem_x += 1 while tx.pixel(stem_x, 50) != [255, 255, 255, 255] && stem_x < box[0] + 10
check("text draws ink", box != nil)
check("ink inside the measured box", box[0] >= 20 + m[:left] - 1.5 && box[2] <= 20 + m[:right] + 1.5 && box[1] >= 60 + m[:top] - 1.5 && box[3] <= 60 + m[:bottom] + 1.5)
check("ink fills the measured box", box[0] <= 20 + m[:left] + 1.5 && box[2] >= 20 + m[:right] - 2.5)
tx.clear
tx.text(150, 60, "Hamburg", size: 40, family: "Helvetica Neue", fill: "#fff", anchor: "middle")
box2 = ink_box(tx)
check("anchor middle centres the advance", near((box2[0] + box2[2]) / 2.0, 150 + (m[:left] + m[:right]) / 2.0 - m[:width] / 2.0, 2))
tx.clear
tx.text(20, 60, "Hamburg", size: 40, family: "Helvetica Neue", fill: "#fff", stroke: "#f00", width: 8, linejoin: "round")
box3 = ink_box(tx)
check("stroke widens the ink by half the width", box3[0] <= box[0] - 3 && box3[2] >= box[2] + 3)
check("fill is painted over the stroke (paint-order stroke)", stem_x < box[0] + 10 && tx.pixel(stem_x, 50) == [255, 255, 255, 255])
check("the stroke shows outside the glyph", tx.pixel(box[0] - 2, 50)[0] == 255 && tx.pixel(box[0] - 2, 50)[1] == 0)
tx.clear
check("resolves Helvetica Neue bold", Canvas.font_name("Helvetica Neue", "bold") == "HelveticaNeue-Bold")
check("resolves weight 500", Canvas.font_name("Helvetica Neue", 500) == "HelveticaNeue-Medium")
check("resolves italic", Canvas.font_name("Helvetica Neue", nil, "italic") == "HelveticaNeue-Italic")
check("falls through a family list", Canvas.font_name("No Such Font, Menlo") == "Menlo-Regular")
check("accepts a PostScript name", Canvas.font_name("Menlo-Bold") == "Menlo-Bold")
glyphs = ["α", "Ω", "√", "²", "＜", "＞", "—", "π", "≈", "∑"]
glyphs.each -> (ch)
  tx.clear
  tx.text(10, 70, ch, size: 60, family: "Helvetica Neue", fill: "#fff")
  check("unicode glyph renders: " + ch, ink_box(tx) != nil && tx.text_width(ch, size: 60, family: "Helvetica Neue") > 5)
tx.clear
tx.text_runs(10, 60, [["x", {style: "italic"}], ["2", {shift: "super", size: 24}], [" + 1", {dx: 4}]], size: 40, fill: "#fff")
check("text_runs draws", ink_box(tx) != nil)
tx.clear
tx.text(10, 60, "GRAD", size: 50, weight: "bold", fill: Canvas.linear(0, 0, 1, 0, [[0, "#ff0000"], [1, "#0000ff"]], units: :bbox))
box = ink_box(tx)
check("gradient text has ink", box != nil)
tx.close

# ---- output: PNG round trip, colour space tag, bytes, raster ----
o = Canvas.new(48, 32)
o.clear("#0b0e13")
o.circle(24, 16, 12, fill: "#ff8a5b", stroke: "#fff", width: 2)
o.text(4, 30, "Aα", size: 14, fill: "#4fd1ff")
o.write_png(TMP + "_rt.png")
back = Canvas.load_image(TMP + "_rt.png")
check("PNG round trip: size", back.width == 48 && back.height == 32)
check("PNG round trip: identical pixels", back.bytes == o.bytes)
check("PNG round trip: sRGB tag", back.space == "srgb")
pngb = File.read_bytes(TMP + "_rt.png")
check("sRGB PNG carries an sRGB or iCCP chunk", find_bytes(pngb, [115, 82, 71, 66]) || find_bytes(pngb, [105, 67, 67, 80]))
back.release
check("bytes length", o.bytes.size == 48 * 32 * 4)
ras = o.to_raster(0x000000)
check("to_raster", ras.width == 48 && ras.get(24, 16) == 0xFF8A5B && ras.get(0, 0) == 0x0B0E13)
enc = o.encode("png")
check("encode returns PNG bytes", enc.size > 100 && enc[1] == 80 && enc[2] == 78 && enc[3] == 71)
o.write(TMP + "_rt.jpg", quality: 0.9)
check("write jpeg", File.read_bytes(TMP + "_rt.jpg")[0] == 255)
check("data_pointer and stride", o.data_pointer > 0 && o.stride >= 48 * 4)
o.close
spaces = ["display_p3", "rec709", "linear_srgb", "rec2020"]
spaces.each -> (sp)
  pc = Canvas.new(16, 16, space: sp, depth: 16)
  pc.clear("#808080")
  pc.write_png(TMP + "_" + sp + ".png")
  pb = File.read_bytes(TMP + "_" + sp + ".png")
  check(sp + " PNG embeds an ICC profile", find_bytes(pb, [105, 67, 67, 80]))
  li = Canvas.load_image(TMP + "_" + sp + ".png")
  check(sp + " PNG decodes in its space", li.space == sp)
  li.release
  pc.close

# ---- lifetime ----
c.close
open_before = Canvas.stats[:canvases]
lc = Canvas.new(8, 8)
lc.close
lc.close
msg = nil
begin
  lc.rect(0, 0, 1, 1)
rescue e
  msg = e.to_s
check("a closed canvas raises", lc.closed? && msg != nil && msg.index("closed") != nil)
check("close frees the canvas", Canvas.stats[:canvases] == open_before)

leak_img = Canvas.load_image(TMP + "_src.png")
-> cycle(img)
  k = Canvas.new(320, 180)
  k.clear("#0b0e13")
  k.rect(10, 10, 100, 60, fill: Canvas.linear(0, 0, 1, 1, [[0, "#ff8a5b"], [1, "#4fd1ff"]], units: :bbox), rx: 8)
  k.path("M 20 150 C 80 100, 160 200, 300 120", stroke: "#fff", width: 3, fill: "none")
  k.image(img, 200, 20, 100, 50, fit: :slice)
  k.text(20, 120, "frame √2 ≈ 1.414", size: 18, fill: "#fff", stroke: "#000", width: 2)
  k.close
  0

i = 0
while i < 200
  cycle(leak_img)
  i += 1
rss0 = OS.capture("ps -o rss= -p $PPID").strip().to_i()
while i < 2000
  cycle(leak_img)
  i += 1
rss1 = OS.capture("ps -o rss= -p $PPID").strip().to_i()
grow_mb = (rss1 - rss0) / 1024.0
<< "  rss after 200 cycles [rss0 / 1024] MB, after 2000 [rss1 / 1024] MB"
check("2,000 create/draw/close cycles: every canvas freed", Canvas.stats[:canvases] == open_before)
check("2,000 create/draw/close cycles: RSS growth under 40 MB (each canvas is 225 KB)", grow_mb < 40)
leak_img.release

["_src.png", "_rt.png", "_rt.jpg", "_display_p3.png", "_rec709.png", "_linear_srgb.png", "_rec2020.png"].each -> (sfx)
  File.delete(TMP + sfx)

<< "ALL PASS canvas_spec ([passed.load()] checks)"
