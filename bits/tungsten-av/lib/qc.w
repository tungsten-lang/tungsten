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

  -> .audio(path, settings, media, _directory = nil)
    m = media.audio_qc(path, Util.get(settings, "silence_threshold", -60))
    integrated = m[:integrated_lufs]
    peak = m[:true_peak_dbtp]
    clipped = m[:clipped_samples]
    longest = m[:longest_silence_frames]
    frames = m[:decoded_frames]
    sr = m[:sample_rate]
    channels = m[:channels]
    energy = m[:energy]
    difference = ~0.0
    if channels > 1
      e0 = energy[0]
      e1 = energy[1]
      hi = Util.max(e0, e1)
      lo = Util.min(e0, e1)
      if hi > ~0.0
        difference = ~10.0 * Math.log10(hi / Util.max(lo, ~1e-24))
    loud_ok = integrated != nil && !integrated.nan? && !integrated.infinite? && (integrated - Util.get(settings, "target", -16)).abs <= Util.get(settings, "tolerance", 1)
    tp_ok = peak != nil && !peak.nan? && !peak.infinite? && peak <= Util.get(settings, "true_peak", -1)
    checks = {"loudness": loud_ok, "true_peak": tp_ok, "clipped_samples": clipped <= Util.get(settings, "max_clipped_samples", 0), "silence": longest / sr.to_f <= Util.get(settings, "max_silence", 10), "channel_balance": difference <= Util.get(settings, "max_channel_difference", 6)}
    {"ok": Util.all(checks.values), "checks": checks, "integrated_lufs": integrated, "true_peak_dbtp": peak, "clipped_samples": clipped, "longest_silence_seconds": longest / sr.to_f, "channel_difference_db": difference, "decoded_frames": frames, "sample_rate": sr, "channels": channels}

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
    scan = media.anomalies(path, black_min: black, freeze_min: freeze, noise: noise, rate: plan["rate"])
    events = []
    scan[:events].each ->(ev)
      events.push({"kind": ev[0], "start": ev[1], "end": ev[2]})
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
      disk = Budget.new(project.resources).disk(directory, 0)
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
