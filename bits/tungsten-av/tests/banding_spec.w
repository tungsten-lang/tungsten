# spec: compiled -- native Canvas and the AV companion are platform APIs
use ../lib/av

-> check(name, condition)
  raise "FAIL [name]" if !condition
  << "PASS [name]"

-> encode_frames_mov(path, frames, width, height, codec = "prores422hq", quality = ~1.0)
  enc = VideoEncoder.new(width, height, codec: codec, rate: [24, 1], gop: 24, quality: quality, input: "rgba")
  frames.each ->(rgba)
    enc.encode(rgba)
  seg = enc.segment
  enc.close
  mux = Mux.new(path, rate: [24, 1], tc_start: "00:00:00:00", frames: frames.size, edit_lists: false)
  mux.append(seg)
  seg.release
  mux.close

-> paint_gradient_rgba(width, height, gradient, mode = 0, offset = 0) (i64 i64 Hash i64 i64) u8[]
  cx = gradient["cx"].to_f
  cy = gradient["cy"].to_f
  radius = gradient["r"].to_f
  mid = gradient["mid"].to_f
  colours = gradient["colors"]
  c0 = colours[0]
  c1 = colours[1]
  c2 = colours[2]
  out = u8[width * height * 4]
  y = 0
  while y < height
    x = 0
    while x < width
      sx = mode == 2 ? (x / 16) * 16 + 8 : x
      sy = mode == 2 ? (y / 16) * 16 + 8 : y
      t = Math.hypot((sx + ~0.5 - cx * width) / (radius * width), (sy + ~0.5 - cy * height) / (radius * height))
      t = ~1.0 if t > ~1.0
      u = t <= mid ? t / mid : (t - mid) / (~1.0 - mid)
      a = t <= mid ? c0 : c1
      b = t <= mid ? c1 : c2
      # Deterministic TPDF-like spatial dither on mode == 0 so 8-bit source has smooth luma
      h = ((x * 73856093) ^ (y * 19349663)) & 1023
      dither = mode == 0 ? (h / ~1024.0 - ~0.5) : ~0.0
      o = (y * width + x) * 4
      k = 0
      while k < 3
        val = a[k] + (b[k] - a[k]) * u + dither + offset
        vi = Math.round(val).to_i
        if mode == 1
          vi = (vi / 10) * 10
        vi = 0 if vi < 0
        vi = 255 if vi > 255
        out[o + k] = vi
        k += 1
      out[o + 3] = 255
      x += 1
    y += 1
  out

-> write_rgba_png(path, rgba, width, height)
  c = Canvas.new(width, height)
  ptr = c.data_pointer ## i64
  stride = c.stride ## i64
  y = 0
  while y < height
    x = 0
    while x < width
      s = (y * width + x) * 4
      d = y * stride + x * 4
      raw_store_u8(ptr, d, rgba[s])
      raw_store_u8(ptr, d + 1, rgba[s + 1])
      raw_store_u8(ptr, d + 2, rgba[s + 2])
      raw_store_u8(ptr, d + 3, 255)
      x += 1
    y += 1
  c.write_png(path)
  c.close

