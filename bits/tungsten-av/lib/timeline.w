in Av

+ Timeline
  -> .studio_identity(toolchain)
    entries = []
    cached = Inputs.last_entries(toolchain)
    if cached != nil
      cached.each ->(pair)
        rel = pair[0]
        if rel == "bin/tungsten" || rel == "bin/tungsten-compiler" || rel.starts_with?("runtime/") || rel.starts_with?("core/") || rel.starts_with?("apps/studio/")
          entries.push(pair)
    else
      paths = [toolchain + "/bin/tungsten", toolchain + "/bin/tungsten-compiler"]
      ["runtime", "core", "apps/studio"].each ->(tree)
        File.walk(toolchain + "/" + tree, ->(path)
          paths.push(path) if [".w", ".c", ".m", ".h"].include?(File.extname(path)) && File.file?(path)
        )
      Util.unique(paths).each ->(path)
        entries.push([path.slice(toolchain.size + 1, path.size), Util.sha_cached(path)])
    Crypto.sha256(JSON.encode([entries, Env.get("TUNGSTEN_FREE") || "", Env.get("TUNGSTEN_DEFINES") || ""]))

  -> .cached_binary(toolchain, runner, name, entry_rel, log = nil)
    cache_base = Env.get("TUNGSTEN_CACHE_DIR")
    if cache_base == nil || cache_base == ""
      thome = Env.get("TUNGSTEN_HOME")
      thome = (Env.get("HOME") || "/tmp") + "/.tungsten" if thome == nil || thome == ""
      cache_base = thome + "/build/compile"
    studio_dir = cache_base + "/av-studio-" + studio_identity(toolchain)
    bin_path = studio_dir + "/" + name
    if !File.file?(bin_path)
      File.mkdir_p(studio_dir)
      part = bin_path + "." + Util.id() + ".part"
      runner.run([toolchain + "/bin/tungsten", "-o", part, toolchain + "/" + entry_rel], toolchain, {"TUNGSTEN_ROOT": toolchain}, log)
      File.atomic_replace(part, bin_path)
    bin_path

  -> .source(project, media, plan, job, snapshots, identity)
    tl_path = project.path(project.settings["timeline"])
    cached_in = plan["timeline_inputs"]
    info = cached_in != nil && cached_in["path"] == tl_path ? cached_in : Planner.new(project, media).timeline_inputs(tl_path)
    root = info["root"]
    paths = info["paths"].dup
    paths.push(project.file)
    ["chapters", "gate", "subtitles"].each ->(kind)
      project.declarations[kind].each ->(item)
        paths.push(project.path(item["name"]))
    plan["profiles"].values.each ->(p)
      paths.push(project.path(p["profile"]["text"]["font"])) if p["profile"]["text"]["font"]
      paths.push(project.path(p["profile"]["audio"]["source"])) if p["profile"]["audio"]["source"]
    project.declarations["input"].each ->(item)
      paths.push(project.path(Util.get(item, "path", item["name"])))
    paths.push(project.path(project.settings["mix"])) if project.settings["mix"]
    frozen = snapshots.tree(paths, root, project.workspace + "/trees")
    mapping = frozen["mapping"]
    records = frozen["records"]
    Pipeline.validate_documents(plan, records)
    original = project.path(project.settings["timeline"])
    document = JSON.parse(File.read(mapping[original]))
    raise "timeline asset root changed while freezing" if Util.canonical(Util.absolute(Util.get(document, "root", "."), File.dirname(original))) != root
    document["root"] = frozen["root"]
    document["title"] = project.settings["title"] if project.settings["title"]
    Util.get(document, "assets", {}).values.each ->(asset)
      path = Util.canonical(Util.absolute(asset["path"], root))
      if File.directory?(path)
        children = mapping.keys.select ->(key) File.dirname(key) == path
        raise "empty frame directory [path]" if children.size == 0
        asset["path"] = File.dirname(mapping[children[0]])
      else
        asset["path"] = mapping[path]
    programs = Util.get(document, "programs", {}).values.dup
    sections = [document]
    Util.get(document, "cuts", {}).values.each ->(s)
      sections.push(s)
    sections.each ->(section)
      Util.get(section, "shots", []).each ->(shot)
        programs.push(shot["program"]) if shot["kind"] == "program"
    programs.each ->(program)
      program["source"] = mapping[Util.canonical(Util.absolute(program["source"], root))]
      program["data"] = Util.get(program, "data", []).map ->(entry) mapping[Util.canonical(Util.absolute(type(entry) == "String" ? entry : entry["path"], root))]
    cut = Util.get(project.settings, "cut", "full")
    settings = document["cuts"][cut]
    settings["encoder"] = {"codec": "prores422hq", "quality": 1}
    name = plan["profiles"].keys[0]
    subtitles = project.associated("subtitles", name).select ->(s) s["mode"] == "timeline"
    if subtitles.size > 0
      cues = Text.captions(mapping[project.path(subtitles[0]["name"])])
      text = plan["profiles"][name]["profile"]["text"]
      raise "timeline subtitles require an explicit font" if !text["font"]
      font = mapping[project.path(text["font"])]
      document["burned_captions"] = Text.outlines(cues, text, settings["w"], settings["h"], font)
    recipe = Crypto.sha256(Util.canonical_json([document, identity, records.map ->(r) [r["source"], r["sha256"]]]))
    directory = project.workspace + "/timelines/" + recipe
    File.mkdir_p(directory)
    episode = directory + "/episode.json"
    Util.json(episode, document)
    studio_bin = cached_binary(project.toolchain, media.runner, "studio", "apps/studio/studio.w", job + "/studio-compile.log")
    environment = {"TW_RATE_NUM": settings["rate"][0].to_s, "TW_RATE_DEN": settings["rate"][1].to_s, "TW_WIDTH": settings["w"].to_s, "TW_HEIGHT": settings["h"].to_s, "TUNGSTEN_ROOT": project.toolchain, "STUDIO_TUNGSTEN": project.toolchain + "/bin/tungsten", "STUDIO_BIN": studio_bin, "STUDIO_IMPLEMENTATION_ID": identity, "STUDIO_ENCODER": "videotoolbox"}
    studio = ->(args)
      command = [studio_bin, args[0], episode, "--cut", cut]
      args.slice(1, args.size).each ->(a)
        command.push(a.to_s)
      media.runner.run(command, project.root, environment, job + "/studio-" + args[0] + ".log")
    primary = plan["profiles"][name]
    budget = Budget.new(project.resources).choose(primary["width"], primary["height"])
    max_frames = plan["timeline"] != nil ? plan["timeline"]["frames"] : 1000000000
    if project.settings["mix"]
      studio.call(["render", "--jobs", budget["jobs"], "--animation-jobs", budget["animation_jobs"], "--max-frames", max_frames, "--write-captions"])
      resolved = JSON.parse(File.read(directory + "/build/" + cut + "/timeline.resolved.json"))
      resolved["av_episode"] = episode
      mix_target = directory + "/build/" + cut + "/mix.wav"
      raise "insufficient disk for timeline audio preparation" if !Budget.new(project.resources).disk(mix_target, resolved["samples"] * 6)["ok"]
      media.prepare_audio(mapping[project.path(project.settings["mix"])], mix_target, sample_rate: 48000, channels: 2, samples: resolved["samples"])
    else
      studio.call(["render", "--jobs", budget["jobs"], "--animation-jobs", budget["animation_jobs"], "--max-frames", max_frames, "--write-captions", "--also-mix"])
      resolved = JSON.parse(File.read(directory + "/build/" + cut + "/timeline.resolved.json"))
      resolved["av_episode"] = episode
      mix_target = directory + "/build/" + cut + "/mix.wav"
    if Env.get("AV_MATERIALIZE_TIMELINE_MOV") == "1"
      picture = directory + "/picture.mov"
      manifest = directory + "/picture.json"
      reusable = File.file?(picture) && File.file?(manifest) && JSON.parse(File.read(manifest))["sha256"] == Util.sha(picture)
      studio.call(["mux", "--out", picture, "--no-edit-lists", "--audio-codec", "pcm"]) if !reusable
      sealed = snapshots.seal(picture)
      Util.json(manifest, {"sha256": sealed["sha256"], "frames": resolved["frames"], "rate": resolved["rate"]})
      return {"source": sealed["path"], "records": records, "mapping": mapping, "timeline": resolved}
    seg_paths = []
    resolved["segments"].each ->(seg)
      sp = directory + "/build/segments/" + seg["key"] + ".prores422hq"
      raise "missing rendered timeline segment [sp]" if !File.file?(sp)
      seg_paths.push(sp)
    sealed_mix = snapshots.seal(mix_target)
    {"source": seg_paths, "audio_source": sealed_mix["path"], "source_hash": recipe, "records": records, "mapping": mapping, "timeline": resolved}
