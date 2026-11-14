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

  -> .blur_into(input, _temporary, result, kernel, width, height) (f64[] f64[] f64[] f64[] i64 i64) f64[]
    ccall("w_media_banding_op", "blur", [input, result], kernel, [width, height])

  -> .blur(input, width, height) (f64[] i64 i64) f64[]
    n = width * height
    blur_into(input, f64[1], f64[n], gaussian_kernel(), width, height)

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
    ccall("w_media_banding_op", "ideal", [width, height], [cx, cy, radius, mid, l0, l1, l2], ideal)

  -> .residual_with_ideal(bytes, ideal, _raw_buf, _tmp_buf, out_buf, kernel, width, height, depth) (u8[] f64[] f64[] f64[] f64[] f64[] i64 i64 i64) f64[]
    ccall("w_media_banding_op", "residual", [bytes, ideal, out_buf], kernel, [width, height, depth])

  -> .residual(bytes, width, height, depth, gradient) (u8[] i64 i64 i64 Hash) f64[]
    n = width * height
    ideal = ideal_luma(width, height, gradient)
    residual_with_ideal(bytes, ideal, f64[1], f64[1], f64[n], gaussian_kernel(), width, height, depth)

  -> .mask(source, background, width, height, excludes, margin = 8, border = 20) (u8[] u8[] i64 i64 Array i64 i64) u8[]
    result = u8[width * height]
    ccall("w_media_banding_op", "mask", [source, background, result], excludes, [width, height, margin, border])

  -> .metrics_into(error, mask, _vals_buf, width, height) (f64[] u8[] f64[] i64 i64)
    r = ccall("w_media_banding_op", "metrics", error, mask, [width, height])
    raise "less than 1% usable background after masks" if r[0] < width * height / 100
    raise "insufficient block boundaries after masks" if r[1] == 0 || r[2] == 0
    {"bg_frac": r[3], "rms": r[4], "mean_err": r[5], "rms_detrended": r[6], "p99": r[7], "blk16": r[8]}

  -> .metrics(error, mask, width, height, temporal = nil) (f64[] u8[] i64 i64 Object)
    metrics_into(error, mask, f64[1], width, height)

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

  -> .prepare_frames(project, plan, timeline)
    spec = plan["profile"]["banding"]
    return [nil, []] if spec == nil || spec.size == 0
    spec = automatic(project, plan, timeline) if spec["auto"]
    samples = Util.get(spec, "samples", [])
    raise "banding requires at least one sample" if samples.size == 0
    needed = []
    samples.each ->(sample)
      f = sample["frame"]
      Schema.integer(f, "banding frame", 0, plan["frames"] - 1)
      needed.push(f)
      if sample["next_source"]
        Schema.integer(f + 1, "banding next frame", 0, plan["frames"] - 1)
        needed.push(f + 1)
    [spec, Util.unique(needed)]

  -> .run(project, media, path, plan, directory, timeline, pre_decoded_by_frame = nil, pre_spec = nil, known_sha = nil)
    spec = pre_spec
    if spec == nil
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
    still_paths = [background]
    samples.each ->(sample)
      still_paths.push(project.path(sample["source"]))
      still_paths.push(project.path(sample["next_source"])) if sample["next_source"]
    unique_stills = Util.unique(still_paths)
    references = {}
    still_cache = {}
    if unique_stills.size <= 1
      unique_stills.each ->(sp)
        references[sp] = Util.sha_cached(sp)
        still_cache[sp] = Pixels.still_frame(sp, width, height, "stretch", 8)
    else
      nw = Util.min(4, unique_stills.size)
      threads = []
      wi = 0
      while wi < nw
        w_idx = wi
        th = Thread.new ->
          w_res = nil
          begin
            out = []
            si = w_idx
            while si < unique_stills.size
              sp = unique_stills[si]
              out.push([sp, Util.sha_cached(sp), Pixels.still_frame(sp, width, height, "stretch", 8)])
              si += nw
            w_res = ["ok", out]
          rescue err
            w_res = ["err", err]
          w_res
        threads.push(th)
        wi += 1
      first_err = nil
      threads.each ->(th)
        res = th.join
        if res[0] == "err"
          first_err = res[1] if first_err == nil
        else
          res[1].each ->(item)
            references[item[0]] = item[1]
            still_cache[item[0]] = item[2]
      raise first_err if first_err != nil
    bg = still_cache[background]
    gradient = spec["gradient"]
    raise "banding requires an analytical gradient" if gradient == nil
    ideal = ideal_luma(width, height, gradient)
    kernel = gaussian_kernel()
    npix = width * height
    dummy_buf = f64[1]
    rectangles = Util.get(spec, "exclude", []).dup
    Util.get(spec, "exclude_normalized", []).each ->(r)
      rectangles.push([Math.round(r[0] * width).to_i, Math.round(r[1] * height).to_i, Math.round(r[2] * width).to_i, Math.round(r[3] * height).to_i])
    decoded_by_frame = pre_decoded_by_frame
    if decoded_by_frame == nil
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
    visuals = directory + "/banding"
    File.mkdir_p(visuals)
    sample_infos = []
    mask_jobs = []
    mask_seen = {}
    orig_needed = {}
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
      ex_json = JSON.encode(exclusions)
      mkey = source + "|" + ex_json
      orig_needed[mkey] = true
      if !mask_seen.has_key?(mkey)
        mask_seen[mkey] = true
        mask_jobs.push([mkey, src, exclusions])
      next_src = nil
      nmkey = nil
      if sample["next_source"]
        next_source = project.path(sample["next_source"])
        references[next_source] = Util.sha(next_source) if !references.has_key?(next_source)
        if !still_cache.has_key?(next_source)
          still_cache[next_source] = Pixels.frame(media, next_source, -1, width, height, rate)
        next_src = still_cache[next_source]
        nmkey = next_source + "|" + ex_json
        if !mask_seen.has_key?(nmkey)
          mask_seen[nmkey] = true
          mask_jobs.push([nmkey, next_src, exclusions])
      sample_infos.push([sample, src, mkey, next_src, nmkey])
    mask_cache = {}
    src_orig_cache = {}
    if mask_jobs.size <= 1
      src_err_buf = f64[npix]
      mask_jobs.each ->(mj)
        mk = mj[0]
        msrc = mj[1]
        mex = mj[2]
        msk = Banding.mask(msrc, bg, width, height, mex)
        mask_cache[mk] = msk
        if orig_needed.has_key?(mk)
          se = residual_with_ideal(msrc, ideal, dummy_buf, dummy_buf, src_err_buf, kernel, width, height, 8)
          src_orig_cache[mk] = metrics_into(se, msk, dummy_buf, width, height)
    else
      mnw = Util.min(4, mask_jobs.size)
      mthreads = []
      mwi = 0
      while mwi < mnw
        mw_idx = mwi
        mth = Thread.new ->
          mw_res = nil
          begin
            mout = []
            local_se = f64[npix]
            local_dm = f64[1]
            mi = mw_idx
            while mi < mask_jobs.size
              mj = mask_jobs[mi]
              mk = mj[0]
              msrc = mj[1]
              mex = mj[2]
              msk = Banding.mask(msrc, bg, width, height, mex)
              orig = nil
              if orig_needed.has_key?(mk)
                se = residual_with_ideal(msrc, ideal, local_dm, local_dm, local_se, kernel, width, height, 8)
                orig = metrics_into(se, msk, local_dm, width, height)
              mout.push([mk, msk, orig])
              mi += mnw
            mw_res = ["ok", mout]
          rescue merr
            mw_res = ["err", merr]
          mw_res
        mthreads.push(mth)
        mwi += 1
      m_err = nil
      mthreads.each ->(mth)
        mres = mth.join
        if mres[0] == "err"
          m_err = mres[1] if m_err == nil
        else
          mres[1].each ->(item)
            mask_cache[item[0]] = item[1]
            src_orig_cache[item[0]] = item[2] if item[2] != nil
      raise m_err if m_err != nil
    rows = []
    sheet = Canvas.new(960, 264 * samples.size)
    sheet.clear("#171b22")
    eval_sample = ->(si, bufs)
      err_buf = bufs[0]
      next_err_buf = bufs[1]
      delta_buf = bufs[2]
      valid_buf = bufs[3]
      local_dm = bufs[4]
      info = sample_infos[si]
      sample = info[0]
      src = info[1]
      mkey = info[2]
      next_src = info[3]
      nmkey = info[4]
      mask = mask_cache[mkey]
      decoded = decoded_by_frame[sample["frame"]]
      error = residual_with_ideal(decoded, ideal, local_dm, local_dm, err_buf, kernel, width, height, 16)
      row = metrics_into(error, mask, local_dm, width, height)
      original = src_orig_cache[mkey]
      row["rms_8bit_source"] = original["rms"]
      row["rms_detrended_8bit_source"] = original["rms_detrended"]
      if sample["next_source"]
        next_mask = mask_cache[nmkey]
        next_decoded = decoded_by_frame[sample["frame"] + 1]
        next_error = residual_with_ideal(next_decoded, ideal, local_dm, local_dm, next_err_buf, kernel, width, height, 16)
        temporal_delta_into(error, next_error, mask, next_mask, delta_buf, valid_buf, npix)
        temporal_metrics = metrics_into(delta_buf, valid_buf, local_dm, width, height)
        row["temporal_rms"] = temporal_metrics["rms"]
        row["temporal_p99"] = temporal_metrics["temporal_p99"] == nil ? temporal_metrics["p99"] : temporal_metrics["temporal_p99"]
      diagnostic = visuals + "/frame-" + sample["frame"].to_s + "-" + si.to_s + ".png"
      tile = Banding.diagnostic(src, decoded, error, mask, width, height, sample["frame"])
      begin
        tile.write(diagnostic, quality: ~0.1, alpha: false)
      rescue werr
        tile.close
        raise werr
      row["diagnostic"] = "banding/" + File.basename(diagnostic)
      row["frame"] = sample["frame"]
      row["ok"] = Util.all(limits.keys.map ->(key) row.has_key?(key) && row[key] <= limits[key])
      [row, tile]
    if samples.size <= 1
      sbufs = [f64[npix], f64[npix], f64[npix], ByteArray.uninit(npix), dummy_buf]
      si = 0
      while si < samples.size
        pair = eval_sample.call(si, sbufs)
        tile = pair[1]
        begin
          sheet.image(tile, 0, si * 264, 960, 264)
        ensure
          tile.close
        rows.push(pair[0])
        si += 1
    else
      snw = Util.min(4, samples.size)
      sthreads = []
      swi = 0
      while swi < snw
        sw_idx = swi
        sth = Thread.new ->
          sw_res = nil
          begin
            sout = []
            wbufs = [f64[npix], f64[npix], f64[npix], ByteArray.uninit(npix), f64[1]]
            si = sw_idx
            while si < samples.size
              pair = eval_sample.call(si, wbufs)
              sout.push([si, pair[0], pair[1]])
              si += snw
            sw_res = ["ok", sout]
          rescue serr
            sw_res = ["err", serr, sout]
          sw_res
        sthreads.push(sth)
        swi += 1
      by_idx = {}
      s_err = nil
      sthreads.each ->(sth)
        sres = sth.join
        if sres[0] == "err"
          s_err = sres[1] if s_err == nil
          if sres.size > 2 && sres[2] != nil
            sres[2].each ->(it)
              it[2].close
        else
          sres[1].each ->(it)
            by_idx[it[0]] = [it[1], it[2]]
      if s_err != nil
        by_idx.keys.each ->(k)
          by_idx[k][1].close
        sheet.close
        raise s_err
      si = 0
      while si < samples.size
        pair = by_idx[si]
        tile = pair[1]
        begin
          sheet.image(tile, 0, si * 264, 960, 264)
        ensure
          tile.close
        rows.push(pair[0])
        si += 1
    sheet.write(visuals + "/contact-sheet.jpg", alpha: false)
    sheet.close
    references.keys.each ->(file)
      raise "banding reference changed" if Util.sha(file) != references[file]
    out_sha = known_sha != nil ? known_sha : Util.sha(path)
    result = {"ok": Util.all(rows.map ->(r) r["ok"]), "sha256": out_sha, "geometry": [width, height], "rate": rate, "references": references, "limits": limits, "frames": rows, "contact_sheet": "banding/contact-sheet.jpg"}
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
    ccall("w_media_banding_op", "temporal", [first, second, delta], [mask, next_mask, valid], [n])
    n

  -> .temporal_delta(first, second, mask, next_mask, n) (f64[] f64[] u8[] u8[] i64)
    delta = f64[n]
    valid = u8[n]
    temporal_delta_into(first, second, mask, next_mask, delta, valid, n)
    [delta, valid]

  -> .paint_panels(tile_ptr, stride, source, decoded, error, mask, width, height, rx, ry, rw, rh) (i64 i64 u8[] u8[] f64[] u8[] i64 i64 i64 i64 i64 i64) i64
    ccall("w_media_banding_op", "paint_panels", [tile_ptr, stride, width, height, rx, ry, rw, rh], [source, decoded, mask], error)
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