root = File.join(Env.get("TMPDIR") || "/tmp", "av-banding-" + Av:Util.id())
File.mkdir_p(root)
begin
  width = 192
  height = 128
  raw = u8[width * height * 3]
  i = 0
  while i < raw.size
    raw[i] = 100
    i += 1
  flat_gradient = {"cx": ~0.5, "cy": ~0.5, "r": 1, "mid": ~0.5, "colors": [[100, 100, 100], [100, 100, 100], [100, 100, 100]]}
  error = Av:Banding.residual(raw, width, height, 8, flat_gradient)
  mask = Av:Banding.mask(raw, raw, width, height, [])
  metrics = Av:Banding.metrics(error, mask, width, height)
  check("analytical residual", metrics["rms"] < ~1e-10 && metrics["p99"] < ~1e-10)
  check("usable background", metrics["bg_frac"] > ~0.2)
  delta = Av:Banding.temporal_delta(error, error, mask, mask, width * height)
  check("adjacent-frame residual", Av:Banding.metrics(delta[0], delta[1], width, height)["rms"] < ~1e-10)
  excluded = Av:Banding.mask(raw, raw, width, height, [[0, 0, width, height]])
  rejected = false
  begin
    Av:Banding.metrics(error, excluded, width, height)
  rescue problem
    rejected = true
  check("no pass without usable samples", rejected)

  File.mkdir_p(root + "/anim")
  File.write(root + "/anim/core.w", "<radialGradient cx=\"50%\" cy=\"40%\" r=\"80%\">\n<stop offset=\"0\" stop-color=\"#50648c\"/>\n<stop offset=\"55%\" stop-color=\"#28344c\"/>\n<stop offset=\"1\" stop-color=\"#0c121c\"/>\n</radialGradient>")
  authored = Av:Banding.gradient(root, false)
  check("authored gradient", authored["cx"] == ~0.5 && authored["mid"] == ~0.55 && authored["colors"][0] == [80, 100, 140])

  media = Av:Media.new(Av:Util.absolute("../../..", __DIR__), Av:Util.absolute("..", __DIR__), Av:Runner.new(120))
  clean_rgba = paint_gradient_rgba(width, height, authored, 0, 0)
  write_rgba_png(root + "/background.png", clean_rgba, width, height)

  # 1. Positive case: smooth dithered gradient encoded natively as 10-bit ProRes 422 HQ passes.
  clean_frames = []
  f = 0
  while f < 12
    clean_frames.push(clean_rgba)
    f += 1
  encode_frames_mov(root + "/clean.mov", clean_frames, width, height, "prores422hq", ~1.0)
  File.write(root + "/Bitfile", "av.project \"banding\", source: \"clean.mov\"\n")
  project = Av:Project.load(root)
  limits = {"rms_detrended": ~0.75, "p99": ~2.0, "blk16": ~2.0, "temporal_rms": ~0.5}
  spec = {"background": "background.png", "gradient": authored, "samples": [{"frame": 4, "source": "background.png", "next_source": "background.png"}], "limits": limits}
  plan = {"width": width, "height": height, "rate": [24, 1], "frames": 12, "start": 0, "profile": {"banding": spec}}
  File.mkdir_p(root + "/checks-clean")
  clean_res = Av:Banding.run(project, media, root + "/clean.mov", plan, root + "/checks-clean", nil)
  check("native encoded dithered gradient passes", clean_res["ok"] && clean_res["max_p99"] <= limits["p99"] && clean_res["max_blk16"] <= limits["blk16"] && clean_res["max_temporal_rms"] <= limits["temporal_rms"])
  check("native diagnostics", File.file?(root + "/checks-clean/banding/contact-sheet.jpg") && File.file?(root + "/checks-clean/banding.html"))

  # 2. Synthetic failure A: quantized staircase contours must fail p99 and rms_detrended.
  stair_rgba = paint_gradient_rgba(width, height, authored, 1, 0)
  stair_frames = []
  f = 0
  while f < 12
    stair_frames.push(stair_rgba)
    f += 1
  encode_frames_mov(root + "/stair.mov", stair_frames, width, height, "prores422hq", ~1.0)
  File.mkdir_p(root + "/checks-stair")
  stair_res = Av:Banding.run(project, media, root + "/stair.mov", plan, root + "/checks-stair", nil)
  check("detects staircase contour banding (p99 & rms_detrended)", !stair_res["ok"] && stair_res["max_p99"] > limits["p99"] && stair_res["max_rms_detrended"] > limits["rms_detrended"])

  # 3. Synthetic failure B: 16x16 macroblock quantization must fail blk16.
  block_rgba = paint_gradient_rgba(width, height, authored, 2, 0)
  block_frames = []
  f = 0
  while f < 12
    block_frames.push(block_rgba)
    f += 1
  encode_frames_mov(root + "/block.mov", block_frames, width, height, "prores422hq", ~1.0)
  File.mkdir_p(root + "/checks-block")
  block_res = Av:Banding.run(project, media, root + "/block.mov", plan, root + "/checks-block", nil)
  check("detects 16x16 macroblock steps (blk16)", !block_res["ok"] && block_res["max_blk16"] > limits["blk16"])

  # 4. Synthetic failure C: frame-to-frame luma shift must fail temporal_rms.
  shifted_rgba = paint_gradient_rgba(width, height, authored, 0, 3)
  flicker_frames = []
  f = 0
  while f < 12
    flicker_frames.push(f == 5 ? shifted_rgba : clean_rgba)
    f += 1
  encode_frames_mov(root + "/flicker.mov", flicker_frames, width, height, "prores422hq", ~1.0)
  File.mkdir_p(root + "/checks-flicker")
  flicker_res = Av:Banding.run(project, media, root + "/flicker.mov", plan, root + "/checks-flicker", nil)
  check("detects temporal luma pumping (temporal_rms)", !flicker_res["ok"] && flicker_res["max_temporal_rms"] > limits["temporal_rms"])
ensure
  Av:Util.remove_tree(root)
