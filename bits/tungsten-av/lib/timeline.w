in Av

+ Timeline
  -> .source(project, media, plan, job, snapshots, identity)
    planner = Planner.new(project, media)
    info = planner.timeline_inputs
    document = info["document"]
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
    recipe = Crypto.sha256(JSON.encode([document, identity, records.map ->(r) [r["source"], r["sha256"]]]))
    directory = project.workspace + "/timelines/" + recipe
    File.mkdir_p(directory)
    episode = directory + "/episode.json"
    Util.json(episode, document)
    environment = {"TW_RATE_NUM": settings["rate"][0].to_s, "TW_RATE_DEN": settings["rate"][1].to_s, "TW_WIDTH": settings["w"].to_s, "TW_HEIGHT": settings["h"].to_s, "STUDIO_TUNGSTEN": project.toolchain + "/bin/tungsten", "STUDIO_IMPLEMENTATION_ID": identity, "STUDIO_ENCODER": "videotoolbox"}
    studio = ->(args)
      command = [project.toolchain + "/bin/tungsten", project.toolchain + "/apps/studio/studio.w", "--", args[0], episode, "--cut", cut]
      args.slice(1, args.size).each ->(a)
        command.push(a.to_s)
      media.runner.run(command, project.root, environment, job + "/studio-" + args[0] + ".log")
    studio.call(["resolve"])
    resolved = JSON.parse(File.read(directory + "/build/" + cut + "/timeline.resolved.json"))
    resolved["av_episode"] = episode
    primary = plan["profiles"][name]
    budget = Budget.new(project.resources).choose(primary["width"], primary["height"])
    studio.call(["render", "--jobs", budget["jobs"], "--animation-jobs", budget["animation_jobs"], "--max-frames", resolved["frames"]])
    if project.settings["mix"]
      target = directory + "/build/" + cut + "/mix.wav"
      raise "insufficient disk for timeline audio preparation" if !Budget.new(project.resources).disk(target, resolved["samples"] * 6)["ok"]
      media.ffmpeg(["-v", "error", "-y", "-i", mapping[project.path(project.settings["mix"])], "-ar", "48000", "-ac", "2", "-af", "apad,atrim=end_sample=" + resolved["samples"].to_s, "-c:a", "pcm_s24le", "-rf64", "auto", target])
    else
      studio.call(["mix"])
    picture = directory + "/picture.mov"
    manifest = directory + "/picture.json"
    reusable = File.file?(picture) && File.file?(manifest) && JSON.parse(File.read(manifest))["sha256"] == Util.sha(picture)
    studio.call(["mux", "--out", picture, "--no-edit-lists", "--audio-codec", "pcm"]) if !reusable
    sealed = snapshots.seal(picture)
    Util.json(manifest, {"sha256": sealed["sha256"], "frames": resolved["frames"], "rate": resolved["rate"]})
    {"source": sealed["path"], "records": records, "mapping": mapping, "timeline": resolved}
