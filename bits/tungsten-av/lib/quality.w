in Av

+ Quality
  -> .metric(reference, candidate, media)
    media.quality(reference, candidate)[:ssim]

  -> .search(project, media, source, plan, options, directory)
    File.mkdir_p(directory)
    settings = plan["profile"]["quality"]
    low = Util.get(settings, "minimum_bitrate", 500000)
    high = Util.get(settings, "maximum_bitrate", Util.get(options, "bitrate", 8000000))
    maximum = Util.get(settings, "max_probes", 6)
    count = Util.min(Util.get(settings, "probe_frames", 24), plan["frames"])
    frames = Util.get(settings, "sample_frames", [0, Util.max(0, (plan["frames"] - count) / 2), Util.max(0, plan["frames"] - count)])
    frames.each ->(f)
      Schema.integer(f, "quality sample frame", 0, plan["frames"] - count)
    frames = Util.unique(frames)
    base = options.merge({"audio": false, "tc": false, "chapters": false, "edit_lists": false, "frames": count, "format": "mov"})
    base.delete("resume_dir")
    base.delete("quality")
    start_offset = Util.get(options, "start", 0)
    fit = Util.get(plan["profile"], "fit", "stretch")
    min_ssim = Util.get(settings, "minimum_ssim", settings.has_key?("minimum_ms_ssim") ? ~0.0 : ~0.98)
    has_ms = settings.has_key?("minimum_ms_ssim")
    min_ms_ssim = Util.get(settings, "minimum_ms_ssim", ~0.0)
    burned_text = plan["profile"]["text"]["enabled"] && plan["profile"]["text"]["burned"]
    rates = []
    i = 0
    while i < maximum
      rates.push(maximum == 1 ? high : Math.round(low * Math.pow(high / low.to_f, i / (maximum - 1).to_f)).to_i)
      i += 1
    rates = Util.unique(rates)
    trials_by_rate = {}
    eval_rate = ->(bits)
      return trials_by_rate[bits] if trials_by_rate.has_key?(bits)
      checks = []
      passed = true
      si = 0
      while si < frames.size && passed
        frame = frames[si]
        path = directory + "/" + bits.to_s + "-" + si.to_s + ".mov"
        opts = base.merge({"start": start_offset + frame, "bitrate": bits})
        media.request("transcode", source, opts, nil, path)
        q = media.quality(source, path, ref_start: start_offset + frame, cand_start: 0, frames: count, fit: fit, rate: plan["rate"])
        ssim = q[:ssim]
        ms_ssim = q[:ms_ssim]
        ok = ssim >= min_ssim && (!has_ms || ms_ssim >= min_ms_ssim)
        score = {"frame": frame, "ssim": ssim, "min_ssim": q[:min_ssim], "ms_ssim": ms_ssim, "min_ms_ssim": q[:min_ms_ssim], "psnr_y": q[:psnr_y], "ok": ok}
        if ok && burned_text
          local = plan.merge({"start": start_offset + frame, "frames": count})
          cues = [{"start": 0, "end": count * plan["rate"][1] / plan["rate"][0].to_f, "text": "probe"}]
          score["text"] = Pixels.encoded_text(path, source, cues, plan["profile"]["text"], local, media)
          score["ok"] = score["ok"] && score["text"]["ok"]
        Util.unlink(path)
        checks.push(score)
        passed = false if !score["ok"]
        si += 1
      trial = {"bitrate": bits, "ok": passed, "samples": checks}
      trials_by_rate[bits] = trial
      trial
    winner = nil
    lo = 0
    hi = rates.size - 1
    while lo <= hi
      mid = (lo + hi) / 2
      bits = rates[mid]
      trial = eval_rate.call(bits)
      if trial["ok"]
        winner = bits
        hi = mid - 1
      else
        lo = mid + 1
    trials = (trials_by_rate.keys.sort).map ->(b) trials_by_rate[b]
    result = {"ok": winner != nil, "bitrate": winner, "trials": trials, "selection": "lowest tested passing bitrate; final-file QC still required"}
    Util.json(directory + "/quality.json", result)
    raise "no tested bitrate passed quality thresholds" if winner == nil
    result
