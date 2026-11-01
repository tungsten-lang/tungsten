in Av

+ Planner
  -> new(@project, @media)

  -> .selected(profiles, names)
    return profiles if names == nil || names.size == 0
    wanted = {}
    names.each ->(name)
      raise "unknown profile [name]" if !profiles.has_key?(name)
      current = name
      while current != nil
        wanted[current] = true
        current = profiles[current]["from"]
    result = {}
    profiles.keys.each ->(name)
      result[name] = profiles[name] if wanted.has_key?(name)
    result

  -> .video_stream(probe)
    streams = probe["streams"].select ->(s) s["codec_type"] == "video" && !Util.get(Util.get(s, "disposition", {}), "attached_pic", 0)
    # FFprobe uses integer zero for false, which remains truthy in Tungsten.
    streams = probe["streams"].select ->(s) s["codec_type"] == "video" && Util.get(Util.get(s, "disposition", {}), "attached_pic", 0) == 0
    raise "source requires one video stream" if streams.size == 0
    streams[0]

  -> .colour_guard(probe, contract)
    video = video_stream(probe)
    expected = {"color_primaries": "bt709", "color_transfer": "bt709", "color_space": "bt709", "color_range": "tv"}
    missing = []
    expected.keys.each ->(key)
      actual = video[key]
      if actual == nil || actual == "unknown" || actual == "unspecified"
        missing.push(key)
      elsif actual != expected[key]
        raise "source colour [key]=[actual] conflicts with BT.709 limited SDR"
    raise "source is untagged; explicitly configure untagged: :bt709" if missing.size > 0 && contract["untagged"] != "bt709"
    {"contract": contract, "source": video["codec_name"], "assumed": missing}

  -> timeline_inputs(path = nil)
    path = path || @project.path(@project.settings["timeline"])
    document = JSON.parse(File.read(path))
    root = Util.canonical(Util.absolute(Util.get(document, "root", "."), File.dirname(path)))
    paths = [path]
    Util.get(document, "assets", {}).values.each ->(asset)
      paths.push(Util.absolute(asset["path"], root))
    programs = Util.get(document, "programs", {}).values.dup
    sections = [document]
    Util.get(document, "cuts", {}).values.each ->(s)
      sections.push(s)
    sections.each ->(section)
      Util.get(section, "shots", []).each ->(shot)
        programs.push(shot["program"]) if shot["kind"] == "program"
    programs.each ->(program)
      paths.push(Util.absolute(program["source"], root))
      Util.get(program, "data", []).each ->(entry)
        paths.push(Util.absolute(type(entry) == "String" ? entry : entry["path"], root))
    {"document": document, "root": root, "paths": paths}

  -> resolve_timeline(path = nil, cut = nil)
    path = path || @project.path(@project.settings["timeline"])
    cut = cut || Util.get(@project.settings, "cut", "full")
    @media.runner.json([@media.toolchain + "/bin/tungsten", @media.toolchain + "/apps/studio/tools/av_plan.w", "--", path, cut])

  -> chapters(name, rate, frames)
    declarations = @project.associated("chapters", name)
    return nil if declarations.size == 0
    raise "only one chapter file per profile is supported" if declarations.size > 1
    entry = declarations[0]
    path = @project.path(entry["name"])
    format = Util.get(entry, "format", File.extname(path) == ".json" ? "json" : "text")
    result = []
    if format == "json"
      JSON.parse(File.read(path)).each ->(item)
        if type(item) == "Array"
          raise "chapter pair requires title/frame" if item.size != 2
          result.push(item)
        else
          frame = item["frame"]
          frame = Math.floor(item["seconds"] * rate[0] / rate[1].to_f + ~0.5).to_i if frame == nil
          result.push([item["title"], frame])
    elsif format == "text"
      File.read(path).split("\n").each ->(line)
        if line.strip != ""
          space = line.index(" ")
          raise "chapter line needs time and title" if space == nil
          seconds = ~0.0
          line.slice(0, space).split(":").each ->(part)
            seconds = seconds * 60 + part.to_f
          result.push([line.slice(space + 1, line.size).strip, Math.floor(seconds * rate[0] / rate[1].to_f + ~0.5).to_i])
    else
      raise "chapters format must be json or text"
    previous = -1
    result.each ->(item)
      raise "chapter frames must increase within output" if type(item[0]) != "String" || item[0] == "" || type(item[1]) != "Int" || item[1] <= previous || item[1] >= frames
      previous = item[1]
    result

  -> timeline_facts(timeline)
    chapters = timeline["tracks"][5]["items"].map ->(c) [c["title"], c["frame"]]
    {"width": timeline["w"], "height": timeline["h"], "rate": timeline["rate"], "frames": timeline["frames"], "tc_label": timeline["tc_start"], "chapters": chapters, "has_audio": true}

  -> build(names = nil, require_space = true)
    project = @project
    raise "Bitfile changed after parsing; run again" if Util.sha(project.file) != project.content_sha256
    profiles = Planner.selected(project.profiles, names)
    caps = @media.capabilities
    raise "native AV requires macOS VideoToolbox" if !caps["available"]
    @media.runner.run(["ffmpeg", "-version"])
    @media.runner.run(["ffprobe", "-version"])
    if (profiles.values.select ->(p) p["quality"].has_key?("minimum_vmaf")).size > 0
      filters = @media.runner.run(["ffmpeg", "-hide_banner", "-filters"])["stdout"]
      raise "minimum_vmaf requires an FFmpeg build with libvmaf" if !filters.include?("libvmaf")
    inputs = [project.file]
    source = nil
    timeline = nil
    probe = nil
    facts = {}
    if project.settings["source"]
      source = project.path(project.settings["source"])
      raise "missing source: [source]" if !File.file?(source)
      facts = @media.facts(source)
      probe = @media.probe(source)
      facts["has_audio"] = (probe["streams"].select ->(s) s["codec_type"] == "audio").size > 0
      inputs.push(source)
    else
      info = timeline_inputs()
      info["paths"].each ->(p)
        inputs.push(p)
      timeline = resolve_timeline()
      cut = info["document"]["cuts"][Util.get(project.settings, "cut", "full")]
      raise "timeline colour must be bt709" if Util.get(cut, "colour", "bt709") != "bt709"
      facts = timeline_facts(timeline)
      inputs.push(project.path(project.settings["mix"])) if project.settings["mix"]
      if project.settings["scene_rate"] && project.settings["scene_rate"] != facts["rate"] && project.settings["generator_clock"] != "env-v1"
        raise "scene_rate differs from cut; declare env-v1 generator clock or update generator"
    project.declarations["input"].each ->(i)
      path = project.path(Util.get(i, "path", i["name"]))
      inputs.push(path) if !i["generated"] || File.exist?(path)
    ["subtitles", "chapters", "gate"].each ->(kind)
      project.declarations[kind].each ->(i)
        inputs.push(project.path(i["name"]))
    profiles.values.each ->(p)
      inputs.push(project.path(p["text"]["font"])) if p["text"]["font"]
      inputs.push(project.path(p["audio"]["source"])) if p["audio"]["source"]
      inputs.push(project.path(p["banding"]["background"])) if p["banding"]["background"]
      Util.get(p["banding"], "samples", []).each ->(s)
        ["source", "next_source"].each ->(key)
          inputs.push(project.path(s[key])) if s[key]
    estimated = timeline == nil ? 0 : timeline["w"] * timeline["h"] * timeline["frames"] * ~1.5
    budget = Budget.new(project.resources)
    plans = {}
    profiles.keys.each ->(name)
      p = profiles[name]
      parent = plans[p["from"]]
      base = parent || facts
      alternate = nil
      if p["timeline"]
        path = project.path(p["timeline"])
        info = timeline_inputs(path)
        alternate_cut = info["document"]["cuts"][Util.get(p, "cut", "full")]
        raise "timeline colour must be bt709" if Util.get(alternate_cut, "colour", "bt709") != "bt709"
        info["paths"].each ->(v)
          inputs.push(v)
        alternate = resolve_timeline(path, Util.get(p, "cut", "full"))
        base = timeline_facts(alternate)
        estimated += alternate["w"] * alternate["h"] * alternate["frames"] * ~1.5
        inputs.push(project.path(p["mix"])) if p["mix"]
      raise "per-output source overrides are unsupported; use project source and output from" if p["source"]
      v = p["video"]
      a = p["audio"]
      raise "unavailable codec [v["codec"]]" if !caps["codecs"].include?(v["codec"])
      backend = Util.get(v, "backend", "auto")
      raise "unavailable scaler backend [backend]" if backend != "auto" && !caps["backends"].include?(backend)
      width = Util.get(p, "width", base["width"])
      height = Util.get(p, "height", base["height"])
      rate = Util.get(p, "rate", base["rate"])
      raise "output rate must match source/cut" if rate != base["rate"]
      start = Util.get(p, "start_frame", 0)
      frames = Util.get(p, "frames", base["frames"] - start)
      raise "output frame range outside source" if start + frames > base["frames"] || frames <= 0
      raise "output dimensions must be even" if width % 2 != 0 || height % 2 != 0
      if a["codec"] != "none"
        raise "audio copy requires complete source from frame zero" if a["codec"] == "copy" && (start != 0 || frames != base["frames"] || a["source"])
        if a["source"]
          audio_probe = @media.probe(project.path(a["source"]))
          raise "external source has no audio track" if (audio_probe["streams"].select ->(s) s["codec_type"] == "audio").size == 0
        elsif !Util.get(base, "has_audio", true)
          raise "profile [name] requires audio; declare source or codec none"
      sample_numerator = frames * rate[1] * a["sample_rate"]
      raise "duration must be exact audio samples" if a["codec"] != "none" && sample_numerator % rate[0] != 0
      contract = source != nil && parent == nil ? Planner.colour_guard(probe, p["colour"]) : {"contract": p["colour"], "source": "timeline or parent profile", "assumed": []}
      gates = project.associated("gate", name).map ->(i) i.merge({"path": project.path(i["name"])})
      raise "source correctness gate failed for [name]" if !QC.source_gates(gates)["ok"]
      subtitles = project.associated("subtitles", name)
      raise "choose one burned subtitle language" if (subtitles.select ->(s) s["mode"] == "timeline").size > 1
      cues = []
      subtitles.each ->(s)
        Text.captions(project.path(s["name"])).each ->(c)
          raise "subtitle extends beyond output duration" if c["end"] > frames * rate[1] / rate[0].to_f + ~0.001
          cues.push(c)
      if cues.size > 0 && (p["text"]["enabled"] || (subtitles.select ->(s) s["mode"] == "timeline").size > 0)
        raise "text captions require explicit font" if !p["text"]["font"]
        raise "caption layout fails for [name]" if !Text.layout(cues, p["text"], width, height, project.path(p["text"]["font"]))["ok"]
      chapter_list = chapters(name, rate, frames)
      if chapter_list == nil
        chapter_list = []
        Util.get(base, "chapters", []).each ->(c)
          frame = c[1] - start
          if frame <= 0
            chapter_list = [[c[0], 0]]
          elsif frame < frames
            chapter_list.push([c[0], frame])
      queue = budget.choose(width, height, base["width"], base["height"])
      @media.call("encoder", [width, height, JSON.encode(v.merge({"rate": rate}))])
      bits = Util.get(v, "bitrate", width * height * rate[0] / rate[1].to_f * (v["codec"].starts_with?("prores") ? 8 : ~0.35))
      samples = sample_numerator / rate[0]
      size = (bits * frames * rate[1] / rate[0].to_f / 8 + samples * a["channels"] * 4).to_i
      estimated += size * 3
      timecode = Util.get(project.settings, "timecode", Util.get(base, "tc_label", base["timecode"]))
      timecode = nil if timecode == false
      if timecode && start > 0 && !project.settings.has_key?("timecode")
        timecode = @media.call("timecode", [timecode, JSON.encode(rate), start])
      plans[name] = {"gates": gates, "has_audio": a["codec"] != "none", "timeline": alternate, "timecode": timecode, "profile": p, "width": width, "height": height, "rate": rate, "frames": frames, "start": start, "samples": samples, "chapters": chapter_list, "colour": contract, "resources": queue, "estimated_bytes": size}
    inputs = Util.unique(inputs)
    inputs.each ->(path)
      raise "missing input: [path]" if !File.exist?(path)
    disk = budget.disk(project.workspace, estimated)
    raise "insufficient disk space for estimated job and reserve" if !disk["ok"] && require_space
    documents = {}
    inputs.each ->(path)
      documents[path] = Util.sha(path) if File.file?(path) && (path == project.file || [".json", ".srt", ".txt"].include?(File.extname(path).downcase))
    {"ready": disk["ok"], "schema": 1, "project": project.name, "root": project.root, "bitfile": project.file, "toolchain": project.toolchain, "capabilities": caps, "inputs": inputs, "documents": documents, "source": source, "timeline": timeline, "profiles": plans, "disk": disk, "stages": ["prepare", "snapshot", timeline == nil ? "decode source" : "render timeline", "encode profiles", "verify candidates", "audio/text/anomaly/banding QC", "activate verified release"]}
