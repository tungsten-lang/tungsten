in Av

+ Pixels
  -> .frame(media, path, frame, width, height, rate, fit = "stretch", depth = 8)
    base = File.join(Env.get("TMPDIR") || "/tmp", "av-frame-" + Util.id() + ".raw")
    scale = "scale=[width]:[height]:flags=lanczos"
    scale = "scale=[width]:[height]:force_original_aspect_ratio=decrease:flags=lanczos,pad=[width]:[height]:(ow-iw)/2:(oh-ih)/2" if fit == "contain"
    scale = "scale=[width]:[height]:force_original_aspect_ratio=increase:flags=lanczos,crop=[width]:[height]" if fit == "cover"
    pixel_format = depth == 16 ? "rgb48le" : "rgb24"
    args = ["-v", "error", "-y"]
    if frame >= 0
      target = frame * rate[1] / rate[0].to_f
      seek = Util.max(~0.0, target - 2)
      args.push("-ss")
      args.push(seek.to_s)
      args.push("-copyts")
      args.push("-start_at_zero")
      threshold = target - ~0.25 * rate[1] / rate[0]
      scale = "select=gte(t\\," + threshold.to_s + ")," + scale
    ["-i", path, "-vf", scale, "-frames:v", "1", "-pix_fmt", pixel_format, "-f", "rawvideo", base].each ->(a)
      args.push(a)
    begin
      media.ffmpeg(args)
      expected = width * height * 3 * (depth == 16 ? 2 : 1)
      raise "decoded frame has wrong size" if File.stat(base).size != expected
      File.read_bytes(base)
    ensure
      Util.unlink(base)

  -> .luma(bytes, index, depth) (u8[] i64 i64) f64
    if depth == 16
      p = index * 6
      r = (bytes[p] + 256 * bytes[p + 1]) / ~257.0
      g = (bytes[p + 2] + 256 * bytes[p + 3]) / ~257.0
      b = (bytes[p + 4] + 256 * bytes[p + 5]) / ~257.0
      return ~16.0 + ~219.0 * (~0.2126 * r + ~0.7152 * g + ~0.0722 * b) / ~255.0
    p = index * 3
    ~16.0 + ~219.0 * (~0.2126 * bytes[p] + ~0.7152 * bytes[p + 1] + ~0.0722 * bytes[p + 2]) / ~255.0

  -> .text_metrics(a, b, width, height, rect) (u8[] u8[] i64 i64 Array)
    x0 = Math.round(rect[0] * width).to_i ## i64
    y0 = Math.round(rect[1] * height).to_i ## i64
    x1 = Math.round((rect[0] + rect[2]) * width).to_i ## i64
    y1 = Math.round((rect[1] + rect[3]) * height).to_i ## i64
    edges = 0 ## i64
    retained = 0 ## i64
    error = ~0.0
    count = 0 ## i64
    y = y0 + 1
    while y < y1 - 1
      x = x0 + 1
      while x < x1 - 1
        p = y * width + x
        ax = (luma(a, p + 1, 8) - luma(a, p - 1, 8)) / ~438.0
        ay = (luma(a, p + width, 8) - luma(a, p - width, 8)) / ~438.0
        bx = (luma(b, p + 1, 8) - luma(b, p - 1, 8)) / ~438.0
        by = (luma(b, p + width, 8) - luma(b, p - width, 8)) / ~438.0
        if Math.hypot(ax, ay) > ~0.08
          edges += 1
          retained += 1 if Math.hypot(bx, by) > ~0.04
        c = 0 ## i64
        while c < 3
          error += Math.abs(a[3 * p + c] - b[3 * p + c]) / ~255.0
          count += 1
          c += 1
        x += 1
      y += 1
    [edges > 0 ? retained / (edges + ~0.0) : ~0.0, count > 0 ? error / count : ~1.0, edges]

  -> .encoded_text(path, reference, cues, settings, plan, media)
    frames = cues.map ->(c) Util.min(plan["frames"] - 1, ((c["start"] + c["end"]) / 2 * plan["rate"][0] / plan["rate"][1]).to_i)
    checks = []
    Util.unique(frames).each ->(frame)
      a = Pixels.frame(media, reference, frame + plan["start"], plan["width"], plan["height"], plan["rate"], Util.get(plan["profile"], "fit", "stretch"))
      b = Pixels.frame(media, path, frame, plan["width"], plan["height"], plan["rate"])
      metrics = text_metrics(a, b, plan["width"], plan["height"], Util.get(settings, "box", [~0.05, ~0.7, ~0.9, ~0.25]))
      checks.push({"frame": frame, "edge_recall": metrics[0], "mean_error": metrics[1], "reference_edges": metrics[2], "ok": metrics[2] > 0 && metrics[0] >= Util.get(settings, "minimum_edge_recall", ~0.85) && metrics[1] <= Util.get(settings, "max_error", ~0.06)})
    {"ok": checks.size > 0 && Util.all(checks.map ->(c) c["ok"]), "frames": checks, "scope": "reference ROI edge retention and pixel error; no OCR claim"}
