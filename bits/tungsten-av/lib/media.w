in Av

+ Media
  ro :toolchain, :package, :runner, :last_verify_probe
  -> new(@toolchain, @package, @runner)
    @caps = nil
    @encoder_checks = {}
    @last_verify_probe = nil

  -> .json_keys(value)
    JSON.parse(JSON.encode(value))

  -> capabilities
    return @caps if @caps != nil
    available = VideoEncoder.available?
    codecs = []
    backends = []
    identity = nil
    if available
      codecs = VideoEncoder.codecs
      backends = Scaler.backends
      identity = ccall("w_media_runtime_identity")
    @caps = {"available": available, "codecs": codecs, "backends": backends, "implementation": identity}
    @caps

  -> facts(path)
    f = Transcode.source_facts(path)
    info = f[:facts]
    chapters = []
    if f[:chapters] != nil
      f[:chapters].each ->(c)
        chapters.push([c[0], c[1]])
    {"width": info[:width], "height": info[:height], "rate": f[:rate], "frames": f[:frames], "tc": f[:tc], "tc_label": f[:tc] == nil ? nil : Timecode.to_smpte(f[:tc], f[:rate], f[:drop]), "drop": f[:drop], "chapters": chapters, "codec": info[:codec], "bit_depth": info[:bit_depth], "audio_rate": info[:audio_rate], "audio_channels": info[:audio_channels]}

  -> probe(path)
    MediaVerify.probe_streams(path)

  -> audio_qc(path, silence_db = -60)
    MediaVerify.audio_qc(path, silence_db)

  -> prepare_audio(src, dst, opts = {})
    MediaVerify.prepare_audio(src, dst, opts)

  -> anomalies(src, opts = {})
    MediaVerify.anomalies(src, opts)

  -> quality(ref_src, cand_src, opts = {})
    MediaVerify.quality(ref_src, cand_src, opts)

  -> extract_frames(src, frames, opts = {})
    MediaVerify.extract_frames(src, frames, opts)

  -> quality_search(src, rates, spec)
    MediaVerify.quality_search(src, rates, spec)

  -> video_scan(src, opts, reqs)
    MediaVerify.video_scan(src, opts, reqs)

  -> call(command, args = [])
    return capabilities() if command == "capabilities"
    return facts(args[0].to_s) if command == "facts"
    if command == "encoder"
      w = args[0].to_i
      h = args[1].to_i
      raw = type(args[2]) == "String" ? args[2] : JSON.encode(args[2])
      key = w.to_s + "x" + h.to_s + ":" + raw
      return {"ok": true} if @encoder_checks.has_key?(key)
      options = type(args[2]) == "Hash" ? args[2] : JSON.parse(raw)
      encoder = VideoEncoder.new(w, h, Util.symbols(options))
      encoder.close
      @encoder_checks[key] = true
      return {"ok": true}
    if command == "timecode"
      label = args[0].to_s
      r = type(args[1]) == "Array" ? args[1] : JSON.parse(args[1].to_s)
      frame = Timecode.parse(label, r) + args[2].to_i
      return Timecode.to_smpte(frame, r, label.include?(";"))
    if command == "segment"
      segment = VideoSegment.load(args[0].to_s)
      out = {"frames": segment.frames, "width": segment.width, "height": segment.height}
      segment.release
      return out
    raise "unknown native AV command: [command]"

  -> request(command, path, options, directory, destination = nil, extra = nil)
    if directory != nil
      File.mkdir_p(directory)
      Util.json(directory + "/" + command + ".json", {"source": path, "destination": destination, "options": options})
    opts = Util.symbols(options)
    if extra != nil
      ex = Util.symbols(extra)
      ex.keys.each ->(k)
        opts[k] = ex[k]
    if command == "transcode"
      result = Transcode.run(path, destination, opts)
      return Media.json_keys(result)
    if command == "verify"
      result = Transcode.check(path, opts)
      @last_verify_probe = MediaVerify.probe_from_facts(result[:facts])
      out = Media.json_keys({"ok": result[:ok], "checks": result[:checks]})
      raise "native media verification failed for [path]" if !out["ok"]
      return out
    raise "unknown native AV request: [command]"
