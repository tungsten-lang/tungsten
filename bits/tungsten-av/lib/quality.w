in Av

+ Quality
  -> .metric(reference, candidate, media, vmaf = false)
    filter = vmaf ? "libvmaf" : "ssim"
    result = media.ffmpeg(["-v", "info", "-i", candidate, "-i", reference, "-lavfi", "\[0:v]setpts=PTS-STARTPTS\[a];\[1:v]setpts=PTS-STARTPTS\[b];\[a]\[b][filter]", "-an", "-f", "null", "-"])
    match = Regex.new(vmaf ? "VMAF score:\\s*(\[0-9.]+)" : "All:(\[0-9.]+)").match_data(result["stderr"])
    raise "quality metric unavailable: [filter]" if match == nil
    match[1].to_f

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
    references = []
    i = 0
    frames.each ->(frame)
      reference = directory + "/reference-" + i.to_s + ".mov"
      opts = base.merge({"start": Util.get(options, "start", 0) + frame, "codec": "prores422hq"})
      opts.delete("bitrate")
      opts.delete("level")
      media.request("transcode", source, opts, directory, reference)
      references.push(reference)
      i += 1
    rates = []
    i = 0
    while i < maximum
      rates.push(maximum == 1 ? high : Math.round(low * Math.pow(high / low.to_f, i / (maximum - 1).to_f)).to_i)
      i += 1
    trials = []
    winner = nil
    Util.unique(rates).each ->(bits)
      if winner == nil
        checks = []
        i = 0
        frames.each ->(frame)
          path = directory + "/[bits]-[i].mov"
          opts = base.merge({"start": Util.get(options, "start", 0) + frame, "bitrate": bits})
          media.request("transcode", source, opts, directory, path)
          ssim = metric(references[i], path, media)
          score = {"frame": frame, "ssim": ssim, "ok": ssim >= Util.get(settings, "minimum_ssim", ~0.98)}
          if settings.has_key?("minimum_vmaf")
            score["vmaf"] = metric(references[i], path, media, true)
            score["ok"] = score["ok"] && score["vmaf"] >= settings["minimum_vmaf"]
          if plan["profile"]["text"]["enabled"] && plan["profile"]["text"]["burned"]
            local = plan.merge({"start": 0, "frames": count})
            cues = [{"start": 0, "end": count * plan["rate"][1] / plan["rate"][0].to_f, "text": "probe"}]
            score["text"] = Pixels.encoded_text(path, references[i], cues, plan["profile"]["text"], local, media)
            score["ok"] = score["ok"] && score["text"]["ok"]
          checks.push(score)
          i += 1
        passed = Util.all(checks.map ->(c) c["ok"])
        trials.push({"bitrate": bits, "ok": passed, "samples": checks})
        winner = bits if passed
    result = {"ok": winner != nil, "bitrate": winner, "trials": trials, "selection": "lowest tested passing bitrate; final-file QC still required"}
    Util.json(directory + "/quality.json", result)
    raise "no tested bitrate passed quality thresholds" if winner == nil
    result
