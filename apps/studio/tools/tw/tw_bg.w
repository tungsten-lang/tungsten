# The animations' background, de-banded: anim/core.w's radial gradient (#131b2c at 0, #090d15 at 0.64, #04060a at 1;
# objectBoundingBox cx 50%, cy 46%, r 78% over the 1920 x 1080 frame, so an ellipse of radii 1497.6 x 842.4 px around
# (960, 496.8); stops interpolated in sRGB code values, as rsvg/cairo draw it) computed in floating point and dithered
# to 8 bits with static triangular noise of +-1 code (a fixed seed: the same plate in every frame, so it costs the encoder
# almost nothing after a segment's first frame). rsvg's own 8-bit gradient steps one code every ~60 px, which
# VideoToolbox turned into 16 x 16 blocks (Erik, 2026-10-26: "very jagged"); the dithered plate has no flat steps.
#   tw_bg <out.png> [width height cx cy r mid seed]     defaults: the film, 1920 1080 0.5 0.46 0.78 0.64 20261026
#   tw_bg short/bg_dither.png 1080 1920 0.5 0.4 0.8 0.6  the Short's s_bg (short/short.w)
# tools/tw_anims.py builds the film's plate into anim/bg_dither.png and copies it next to every frame it renders
# (librsvg only reads images from the SVG's own folder or below); anim/core.w's background() draws it as an <image>.

-> plate(dst, stride, w, h, cx, cy, rx, ry, mid, seed) (i64 i64 i64 i64 f64 f64 f64 f64 f64 i64) i64
  s = seed
  y = 0
  while y < h
    x = 0
    while x < w
      dx = ((x + ~0.5) - cx) / rx
      dy = ((y + ~0.5) - cy) / ry
      t = Math.sqrt(dx * dx + dy * dy)
      t = ~1.0 if t > ~1.0
      r = ~0.0
      g = ~0.0
      b = ~0.0
      if t <= mid
        u = t / mid
        r = ~19.0 + (~9.0 - ~19.0) * u
        g = ~27.0 + (~13.0 - ~27.0) * u
        b = ~44.0 + (~21.0 - ~44.0) * u
      else
        u = (t - mid) / (~1.0 - mid)
        r = ~9.0 + (~4.0 - ~9.0) * u
        g = ~13.0 + (~6.0 - ~13.0) * u
        b = ~21.0 + (~10.0 - ~21.0) * u
      # one triangular noise value for the three channels (luminance dither, no colour noise)
      # a 64-bit LCG inlined (a typed call would box results above 2^47 in this compiler)
      s = (s * 6364136223846793005 + 1442695040888963407) & 9223372036854775807
      u1 = ((s >> 11) & 1048575) + ~0.0
      s = (s * 6364136223846793005 + 1442695040888963407) & 9223372036854775807
      u2 = ((s >> 11) & 1048575) + ~0.0
      n = (u1 + u2) / ~1048576.0 - ~1.0
      ri = Math.floor(r + n + ~0.5)
      gi = Math.floor(g + n + ~0.5)
      bi = Math.floor(b + n + ~0.5)
      p = dst + y * stride + x * 4
      raw_store_u8(p, 0, ri ## i64)
      raw_store_u8(p, 1, gi ## i64)
      raw_store_u8(p, 2, bi ## i64)
      raw_store_u8(p, 3, 255)
      x += 1
    y += 1
  0

-> main(args)
  out = args[0]
  w = 1920
  h = 1080
  cx = ~0.5
  cy = ~0.46
  r = ~0.78
  mid = ~0.64
  seed = 20261026
  if args.size >= 7
    w = args[1].to_i
    h = args[2].to_i
    cx = args[3].to_f
    cy = args[4].to_f
    r = args[5].to_f
    mid = args[6].to_f
  seed = args[7].to_i if args.size > 7
  c = Canvas.new(w, h)
  c.clear("#000000")
  # objectBoundingBox units over the whole frame: centre (cx w, cy h), radii r w and r h
  wf = w + ~0.0
  hf = h + ~0.0
  plate(c.data_pointer, c.stride, w, h, cx * wf, cy * hf, r * wf, r * hf, mid, seed)
  c.write_png(out)
  c.close
  << out
  0

args = []
i_arg = 0
while i_arg < ARGV.size
  if ARGV[i_arg] != "--"
    args.push(ARGV[i_arg])
  i_arg += 1
main(args)
