in Av

+ QC
  -> .source_gates(gates)
    reports = []
    gates.each ->(gate)
      path = gate["path"]
      raise "source gate report exceeds 16 MiB" if File.stat(path).size > 16777216
      match = Regex.new(gate["pattern"]).match_data(File.read(path))
      equal = gate["equal"]
      ok = match != nil
      if ok && equal != nil
        raise "gate capture index outside pattern" if equal[0] >= match.size || equal[1] >= match.size
        ok = match[equal[0]] == match[equal[1]]
      reports.push({"file": path, "sha256": Util.sha(path), "pattern": gate["pattern"], "ok": ok})
    {"ok": Util.all(reports.map ->(r) r["ok"]), "reports": reports}

  -> .audio(path, settings, media, directory)
    meter_result = media.ffmpeg(["-v", "info", "-i", path, "-map", "0:a:0", "-af", "loudnorm=I=-23:TP=-1:LRA=7:print_format=json", "-f", "null", "-"])
    log = meter_result["stderr"]
    position = log.index("{\n\t\"input_i\"")
    raise "audio meter returned no measurements" if position == nil
    tail = log.slice(position, log.size)
    meter = JSON.parse(tail.slice(0, tail.index("}") + 1))
    integrated = meter["input_i"].to_f
    peak = meter["input_tp"].to_f
    probe = media.probe(path)
    stream = probe["streams"].select ->(s) s["codec_type"] == "audio"
    raise "audio QC source has no audio" if stream.size != 1
    channels = stream[0]["channels"]
    sr = stream[0]["sample_rate"].to_i
    raw = directory + "/audio.f32"
    begin
      media.ffmpeg(["-v", "error", "-y", "-i", path, "-map", "0:a:0", "-c:a", "pcm_f32le", "-f", "f32le", raw])
      stats = ccall("w_av_pcm_stats", raw, channels, Math.pow(10, Util.get(settings, "silence_threshold", -60) / ~20.0))
    ensure
      Util.unlink(raw)
    frames = stats[0]
    difference = ~0.0
    if channels > 1 && Util.max(stats[3], stats[4]) > 0
      difference = 10 * Math.log10(Util.max(stats[3], stats[4]) / Util.max(Util.min(stats[3], stats[4]), ~1e-24))
    checks = {"loudness": !integrated.nan? && !integrated.infinite? && (integrated - Util.get(settings, "target", -16)).abs <= Util.get(settings, "tolerance", 1), "true_peak": !peak.nan? && !peak.infinite? && peak <= Util.get(settings, "true_peak", -1), "clipped_samples": stats[1] <= Util.get(settings, "max_clipped_samples", 0), "silence": stats[2] / sr.to_f <= Util.get(settings, "max_silence", 10), "channel_balance": difference <= Util.get(settings, "max_channel_difference", 6)}
    {"ok": Util.all(checks.values), "checks": checks, "integrated_lufs": integrated.infinite? ? nil : integrated, "true_peak_dbtp": peak.infinite? ? nil : peak, "clipped_samples": stats[1], "longest_silence_seconds": stats[2] / sr.to_f, "channel_difference_db": difference, "decoded_frames": frames, "sample_rate": sr, "channels": channels}

  -> .uncovered(start, finish, allowed)
    remaining = [[start, finish]]
    allowed.each ->(range)
      next_ranges = []
      remaining.each ->(r)
        a = [r[0], Util.min(r[1], range[0])]
        b = [Util.max(r[0], range[1]), r[1]]
        next_ranges.push(a) if a[1] > a[0]
        next_ranges.push(b) if b[1] > b[0]
      remaining = next_ranges
    remaining

  -> .anomalies(path, settings, media, plan, timeline = nil)
    black = Util.get(settings, "black_min", 1)
    freeze = Util.get(settings, "freeze_min", 3)
    noise = Util.get(settings, "noise", ~0.001)
    result = media.ffmpeg(["-v", "info", "-xerror", "-i", path, "-an", "-vf", "scale=320:-2,blackdetect=d=[black]:pix_th=0.10,freezedetect=n=[noise]:d=[freeze]", "-f", "null", "-"])
    duration = plan["frames"] * plan["rate"][1] / plan["rate"][0].to_f
    events = []
    starts = []
    result["stderr"].split("\n").each ->(line)
      m = Regex.new("black_start:(\[0-9.]+) black_end:(\[0-9.]+)").match_data(line)
      events.push({"kind": "black", "start": m[1].to_f, "end": m[2].to_f}) if m != nil
      m = Regex.new("freeze_(start|end):\\s*(\[0-9.]+)").match_data(line)
      if m != nil
        if m[1] == "start"
          starts.push(m[2].to_f)
        elsif starts.size > 0
          events.push({"kind": "freeze", "start": starts.shift, "end": m[2].to_f})
    starts.each ->(start)
      events.push({"kind": "freeze", "start": start, "end": duration})
    allowed = {"black": Util.get(settings, "allow_black", []).dup, "freeze": Util.get(settings, "allow_freeze", []).dup}
    if timeline != nil
      fps = plan["rate"][0] / plan["rate"][1].to_f
      offset = plan["start"] / fps
      timeline["tracks"][0]["items"].each ->(item)
        lo = Util.get(item, "f0", 0) / fps - offset
        hi = Util.get(item, "f1", Util.get(item, "f0", 0) + Util.get(item, "n", 0)) / fps - offset
        allowed["black"].push([lo, hi]) if item["kind"] == "black"
        allowed["freeze"].push([lo, hi]) if ["black", "still", "card"].include?(item["kind"])
    events.each ->(event)
      threshold = event["kind"] == "black" ? black : freeze
      event["unexpected"] = uncovered(event["start"], event["end"], allowed[event["kind"]]).select ->(r) r[1] - r[0] >= threshold - ~0.05
    unexpected = events.select ->(e) e["unexpected"].size > 0
    {"ok": unexpected.size == 0 || Util.get(settings, "policy", "fail") == "report", "events": events, "unexpected": unexpected.size, "decoded_entire_video": true, "scope": "320-pixel detection; all output pictures decoded"}

  -> .run(project, media, path, plan, directory, reference = nil, timeline = nil, subtitles = nil)
    File.mkdir_p(directory)
    before = Util.sha(path)
    p = plan["profile"]
    results = {}
    results["source_gates"] = source_gates(plan["gates"]) if plan["gates"].size > 0
    if p["loudness"]["enabled"]
      disk = Budget.new(project.resources).disk(directory, plan["samples"] * p["audio"]["channels"] * 4)
      raise "insufficient disk for decoded audio QC" if !disk["ok"]
      results["audio"] = audio(path, p["loudness"], media, directory)
    if p["text"]["enabled"]
      paths = subtitles || project.associated("subtitles", p["name"]).map ->(i) project.path(i["name"])
      cues = []
      paths.each ->(file)
        Text.captions(file).each ->(cue)
          cues.push(cue)
      raise "text QC needs nonempty subtitles" if cues.size == 0
      results["text_layout"] = Text.layout(cues, p["text"], plan["width"], plan["height"], project.path(p["text"]["font"]))
      if p["text"]["burned"]
        raise "burned text QC requires a reference source" if reference == nil
        results["encoded_text"] = Pixels.encoded_text(path, reference, cues, p["text"], plan, media)
    results["anomalies"] = anomalies(path, p["anomalies"], media, plan, timeline) if p["anomalies"]["enabled"]
    results["banding"] = Banding.run(project, media, path, plan, directory, timeline) if p["banding"].size > 0
    raise "output changed during QC" if Util.sha(path) != before
    result = {"ok": Util.all(results.values.map ->(r) r["ok"]), "sha256": before, "checks": results}
    Util.json(directory + "/qc.json", result)
    result
