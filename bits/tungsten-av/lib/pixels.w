in Av

+ Pixels
  REF_TEXT_CACHE = {}

  -> .still?(path, frame)
    return true if frame < 0
    return false if type(path) != "String"
    ext = File.extname(path).downcase
    [".png", ".jpg", ".jpeg", ".webp", ".heic", ".tif", ".tiff", ".bmp", ".gif"].include?(ext)

  -> .pack_rgba_ptr(ptr, stride, width, height, depth) (i64 i64 i64 i64 i64) u8[]
    bpp = depth == 16 ? 6 : 3
    out = u8[width * height * bpp]
    ccall("w_media_studio_op", "copy_rgb", [ptr, stride, width, 0, height, depth], out, 0)
    out

  -> .pack_rgba_bytes(rgba, width, height, depth) (u8[] i64 i64 i64) u8[]
    bpp = depth == 16 ? 6 : 3
    out = u8[width * height * bpp]
    ccall("w_media_studio_op", "copy_rgb", [0, width * 4, width, 0, height, depth], out, rgba)
    out

  -> .still_frame(path, width, height, fit = "stretch", depth = 8)
    img = Canvas.load_image(path)
    mode = fit == nil ? "stretch" : fit.to_s
    if img.width == width && img.height == height && mode == "stretch"
      return ccall("w_cg_image_rgb", img.handle, depth)
    src_canvas = Canvas.new(img.width, img.height, background: "#000000")
    scaler = nil
    begin
      src_canvas.image(img, 0, 0, img.width, img.height)
      scaler = Scaler.new(img.width, img.height, width, height, filter: :lanczos3, fit: mode, alpha: :opaque)
      scaled = scaler.scale(src_canvas)
      pack_rgba_bytes(scaled, width, height, depth)
    ensure
      scaler.free if scaler != nil
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
    ccall("w_media_banding_op", "text_metrics", [a, b], [width, height], [x0, y0, x1, y1])

  -> .encoded_text_frames(cues, plan)
    frames = cues.map ->(c) Util.min(plan["frames"] - 1, ((c["start"] + c["end"]) / 2 * plan["rate"][0] / plan["rate"][1]).to_i)
    Util.unique(frames)

  -> .encoded_text(path, reference, cues, settings, plan, media, pre_cand_by_frame = nil)
    unique = encoded_text_frames(cues, plan)
    fit = Util.get(plan["profile"], "fit", "stretch")
    ref_frames = unique.map ->(f) f + plan["start"]
    ref_sig = type(reference) == "String" ? [reference, Util.stamp(reference)] : [reference, reference.size > 0 ? Util.stamp(reference[0]) : nil]
    ref_key = JSON.encode([ref_sig, ref_frames, plan["width"], plan["height"], fit])
    ref_imgs = REF_TEXT_CACHE[ref_key]
    if ref_imgs == nil
      ref_imgs = Pixels.frames(media, reference, ref_frames, plan["width"], plan["height"], plan["rate"], fit, 8)
      REF_TEXT_CACHE.clear if REF_TEXT_CACHE.size >= 8
      REF_TEXT_CACHE[ref_key] = ref_imgs
    cand_imgs = pre_cand_by_frame != nil ? (unique.map ->(f) pre_cand_by_frame[f]) : Pixels.frames(media, path, unique, plan["width"], plan["height"], plan["rate"], "stretch", 8)
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
