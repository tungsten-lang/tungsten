in Av

+ Banding
  -> .gaussian_kernel () f64[]
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
    kernel

  -> .blur_into(input, temporary, result, kernel, width, height) (f64[] f64[] f64[] f64[] i64 i64) f64[]
    k0 = kernel[0]
    k1 = kernel[1]
    k2 = kernel[2]
    k3 = kernel[3]
    k4 = kernel[4]
    k5 = kernel[5]
    k6 = kernel[6]
    y = 0 ## i64
    while y < height
      row = y * width
      x = 0 ## i64
      while x < width
        if x >= 6 && x < width - 6
          p = row + x
          v = input[p] * k6 + (input[p - 1] + input[p + 1]) * k5 + (input[p - 2] + input[p + 2]) * k4 + (input[p - 3] + input[p + 3]) * k3 + (input[p - 4] + input[p + 4]) * k2 + (input[p - 5] + input[p + 5]) * k1 + (input[p - 6] + input[p + 6]) * k0
          temporary[p] = v
        else
          v = ~0.0
          k = -6 ## i64
          while k <= 6
            at = x + k
            at = 0 if at < 0
            at = width - 1 if at >= width
            v += input[row + at] * kernel[k + 6]
            k += 1
          temporary[row + x] = v
        x += 1
      y += 1
    y = 0
    while y < height
      row = y * width
      if y >= 6 && y < height - 6
        w1 = width
        w2 = width * 2
        w3 = width * 3
        w4 = width * 4
        w5 = width * 5
        w6 = width * 6
        x = 0 ## i64
        while x < width
          p = row + x
          result[p] = temporary[p] * k6 + (temporary[p - w1] + temporary[p + w1]) * k5 + (temporary[p - w2] + temporary[p + w2]) * k4 + (temporary[p - w3] + temporary[p + w3]) * k3 + (temporary[p - w4] + temporary[p + w4]) * k2 + (temporary[p - w5] + temporary[p + w5]) * k1 + (temporary[p - w6] + temporary[p + w6]) * k0
          x += 1
      else
        x = 0 ## i64
        while x < width
          v = ~0.0
          k = -6 ## i64
          while k <= 6
            at = y + k
            at = 0 if at < 0
            at = height - 1 if at >= height
            v += temporary[at * width + x] * kernel[k + 6]
            k += 1
          result[row + x] = v
          x += 1
      y += 1
    result

  -> .blur(input, width, height) (f64[] i64 i64) f64[]
    n = width * height
    blur_into(input, f64[n], f64[n], gaussian_kernel(), width, height)

  -> .ideal_luma(width, height, gradient) (i64 i64 Hash) f64[]
    cx = gradient["cx"].to_f
    cy = gradient["cy"].to_f
    radius = gradient["r"].to_f
    mid = gradient["mid"].to_f
    raise "gradient requires positive radius and mid in 0..1" if radius <= 0 || mid <= 0 || mid >= 1
    colours = Util.get(gradient, "colors", [[19, 27, 44], [9, 13, 21], [4, 6, 10]])
    l0 = ~0.0
    l1 = ~0.0
    l2 = ~0.0
    i = 0 ## i64
    while i < 3
      c = colours[i]
      lv = ~16.0 + ~219.0 * (~0.2126 * c[0] + ~0.7152 * c[1] + ~0.0722 * c[2]) / ~255.0
      l0 = lv if i == 0
      l1 = lv if i == 1
      l2 = lv if i == 2
      i += 1
    ideal = f64[width * height]
    cx_px = cx * width
    cy_px = cy * height
    inv_rx = ~1.0 / (radius * width)
    inv_ry = ~1.0 / (radius * height)
    slope0 = (l1 - l0) / mid
    slope1 = (l2 - l1) / (~1.0 - mid)
    y = 0 ## i64
    while y < height
      dy = (y + ~0.5 - cy_px) * inv_ry
      dy2 = dy * dy
      row = y * width
      x = 0 ## i64
      while x < width
        dx = (x + ~0.5 - cx_px) * inv_rx
        t = Math.sqrt(dx * dx + dy2)
        t = ~1.0 if t > ~1.0
        ideal[row + x] = t <= mid ? l0 + slope0 * t : l1 + slope1 * (t - mid)
        x += 1
      y += 1
    ideal

  -> .residual_with_ideal(bytes, ideal, raw_buf, tmp_buf, out_buf, kernel, width, height, depth) (u8[] f64[] f64[] f64[] f64[] f64[] i64 i64 i64) f64[]
    n = width * height
    if depth == 16
      scale16 = ~219.0 / (~255.0 * ~257.0)
      i = 0 ## i64
      while i < n
        p = i * 6
        r = bytes[p] + 256 * bytes[p + 1]
        g = bytes[p + 2] + 256 * bytes[p + 3]
        b = bytes[p + 4] + 256 * bytes[p + 5]
        raw_buf[i] = (~16.0 + (~0.2126 * r + ~0.7152 * g + ~0.0722 * b) * scale16) - ideal[i]
        i += 1
    else
      scale8 = ~219.0 / ~255.0
      i = 0 ## i64
      while i < n
        p = i * 3
        raw_buf[i] = (~16.0 + (~0.2126 * bytes[p] + ~0.7152 * bytes[p + 1] + ~0.0722 * bytes[p + 2]) * scale8) - ideal[i]
        i += 1
    blur_into(raw_buf, tmp_buf, out_buf, kernel, width, height)

  -> .residual(bytes, width, height, depth, gradient) (u8[] i64 i64 i64 Hash) f64[]
    n = width * height
    ideal = ideal_luma(width, height, gradient)
    residual_with_ideal(bytes, ideal, f64[n], f64[n], f64[n], gaussian_kernel(), width, height, depth)

  -> .mask(source, background, width, height, excludes, margin = 8, border = 20) (u8[] u8[] i64 i64 Array i64 i64) u8[]
    n = width * height
    diff = u8[n]
    i = 0 ## i64
    while i < n
      p = i * 3
      diff[i] = 1 if source[p] != background[p] || source[p + 1] != background[p + 1] || source[p + 2] != background[p + 2]
      i += 1
    ri = 0
    while ri < excludes.size
      r = excludes[ri]
      rx0 = r[0].to_i ## i64
      ry0 = r[1].to_i ## i64
      rx1 = rx0 + r[2].to_i
      ry1 = ry0 + r[3].to_i
      rx0 = 0 if rx0 < 0
      ry0 = 0 if ry0 < 0
      rx1 = width if rx1 > width
      ry1 = height if ry1 > height
      ry = ry0
      while ry < ry1
        row = ry * width
        rx = rx0
        while rx < rx1
          diff[row + rx] = 1
          rx += 1
        ry += 1
      ri += 1
    stride = width + 1
    blocked = i32[stride * (height + 1)]
    y = 0 ## i64
    while y < height
      row_sum = 0 ## i64
      src_row = y * width
      prev_row = y * stride
      cur_row = (y + 1) * stride
      x = 0 ## i64
      while x < width
        row_sum += diff[src_row + x]
        blocked[cur_row + x + 1] = blocked[prev_row + x + 1] + row_sum
        x += 1
      y += 1
    result = u8[n]
    y = border
    while y < height - border
      y0 = y - margin
      y1 = y + margin + 1
      y0 = 0 if y0 < 0
      y1 = height if y1 > height
      r0 = y0 * stride
      r1 = y1 * stride
      out_row = y * width
      x = border
      while x < width - border
        x0 = x - margin
        x1 = x + margin + 1
        x0 = 0 if x0 < 0
        x1 = width if x1 > width
        count = blocked[r1 + x1] - blocked[r0 + x1] - blocked[r1 + x0] + blocked[r0 + x0]
        result[out_row + x] = 1 if count == 0
        x += 1
      y += 1
    result

  -> .select_kth(vals, n, k) (f64[] i64 i64) f64
    lo = 0 ## i64
    hi = n - 1
    while lo < hi
      mid = (lo + hi) >> 1
      a = vals[lo]
      b = vals[mid]
      c = vals[hi]
      pivot = b
      if (a <= b && b <= c) || (c <= b && b <= a)
        pivot = b
      elsif (b <= a && a <= c) || (c <= a && a <= b)
        pivot = a
      else
        pivot = c
      lt = lo
      idx = lo
      gt = hi
      while idx <= gt
        v = vals[idx]
        if v < pivot
          tmp = vals[lt]
          vals[lt] = v
          vals[idx] = tmp
          lt += 1
          idx += 1
        elsif v > pivot
          tmp = vals[gt]
          vals[gt] = v
          vals[idx] = tmp
          gt -= 1
        else
          idx += 1
      if k < lt
        hi = lt - 1
      elsif k > gt
        lo = gt + 1
      else
        return pivot
    vals[lo]

  -> .p99_exact(vals, count) (f64[] i64) f64
    hist = i32[65536]
    i = 0 ## i64
    while i < count
      b = (vals[i] * ~2048.0).to_i
      b = 65535 if b > 65535
      hist[b] += 1
      i += 1
    q = ~0.99 * (count - 1)
    lo_rank = q.to_i ## i64
    hi_rank = lo_rank + 1 < count ? lo_rank + 1 : lo_rank
    prefix = 0 ## i64
    b_lo = 0 ## i64
    while b_lo < 65536
      c = hist[b_lo]
      break if prefix + c > lo_rank
      prefix += c
      b_lo += 1
    bucket_n = hist[b_lo] ## i64
    bucket = f64[bucket_n]
    bi = 0 ## i64
    next_min = ~1e300
    need_next = hi_rank >= prefix + bucket_n
    i = 0
    while i < count
      v = vals[i]
      b = (v * ~2048.0).to_i
      b = 65535 if b > 65535
      if b == b_lo
        bucket[bi] = v
        bi += 1
      elsif need_next && b > b_lo && v < next_min
        next_min = v
      i += 1
    local_lo = lo_rank - prefix
    v_lo = select_kth(bucket, bi, local_lo)
    v_hi = v_lo
    if hi_rank != lo_rank
      if need_next
        v_hi = next_min
      else
        j = local_lo + 1
        m = bucket[j]
        j += 1
        while j < bi
          m = bucket[j] if bucket[j] < m
          j += 1
        v_hi = m
    v_lo + (v_hi - v_lo) * (q - lo_rank)

  -> .metrics_into(error, mask, vals_buf, width, height) (f64[] u8[] f64[] i64 i64)
    total = ~0.0
    squared = ~0.0
    count = 0 ## i64
    boundaries = ~0.0
    interiors = ~0.0
    nb = 0 ## i64
    ni = 0 ## i64
    y = 0 ## i64
    while y < height
      row = y * width
      y_boundary = y > 0 && (y & 15) == 0
      x = 0 ## i64
      while x < width
        p = row + x
        if mask[p] != 0
          e = error[p]
          total += e
          squared += e * e
          vals_buf[count] = e < ~0.0 ? ~0.0 - e : e
          count += 1
          if x > 0 && mask[p - 1] != 0
            d = e - error[p - 1]
            d = ~0.0 - d if d < ~0.0
            if (x & 15) == 0
              boundaries += d
              nb += 1
            else
              interiors += d
              ni += 1
          if y > 0 && mask[p - width] != 0
            d = e - error[p - width]
            d = ~0.0 - d if d < ~0.0
            if y_boundary
              boundaries += d
              nb += 1
            else
              interiors += d
              ni += 1
        x += 1
      y += 1
    raise "less than 1% usable background after masks" if count < width * height / 100
    raise "insufficient block boundaries after masks" if nb == 0 || ni == 0
    p99 = p99_exact(vals_buf, count)
    mean = total / count
    {"bg_frac": count / (width * height + ~0.0), "rms": Math.sqrt(squared / count), "mean_err": mean, "rms_detrended": Math.sqrt(Util.max(~0.0, squared / count - mean * mean)), "p99": p99, "blk16": (boundaries / nb) / Util.max(interiors / ni, ~1e-9)}

  -> .metrics(error, mask, width, height, temporal = nil) (f64[] u8[] i64 i64 Object)
    metrics_into(error, mask, f64[width * height], width, height)

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
        samples.push({"frame": shot["f0"] + i, "source": directory + "/" + Util.format_frame(pattern, i + offset + first), "next_source": directory + "/" + Util.format_frame(pattern, i + offset + first + 1)})
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
            samples.push({"frame": frame, "source": directory + "/" + Util.format_frame("%05d.png", i), "next_source": directory + "/" + Util.format_frame("%05d.png", i + 1)})
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
    still_cache = {}
    bg = Pixels.frame(media, background, -1, width, height, rate)
    still_cache[background] = bg
    gradient = spec["gradient"]
    raise "banding requires an analytical gradient" if gradient == nil
    ideal = ideal_luma(width, height, gradient)
    kernel = gaussian_kernel()
    npix = width * height
    raw_buf = f64[npix]
    tmp_buf = f64[npix]
    err_buf = f64[npix]
    src_err_buf = f64[npix]
    next_err_buf = f64[npix]
    delta_buf = f64[npix]
    valid_buf = u8[npix]
    vals_buf = f64[npix]
    rectangles = Util.get(spec, "exclude", []).dup
    Util.get(spec, "exclude_normalized", []).each ->(r)
      rectangles.push([Math.round(r[0] * width).to_i, Math.round(r[1] * height).to_i, Math.round(r[2] * width).to_i, Math.round(r[3] * height).to_i])
    needed_frames = []
    samples.each ->(sample)
      f = sample["frame"]
      Schema.integer(f, "banding frame", 0, plan["frames"] - 1)
      needed_frames.push(f)
      if sample["next_source"]
        Schema.integer(f + 1, "banding next frame", 0, plan["frames"] - 1)
        needed_frames.push(f + 1)
    unique_frames = Util.unique(needed_frames)
    extracted = Pixels.frames(media, path, unique_frames, width, height, rate, "stretch", 16)
    decoded_by_frame = {}
    fi = 0
    while fi < unique_frames.size
      decoded_by_frame[unique_frames[fi]] = extracted[fi]
      fi += 1
    rows = []
    visuals = directory + "/banding"
    File.mkdir_p(visuals)
    sheet = Canvas.new(960, 264 * samples.size)
    sheet.clear("#171b22")
    samples.each ->(sample)
      source = project.path(sample["source"])
      references[source] = Util.sha(source) if !references.has_key?(source)
      if !still_cache.has_key?(source)
        still_cache[source] = Pixels.frame(media, source, -1, width, height, rate)
      src = still_cache[source]
      exclusions = rectangles.dup
      Util.get(sample, "exclude", []).each ->(r) exclusions.push(r)
      exclusions.each ->(r)
        raise "invalid banding exclusion rectangle" if type(r) != "Array" || r.size != 4 || r[2] <= 0 || r[3] <= 0
      mask = Banding.mask(src, bg, width, height, exclusions)
      decoded = decoded_by_frame[sample["frame"]]
      error = residual_with_ideal(decoded, ideal, raw_buf, tmp_buf, err_buf, kernel, width, height, 16)
      row = metrics_into(error, mask, vals_buf, width, height)
      src_err = residual_with_ideal(src, ideal, raw_buf, tmp_buf, src_err_buf, kernel, width, height, 8)
      original = metrics_into(src_err, mask, vals_buf, width, height)
      row["rms_8bit_source"] = original["rms"]
      row["rms_detrended_8bit_source"] = original["rms_detrended"]
      if sample["next_source"]
        next_source = project.path(sample["next_source"])
        references[next_source] = Util.sha(next_source) if !references.has_key?(next_source)
        if !still_cache.has_key?(next_source)
          still_cache[next_source] = Pixels.frame(media, next_source, -1, width, height, rate)
        next_src = still_cache[next_source]
        next_mask = Banding.mask(next_src, bg, width, height, exclusions)
        next_decoded = decoded_by_frame[sample["frame"] + 1]
        next_error = residual_with_ideal(next_decoded, ideal, raw_buf, tmp_buf, next_err_buf, kernel, width, height, 16)
        temporal_delta_into(error, next_error, mask, next_mask, delta_buf, valid_buf, npix)
        temporal_metrics = metrics_into(delta_buf, valid_buf, vals_buf, width, height)
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

  -> .temporal_delta_into(first, second, mask, next_mask, delta, valid, n) (f64[] f64[] u8[] u8[] f64[] u8[] i64) i64
    i = 0 ## i64
    while i < n
      delta[i] = second[i] - first[i]
      valid[i] = mask[i] & next_mask[i]
      i += 1
    n

  -> .temporal_delta(first, second, mask, next_mask, n) (f64[] f64[] u8[] u8[] i64)
    delta = f64[n]
    valid = u8[n]
    temporal_delta_into(first, second, mask, next_mask, delta, valid, n)
    [delta, valid]

  -> .paint_panels(tile_ptr, stride, source, decoded, error, mask, width, height, rx, ry, rw, rh) (i64 i64 u8[] u8[] f64[] u8[] i64 i64 i64 i64 i64 i64) i64
    py = 0 ## i64
    while py < 240
      dst_row = (24 + py) * stride
      px = 0 ## i64
      while px < 320
        d0 = dst_row + px * 4
        d1 = dst_row + (320 + px) * 4
        d2 = dst_row + (640 + px) * 4
        raw_store_u8(tile_ptr, d0, 0)
        raw_store_u8(tile_ptr, d0 + 1, 0)
        raw_store_u8(tile_ptr, d0 + 2, 0)
        raw_store_u8(tile_ptr, d0 + 3, 255)
        raw_store_u8(tile_ptr, d1, 0)
        raw_store_u8(tile_ptr, d1 + 1, 0)
        raw_store_u8(tile_ptr, d1 + 2, 0)
        raw_store_u8(tile_ptr, d1 + 3, 255)
        raw_store_u8(tile_ptr, d2, 0)
        raw_store_u8(tile_ptr, d2 + 1, 0)
        raw_store_u8(tile_ptr, d2 + 2, 0)
        raw_store_u8(tile_ptr, d2 + 3, 255)
        px += 1
      py += 1
    dy = 0 ## i64
    while dy < rh
      sy = (dy * 2 + 1) * height / (rh * 2)
      sy = height - 1 if sy >= height
      src_row = sy * width
      dst_row = (24 + ry + dy) * stride
      dx = 0 ## i64
      while dx < rw
        sx = (dx * 2 + 1) * width / (rw * 2)
        sx = width - 1 if sx >= width
        p = src_row + sx
        p3 = p * 3
        p6 = p * 6
        heat = mask[p] == 0 ? 128 : Math.round(~128.0 + ~7.0 * error[p]).to_i
        heat = 0 if heat < 0
        heat = 255 if heat > 255
        o0 = dst_row + (rx + dx) * 4
        o1 = dst_row + (320 + rx + dx) * 4
        o2 = dst_row + (640 + rx + dx) * 4
        raw_store_u8(tile_ptr, o0, source[p3])
        raw_store_u8(tile_ptr, o0 + 1, source[p3 + 1])
        raw_store_u8(tile_ptr, o0 + 2, source[p3 + 2])
        raw_store_u8(tile_ptr, o0 + 3, 255)
        raw_store_u8(tile_ptr, o1, (decoded[p6] + 256 * decoded[p6 + 1]) / 257)
        raw_store_u8(tile_ptr, o1 + 1, (decoded[p6 + 2] + 256 * decoded[p6 + 3]) / 257)
        raw_store_u8(tile_ptr, o1 + 2, (decoded[p6 + 4] + 256 * decoded[p6 + 5]) / 257)
        raw_store_u8(tile_ptr, o1 + 3, 255)
        raw_store_u8(tile_ptr, o2, heat)
        raw_store_u8(tile_ptr, o2 + 1, heat)
        raw_store_u8(tile_ptr, o2 + 2, heat)
        raw_store_u8(tile_ptr, o2 + 3, 255)
        dx += 1
      dy += 1
    rw * rh

  -> .diagnostic(source, decoded, error, mask, width, height, frame) (u8[] u8[] f64[] u8[] i64 i64 i64)
    tile = Canvas.new(960, 264)
    tile.clear("#171b22")
    rect = Scaler.fit(width, height, 320, 240, "contain")[:rect]
    paint_panels(tile.data_pointer, tile.stride, source, decoded, error, mask, width, height, rect[0], rect[1], rect[2], rect[3])
    labels = ["Source", "Decoded", "Residual x7"]
    i = 0
    while i < 3
      tile.text(i * 320 + 4, 17, frame.to_s + ": " + labels[i], size: 12, fill: "#ffffff")
      i += 1
    tile
