in Av

+ Banding
  -> .blur(input, width, height) (f64[] i64 i64) f64[]
    kernel = f64[13]
    sum = ~0.0
    k = -6 ## i64
    while k <= 6
      kernel[k + 6] = Math.exp(~-0.5 * (k / ~2.0) * (k / ~2.0))
      sum += kernel[k + 6]
      k += 1
    k = 0
    while k < 13
      kernel[k] /= sum
      k += 1
    temporary = f64[width * height]
    result = f64[width * height]
    y = 0 ## i64
    while y < height
      x = 0 ## i64
      while x < width
        v = ~0.0
        k = -6
        while k <= 6
          at = x + k
          at = 0 if at < 0
          at = width - 1 if at >= width
          v += input[y * width + at] * kernel[k + 6]
          k += 1
        temporary[y * width + x] = v
        x += 1
      y += 1
    y = 0
    while y < height
      x = 0
      while x < width
        v = ~0.0
        k = -6
        while k <= 6
          at = y + k
          at = 0 if at < 0
          at = height - 1 if at >= height
          v += temporary[at * width + x] * kernel[k + 6]
          k += 1
        result[y * width + x] = v
        x += 1
      y += 1
    result

  -> .residual(bytes, width, height, depth, gradient) (u8[] i64 i64 i64 Hash) f64[]
    cx = gradient["cx"].to_f
    cy = gradient["cy"].to_f
    radius = gradient["r"].to_f
    mid = gradient["mid"].to_f
    raise "gradient requires positive radius and mid in 0..1" if radius <= 0 || mid <= 0 || mid >= 1
    colours = Util.get(gradient, "colors", [[19, 27, 44], [9, 13, 21], [4, 6, 10]])
    lumas = f64[3]
    i = 0 ## i64
    while i < 3
      c = colours[i]
      lumas[i] = ~16.0 + ~219.0 * (~0.2126 * c[0] + ~0.7152 * c[1] + ~0.0722 * c[2]) / ~255.0
      i += 1
    raw = f64[width * height]
    y = 0 ## i64
    while y < height
      x = 0 ## i64
      while x < width
        t = Math.hypot((x + ~0.5 - cx * width) / (radius * width), (y + ~0.5 - cy * height) / (radius * height))
        t = ~1.0 if t > ~1.0
        ideal = t <= mid ? lumas[0] + (lumas[1] - lumas[0]) * t / mid : lumas[1] + (lumas[2] - lumas[1]) * (t - mid) / (~1.0 - mid)
        raw[y * width + x] = Pixels.luma(bytes, y * width + x, depth) - ideal
        x += 1
      y += 1
    blur(raw, width, height)

  -> .mask(source, background, width, height, excludes, margin = 8, border = 20) (u8[] u8[] i64 i64 Array i64 i64) u8[]
    blocked = i64[(width + 1) * (height + 1)]
    y = 0 ## i64
    while y < height
      row = 0 ## i64
      x = 0 ## i64
      while x < width
        p = (y * width + x) * 3
        different = source[p] != background[p] || source[p + 1] != background[p + 1] || source[p + 2] != background[p + 2]
        excludes.each ->(r)
          different = true if x >= r[0] && y >= r[1] && x < r[0] + r[2] && y < r[1] + r[3]
        row += 1 if different
        blocked[(y + 1) * (width + 1) + x + 1] = blocked[y * (width + 1) + x + 1] + row
        x += 1
      y += 1
    result = u8[width * height]
    y = border
    while y < height - border
      x = border
      while x < width - border
        x0 = x - margin
        x1 = x + margin + 1
        y0 = y - margin
        y1 = y + margin + 1
        x0 = 0 if x0 < 0
        y0 = 0 if y0 < 0
        x1 = width if x1 > width
        y1 = height if y1 > height
        count = blocked[y1 * (width + 1) + x1] - blocked[y0 * (width + 1) + x1] - blocked[y1 * (width + 1) + x0] + blocked[y0 * (width + 1) + x0]
        result[y * width + x] = 1 if count == 0
        x += 1
      y += 1
    result

  -> .metrics(error, mask, width, height, temporal = nil) (f64[] u8[] i64 i64 Object)
    total = ~0.0
    squared = ~0.0
    count = 0 ## i64
    boundaries = ~0.0
    interiors = ~0.0
    nb = 0 ## i64
    ni = 0 ## i64
    absolute = []
    p = 0 ## i64
    while p < width * height
      if mask[p] != 0
        e = error[p]
        total += e
        squared += e * e
        count += 1
        absolute.push(Math.abs(e))
        if p % width > 0 && mask[p - 1] != 0
          d = Math.abs(e - error[p - 1])
          if p % width % 16 == 0
            boundaries += d
            nb += 1
          else
            interiors += d
            ni += 1
        if p >= width && mask[p - width] != 0
          d = Math.abs(e - error[p - width])
          if (p / width) % 16 == 0
            boundaries += d
            nb += 1
          else
            interiors += d
            ni += 1
      p += 1
    raise "less than 1% usable background after masks" if count < width * height / 100
    raise "insufficient block boundaries after masks" if nb == 0 || ni == 0
    sorted = absolute.sort
    q = ~0.99 * (count - 1)
    lo = q.to_i
    hi = lo + 1 < count ? lo + 1 : lo
    p99 = sorted[lo] + (sorted[hi] - sorted[lo]) * (q - lo)
    mean = total / count
    {"bg_frac": count / (width * height + ~0.0), "rms": Math.sqrt(squared / count), "mean_err": mean, "rms_detrended": Math.sqrt(Util.max(~0.0, squared / count - mean * mean)), "p99": p99, "blk16": (boundaries / nb) / Util.max(interiors / ni, ~1e-9)}

  -> .gradient(root, short)
    path = root + (short ? "/short/short.w" : "/anim/core.w")
    text = File.read(path).replace("\\\"", "\"")
    tag = Regex.new("(?m)<radialGradient\\b(\[^>]*)>(.*?)</radialGradient>").match_data(text)
    raise "configure an analytical gradient for [path]" if tag == nil
    result = {}
    ["cx", "cy", "r"].each ->(key)
      m = Regex.new(key + "=\"(\[0-9.]+)%\"").match_data(tag[1])
      raise "invalid authored gradient" if m == nil
      result[key] = m[1].to_f / 100
    colours = []
    stops = tag[2].split("<stop")
    stops.each ->(stop)
      m = Regex.new("offset=\"(\[0-9.]+%?)\"\[^>]*stop-color=\"(#\[0-9a-fA-F]{6})\"").match_data(stop)
      if m != nil
        result["mid"] = m[1].to_f / (m[1].ends_with?("%") ? 100 : 1) if colours.size == 1
        digits = "0123456789abcdef"
        colour = []
        [1, 3, 5].each ->(i)
          colour.push(16 * digits.index(m[2].slice(i, 1).downcase) + digits.index(m[2].slice(i + 1, 1).downcase))
        colours.push(colour)
    raise "analytical gradient requires three stops" if colours.size != 3
    result["colors"] = colours
    result

  -> .automatic(project, plan, timeline)
    raise "auto banding needs a resolved timeline" if timeline == nil
    spec = Util.copy(plan["profile"]["banding"])
    episode = timeline["av_episode"] || project.path(project.settings["timeline"])
    document = JSON.parse(File.read(episode))
    root = Util.absolute(Util.get(document, "root", "."), File.dirname(episode))
    short = plan["profile"]["role"] == "short"
    samples = []
    shots = timeline["tracks"][0]["items"].select ->(s) s["kind"] == "frames" && s["params"]["src"].starts_with?(Util.get(spec, "asset_prefix", "anim:"))
    requested = Util.get(spec, "shots", 6)
    Schema.integer(requested, "banding shots")
    if shots.size > requested
      chosen = []
      i = 0
      while i < requested
        at = requested == 1 ? 0 : Math.round(i * (shots.size - 1) / (requested - 1).to_f).to_i
        chosen.push(shots[at])
        i += 1
      shots = chosen
    shots.each ->(shot)
      params = shot["params"]
      asset = document["assets"][params["src"]]
      directory = Util.absolute(asset["path"], root)
      n = Util.min(shot["f1"] - shot["f0"], Util.get(params, "count", shot["f1"] - shot["f0"]))
      offset = Util.get(params, "in", 0)
      [~0.3, ~0.7].each ->(fraction)
        i = Util.min(Math.round((n - 1) * fraction).to_i, n - 2)
        raise "banding requires adjacent source frames" if i < 0
        pattern = Util.get(asset, "pattern", "%05d.png")
        first = Util.get(asset, "first", 0)
        samples.push({"frame": shot["f0"] + i, "source": directory + "/" + (pattern % (i + offset + first)), "next_source": directory + "/" + (pattern % (i + offset + first + 1))})
    if short && samples.size == 0
      # Program Shorts author exact beat start/duration in their data document.
      beats = JSON.parse(File.read(root + "/short/timeline.json"))["beats"]
      programs = timeline["tracks"][0]["items"].select ->(s) s["kind"] == "program" && (!spec["program_id"] || s["id"] == spec["program_id"])
      raise "Short auto banding requires one program; configure explicit samples" if programs.size != 1
      program = programs[0]
      rate = plan["rate"]
      beats.each ->(beat)
        count = Math.round(beat["dur"].to_f * rate[0] / rate[1]).to_i
        origin = program["f0"] - Util.get(program["params"], "in", 0) + Math.round(beat["start"].to_f * rate[0] / rate[1]).to_i
        [~0.3, ~0.7].each ->(fraction)
          i = Util.min(Math.round((count - 1) * fraction).to_i, count - 2)
          frame = origin + i
          if i >= 0 && frame >= program["f0"] && frame + 1 < program["f1"]
            directory = root + "/short/frames/" + beat["id"]
            samples.push({"frame": frame, "source": directory + "/" + ("%05d.png" % i), "next_source": directory + "/" + ("%05d.png" % (i + 1))})
    samples = samples.map ->(sample) sample.merge({"frame": sample["frame"] - plan["start"]})
    samples = samples.select ->(sample) sample["frame"] >= 0 && sample["frame"] + 1 < plan["frames"]
    spec["samples"] = samples
    if spec["max_samples"]
      Schema.integer(spec["max_samples"], "banding max_samples")
      spec["samples"] = samples.slice(0, spec["max_samples"])
    spec["background"] = Util.absolute(Util.get(spec, "background", short ? "short/bg_rsvg.png" : "anim/bg_rsvg.png"), root)
    spec["gradient"] = gradient(root, short) if !spec["gradient"]
    spec["exclude_normalized"] = short ? [[0, 0, 1, ~0.395833333333], [0, ~0.713541666667, 1, ~0.083333333333]] : [] if !spec.has_key?("exclude_normalized")
    spec

  -> .run(project, media, path, plan, directory, timeline)
    spec = plan["profile"]["banding"]
    spec = automatic(project, plan, timeline) if spec["auto"]
    width = plan["width"]
    height = plan["height"]
    rate = plan["rate"]
    samples = Util.get(spec, "samples", [])
    raise "banding requires at least one sample" if samples.size == 0
    limits = Util.get(spec, "limits", {"rms_detrended": ~0.75, "p99": ~2.0, "blk16": ~2.0, "temporal_rms": ~0.5})
    raise "supply positive banding limits" if limits.size == 0
    limits.keys.each ->(key)
      Schema.one_of(key, ["rms_detrended", "p99", "blk16", "temporal_rms", "temporal_p99"], "banding metric")
      Schema.positive(limits[key], "banding " + key)
    background = project.path(spec["background"])
    references = {}
    references[background] = Util.sha(background)
    bg = Pixels.frame(media, background, -1, width, height, rate)
    gradient = spec["gradient"]
    raise "banding requires an analytical gradient" if gradient == nil
    rectangles = Util.get(spec, "exclude", []).dup
    Util.get(spec, "exclude_normalized", []).each ->(r)
      rectangles.push([Math.round(r[0] * width).to_i, Math.round(r[1] * height).to_i, Math.round(r[2] * width).to_i, Math.round(r[3] * height).to_i])
    rows = []
    visuals = directory + "/banding"
    File.mkdir_p(visuals)
    sheet = Canvas.new(960, 264 * samples.size)
    sheet.clear("#171b22")
    samples.each ->(sample)
      Schema.integer(sample["frame"], "banding frame", 0, plan["frames"] - 1)
      source = project.path(sample["source"])
      references[source] = Util.sha(source)
      src = Pixels.frame(media, source, -1, width, height, rate)
      exclusions = rectangles.dup
      Util.get(sample, "exclude", []).each ->(r) exclusions.push(r)
      exclusions.each ->(r)
        raise "invalid banding exclusion rectangle" if type(r) != "Array" || r.size != 4 || r[2] <= 0 || r[3] <= 0
      mask = Banding.mask(src, bg, width, height, exclusions)
      decoded = Pixels.frame(media, path, sample["frame"], width, height, rate, "stretch", 16)
      error = residual(decoded, width, height, 16, gradient)
      row = metrics(error, mask, width, height)
      original = metrics(residual(src, width, height, 8, gradient), mask, width, height)
      row["rms_8bit_source"] = original["rms"]
      row["rms_detrended_8bit_source"] = original["rms_detrended"]
      if sample["next_source"]
        next_source = project.path(sample["next_source"])
        references[next_source] = Util.sha(next_source)
        next_src = Pixels.frame(media, next_source, -1, width, height, rate)
        next_mask = Banding.mask(next_src, bg, width, height, exclusions)
        next_decoded = Pixels.frame(media, path, sample["frame"] + 1, width, height, rate, "stretch", 16)
        next_error = residual(next_decoded, width, height, 16, gradient)
        temporal = temporal_delta(error, next_error, mask, next_mask, width * height)
        temporal_metrics = metrics(temporal[0], temporal[1], width, height)
        row["temporal_rms"] = temporal_metrics["rms"]
        row["temporal_p99"] = temporal_metrics["p99"]
      diagnostic = visuals + "/frame-" + sample["frame"].to_s + "-" + rows.size.to_s + ".png"
      tile = Banding.diagnostic(src, decoded, error, mask, width, height, sample["frame"])
      begin
        tile.write_png(diagnostic)
        sheet.image(tile, 0, rows.size * 264, 960, 264)
      ensure
        tile.close
      row["diagnostic"] = "banding/" + File.basename(diagnostic)
      row["frame"] = sample["frame"]
      row["ok"] = Util.all(limits.keys.map ->(key) row.has_key?(key) && row[key] <= limits[key])
      rows.push(row)
    sheet.write(visuals + "/contact-sheet.jpg")
    sheet.close
    references.keys.each ->(file)
      raise "banding reference changed" if Util.sha(file) != references[file]
    result = {"ok": Util.all(rows.map ->(r) r["ok"]), "sha256": Util.sha(path), "geometry": [width, height], "rate": rate, "references": references, "limits": limits, "frames": rows, "contact_sheet": "banding/contact-sheet.jpg"}
    result["worst_frames"] = (rows.sort_by ->(r) -r["p99"]).slice(0, 5).map ->(r) r["frame"]
    ["rms", "rms_detrended", "p99", "blk16", "temporal_rms", "temporal_p99"].each ->(key)
      if Util.all(rows.map ->(r) r.has_key?(key))
        values = rows.map ->(r) r[key]
        result["mean_" + key] = values.sum / values.size.to_f
        result["max_" + key] = values.max
    File.atomic_write(directory + "/banding.html", "<!doctype html><meta charset=\"utf-8\"><title>AV QC</title><h1>AV banding QC</h1><p>SHA256 " + result["sha256"] + "</p><img style=\"max-width:100%\" src=\"banding/contact-sheet.jpg\">")
    Util.json(directory + "/banding.json", result)
    result

  -> .temporal_delta(first, second, mask, next_mask, n) (f64[] f64[] u8[] u8[] i64)
    delta = f64[n]
    valid = u8[n]
    i = 0 ## i64
    while i < n
      delta[i] = second[i] - first[i]
      valid[i] = mask[i] & next_mask[i]
      i += 1
    [delta, valid]

  -> .diagnostic(source, decoded, error, mask, width, height, frame) (u8[] u8[] f64[] u8[] i64 i64 i64)
    src_canvas = Canvas.new(width, height)
    dec_canvas = Canvas.new(width, height)
    heat_canvas = Canvas.new(width, height)
    src_ptr = src_canvas.data_pointer ## i64
    dec_ptr = dec_canvas.data_pointer ## i64
    heat_ptr = heat_canvas.data_pointer ## i64
    stride = src_canvas.stride ## i64
    y = 0 ## i64
    while y < height
      x = 0 ## i64
      while x < width
        p = y * width + x
        dest = y * stride + x * 4
        value = mask[p] == 0 ? 128 : Math.round(~128.0 + ~7.0 * error[p]).to_i
        value = 0 if value < 0
        value = 255 if value > 255
        c = 0 ## i64
        while c < 3
          raw_store_u8(src_ptr, dest + c, source[3 * p + c])
          raw_store_u8(dec_ptr, dest + c, (decoded[6 * p + 2 * c] + 256 * decoded[6 * p + 2 * c + 1]) / 257)
          raw_store_u8(heat_ptr, dest + c, value)
          c += 1
        raw_store_u8(src_ptr, dest + 3, 255)
        raw_store_u8(dec_ptr, dest + 3, 255)
        raw_store_u8(heat_ptr, dest + 3, 255)
        x += 1
      y += 1
    tile = Canvas.new(960, 264)
    tile.clear("#171b22")
    begin
      i = 0
      [src_canvas, dec_canvas, heat_canvas].each ->(canvas)
        tile.image(canvas, i * 320, 24, 320, 240, fit: "contain")
        label = ["Source", "Decoded", "Residual x7"][i]
        tile.text(i * 320 + 4, 17, frame.to_s + ": " + label, size: 12, fill: "#ffffff")
        i += 1
    ensure
      src_canvas.close
      dec_canvas.close
      heat_canvas.close
    tile
