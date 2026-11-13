in Av

+ Pixels
  -> .still?(path, frame)
    return true if frame < 0
    return false if type(path) != "String"
    ext = File.extname(path).downcase
    [".png", ".jpg", ".jpeg", ".webp", ".heic", ".tif", ".tiff", ".bmp", ".gif"].include?(ext)

  -> .pack_rgba_ptr(ptr, stride, width, height, depth) (i64 i64 i64 i64 i64) u8[]
    if depth == 16
      out16 = u8[width * height * 6]
      y = 0 ## i64
      while y < height
        row = y * stride
        dst_row = y * width * 6
        x = 0 ## i64
        while x < width
          s = row + x * 4
          d = dst_row + x * 6
          r = raw_load_u8(ptr, s) * 257
          g = raw_load_u8(ptr, s + 1) * 257
          b = raw_load_u8(ptr, s + 2) * 257
          out16[d] = r & 255
          out16[d + 1] = r >> 8
          out16[d + 2] = g & 255
          out16[d + 3] = g >> 8
          out16[d + 4] = b & 255
          out16[d + 5] = b >> 8
          x += 1
        y += 1
      return out16
    out8 = u8[width * height * 3]
    y = 0 ## i64
    while y < height
      row = y * stride
      dst_row = y * width * 3
      x = 0 ## i64
      while x < width
        s = row + x * 4
        d = dst_row + x * 3
        out8[d] = raw_load_u8(ptr, s)
        out8[d + 1] = raw_load_u8(ptr, s + 1)
        out8[d + 2] = raw_load_u8(ptr, s + 2)
        x += 1
      y += 1
    out8

  -> .pack_rgba_bytes(rgba, width, height, depth) (u8[] i64 i64 i64) u8[]
    n = width * height
    if depth == 16
      out16 = u8[n * 6]
      i = 0 ## i64
      while i < n
        s = i * 4
        d = i * 6
        r = rgba[s] * 257
        g = rgba[s + 1] * 257
        b = rgba[s + 2] * 257
        out16[d] = r & 255
        out16[d + 1] = r >> 8
        out16[d + 2] = g & 255
        out16[d + 3] = g >> 8
        out16[d + 4] = b & 255
        out16[d + 5] = b >> 8
        i += 1
      return out16
    out8 = u8[n * 3]
    i = 0 ## i64
    while i < n
      s = i * 4
      d = i * 3
      out8[d] = rgba[s]
      out8[d + 1] = rgba[s + 1]
      out8[d + 2] = rgba[s + 2]
      i += 1
    out8

  -> .still_frame(path, width, height, fit = "stretch", depth = 8)
    img = Canvas.load_image(path)
    src_canvas = Canvas.new(img.width, img.height, background: "#000000")
    scaler = nil
    begin
      src_canvas.image(img, 0, 0, img.width, img.height)
      mode = fit == nil ? "stretch" : fit.to_s
      if img.width == width && img.height == height && mode == "stretch"
        return pack_rgba_ptr(src_canvas.data_pointer, src_canvas.stride, width, height, depth)
      scaler = Scaler.new(img.width, img.height, width, height, filter: :lanczos3, fit: mode, alpha: :opaque)
      scaled = scaler.scale(src_canvas)
      pack_rgba_bytes(scaled, width, height, depth)
    ensure
      scaler.close if scaler != nil
      src_canvas.close

  -> .frames(media, path, frame_list, width, height, rate, fit = "stretch", depth = 8)
    return [] if frame_list.size == 0
    if type(path) == "String" && still?(path, frame_list[0])
      single = still_frame(path, width, height, fit, depth)
      return frame_list.map ->(_f) single
    unique = Util.unique(frame_list)
    extracted = media.extract_frames(path, unique, width: width, height: height, fit: fit, depth: depth, rate: rate)
    by_frame = {}
    i = 0
    while i < unique.size
      by_frame[unique[i]] = extracted[i]
      i += 1
    frame_list.map ->(f) by_frame[f]

  -> .frame(media, path, frame, width, height, rate, fit = "stretch", depth = 8)
    return still_frame(path, width, height, fit, depth) if still?(path, frame)
    frames(media, path, [frame], width, height, rate, fit, depth)[0]

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
    x0 = 0 if x0 < 0
    y0 = 0 if y0 < 0
    x1 = width if x1 > width
    y1 = height if y1 > height
    rw = x1 - x0
    rh = y1 - y0
    return [~0.0, ~1.0, 0] if rw <= 2 || rh <= 2
    la = f64[rw * rh]
    lb = f64[rw * rh]
    ry = 0 ## i64
    while ry < rh
      y = y0 + ry
      rx = 0 ## i64
      while rx < rw
        p = (y * width + x0 + rx) * 3
        la[ry * rw + rx] = ~16.0 + ~219.0 * (~0.2126 * a[p] + ~0.7152 * a[p + 1] + ~0.0722 * a[p + 2]) / ~255.0
        lb[ry * rw + rx] = ~16.0 + ~219.0 * (~0.2126 * b[p] + ~0.7152 * b[p + 1] + ~0.0722 * b[p + 2]) / ~255.0
        rx += 1
      ry += 1
    edges = 0 ## i64
    retained = 0 ## i64
    err_sum = 0 ## i64
    count = 0 ## i64
    inv438 = ~1.0 / ~438.0
    ry = 1 ## i64
    while ry < rh - 1
      y = y0 + ry
      rx = 1 ## i64
      while rx < rw - 1
        idx = ry * rw + rx
        ax = (la[idx + 1] - la[idx - 1]) * inv438
        ay = (la[idx + rw] - la[idx - rw]) * inv438
        bx = (lb[idx + 1] - lb[idx - 1]) * inv438
        by = (lb[idx + rw] - lb[idx - rw]) * inv438
        if ax * ax + ay * ay > ~0.0064
          edges += 1
          retained += 1 if bx * bx + by * by > ~0.0016
        p3 = (y * width + x0 + rx) * 3
        d0 = a[p3] - b[p3]
        d0 = 0 - d0 if d0 < 0
        d1 = a[p3 + 1] - b[p3 + 1]
        d1 = 0 - d1 if d1 < 0
        d2 = a[p3 + 2] - b[p3 + 2]
        d2 = 0 - d2 if d2 < 0
        err_sum += d0 + d1 + d2
        count += 3
        rx += 1
      ry += 1
    [edges > 0 ? retained / (edges + ~0.0) : ~0.0, count > 0 ? (err_sum / ~255.0) / count : ~1.0, edges]

  -> .encoded_text(path, reference, cues, settings, plan, media)
    frames = cues.map ->(c) Util.min(plan["frames"] - 1, ((c["start"] + c["end"]) / 2 * plan["rate"][0] / plan["rate"][1]).to_i)
    unique = Util.unique(frames)
    fit = Util.get(plan["profile"], "fit", "stretch")
    ref_frames = unique.map ->(f) f + plan["start"]
    ref_imgs = Pixels.frames(media, reference, ref_frames, plan["width"], plan["height"], plan["rate"], fit, 8)
    cand_imgs = Pixels.frames(media, path, unique, plan["width"], plan["height"], plan["rate"], "stretch", 8)
    box = Util.get(settings, "box", [~0.05, ~0.7, ~0.9, ~0.25])
    min_recall = Util.get(settings, "minimum_edge_recall", ~0.85)
    max_err = Util.get(settings, "max_error", ~0.06)
    checks = []
    i = 0
    while i < unique.size
      frame = unique[i]
      metrics = text_metrics(ref_imgs[i], cand_imgs[i], plan["width"], plan["height"], box)
      checks.push({"frame": frame, "edge_recall": metrics[0], "mean_error": metrics[1], "reference_edges": metrics[2], "ok": metrics[2] > 0 && metrics[0] >= min_recall && metrics[1] <= max_err})
      i += 1
    {"ok": checks.size > 0 && Util.all(checks.map ->(c) c["ok"]), "frames": checks, "scope": "reference ROI edge retention and pixel error; no OCR claim"}
