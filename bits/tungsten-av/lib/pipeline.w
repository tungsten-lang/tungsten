in Av

+ Pipeline
  -> new(@project, @media)

  -> .validate_documents(plan, records)
    records.each ->(record)
      expected = plan["documents"][record["source"]]
      raise "plan input changed before snapshot: [record["source"]]" if expected && expected != record["sha256"]

  -> .freeze_profile(project, plan, mapping)
    plan["gates"].each ->(gate)
      gate["path"] = Util.get(mapping, project.path(gate["path"]), gate["path"])
    text = plan["profile"]["text"]
    text["font"] = Util.get(mapping, project.path(text["font"]), text["font"]) if text["font"]
    spec = plan["profile"]["banding"]
    if !spec["auto"]
      spec["background"] = Util.get(mapping, project.path(spec["background"]), spec["background"]) if spec["background"]
      Util.get(spec, "samples", []).each ->(sample)
        ["source", "next_source"].each ->(key)
          sample[key] = Util.get(mapping, project.path(sample[key]), sample[key]) if sample[key]

  -> options(plan, identity)
    p = plan["profile"]
    video = p["video"]
    audio = p["audio"]
    resources = plan["resources"]
    settings = @project.resources
    codec = audio["codec"] == "none" ? false : audio["codec"] == "pcm" ? "pcm_" + audio["sample_format"] : audio["codec"]
    opts = {"width": plan["width"], "height": plan["height"], "rate": plan["rate"], "start": plan["start"], "frames": plan["frames"], "format": p["format"], "fit": Util.get(p, "fit", "stretch"), "filter": Util.get(p, "filter", "lanczos3"), "codec": video["codec"], "scale_backend": Util.get(video, "backend", "auto"), "audio": codec, "edit_lists": p["edit_lists"], "faststart": Util.get(p, "faststart", true), "decode_ahead": resources["decode_ahead"], "segments_ahead": resources["segments_ahead"], "disk_reserve_bytes": (Util.get(settings, "disk_reserve_mb", 1024) * 1048576).to_i, "timeout_ms": Util.get(settings, "native_timeout_ms", 30000), "retries": Util.get(settings, "retries", 2), "implementation_id": identity, "resume_dir": @project.path(Util.get(@project.settings, "cache", ".av/cache")) + "/" + p["name"]}
    "bitrate quality level gop reorder speed crop rect".split(" ").each ->(key)
      opts[key] = video[key] if video.has_key?(key)
    opts["audio_kbps"] = audio["bitrate"] / 1000 if audio["bitrate"]
    opts["tc"] = @project.settings["timecode"] if @project.settings.has_key?("timecode")
    opts["chapters"] = plan["chapters"] if plan["chapters"] != nil
    opts

  -> verify(project, path, plan, directory, reference = nil, timeline = nil, subtitles = nil)
    File.mkdir_p(directory)
    p = plan["profile"]
    opts = {"tc_start": plan["timecode"], "width": plan["width"], "height": plan["height"], "rate": plan["rate"], "frames": plan["frames"], "codec": p["video"]["codec"], "audio": p["audio"]["codec"] != "none", "edit_lists": p["edit_lists"]}
    opts["chapters"] = plan["chapters"] if plan["chapters"] != nil
    opts["level"] = p["video"]["level"] if p["video"]["level"]
    native = @media.request("verify", path, opts, directory)
    probe = @media.probe(path)
    Planner.colour_guard(probe, p["colour"].merge({"untagged": "reject"}))
    audios = probe["streams"].select ->(s) s["codec_type"] == "audio"
    a = p["audio"]
    if a["codec"] == "none"
      audio_ok = audios.size == 0
    elsif a["codec"] == "copy"
      audio_ok = audios.size == 1
    else
      want = a["codec"] == "aac" ? "aac" : "pcm_" + a["sample_format"]
      audio_ok = audios.size == 1 && audios[0]["codec_name"] == want && audios[0]["sample_rate"].to_i == a["sample_rate"] && audios[0]["channels"] == a["channels"]
    result = QC.run(project, @media, path, plan, directory, reference, timeline, subtitles)
    result["ok"] = result["ok"] && native["ok"] && audio_ok
    result["native"] = native
    result["audio_contract"] = audio_ok
    Util.json(directory + "/verification.json", result)
    raise "verification/QC failed for [path]; see [directory]" if !result["ok"]
    result

  -> prepared_audio(project, source, plan, opts, snapshots, mapping)
    a = plan["profile"]["audio"]
    return nil if a["codec"] == "none" || a["codec"] == "copy"
    external_audio = a["source"]
    audio_source = external_audio ? Util.get(mapping, project.path(external_audio), project.path(external_audio)) : source
    streams = @media.probe(audio_source)["streams"].select ->(s) s["codec_type"] == "audio"
    raise "profile requires audio but source has none" if streams.size == 0
    stream = streams[0]
    return nil if !external_audio && stream["sample_rate"].to_i == a["sample_rate"] && stream["channels"] == a["channels"]
    key = Crypto.sha256(JSON.encode([Util.sha(audio_source), a["sample_rate"], a["channels"]]))
    output = project.workspace + "/audio/" + key + ".wav"
    File.mkdir_p(File.dirname(output))
    if !File.file?(output)
      part = output + ".part.wav"
      @media.ffmpeg(["-v", "error", "-y", "-i", audio_source, "-map", "0:a:0", "-ar", a["sample_rate"], "-ac", a["channels"], "-c:a", "pcm_s24le", part])
      File.atomic_replace(part, output)
    opts["audio_src"] = snapshots.seal(output)["path"]

  -> delivery_context(name, path)
    pinned = File.realpath(path)
    manifest_path = File.dirname(pinned) + "/manifest.json"
    return nil if !File.file?(manifest_path)
    manifest = JSON.parse(File.read(manifest_path))
    job = Util.get(manifest, "provenance", {})["job"]
    return nil if job == nil
    job = File.realpath(job)
    raise "release provenance points outside project jobs" if !Util.inside?(job, @project.workspace + "/jobs")
    state = JSON.parse(File.read(job + "/job.json"))
    output = state["outputs"][name]
    raise "release has no matching profile provenance" if output == nil
    items = manifest["files"].select ->(i) i["name"] == File.basename(pinned) && i["role"] == name
    raise "delivery differs from recorded release" if items.size != 1 || items[0]["sha256"] != output["sha256"] || Util.sha(pinned) != output["sha256"]
    mapping = {}
    Util.get(state, "inputs", []).each ->(item)
      mapping[item["source"]] = Util.get(item, "frozen", item["path"])
    {"project": @project.with_settings(Util.get(output, "project_settings", @project.settings)), "reference": output["reference"], "timeline": output["timeline"], "subtitles": output["subtitle_paths"], "mapping": mapping}

  -> render(names = nil, quality_only = false)
    lock = Util.lock(@project.workspace + "/project.lock")
    begin
      render_locked(names, quality_only)
    ensure
      Util.unlock(lock)

  -> render_locked(names, quality_only)
    project = @project
    prepare_env = {}
    if project.settings["timeline"]
      cut = JSON.parse(File.read(project.path(project.settings["timeline"])))["cuts"][Util.get(project.settings, "cut", "full")]
      prepare_env = {"TW_RATE_NUM": cut["rate"][0], "TW_RATE_DEN": cut["rate"][1], "TW_WIDTH": cut["w"], "TW_HEIGHT": cut["h"]}
    project.declarations["prepare"].each ->(hook)
      @media.runner.run(hook["argv"], project.path(Util.get(hook, "cwd", ".")), prepare_env, project.workspace + "/prepare-" + hook["name"] + ".log")
    plan = Planner.new(project, @media).build(names)
    identity = Inputs.implementation(project.toolchain, @media.package)
    job = project.workspace + "/jobs/" + Util.id()
    File.mkdir_p(job)
    state = {"schema": 1, "status": "running", "started": Util.now, "plan": plan, "implementation": identity, "outputs": {}, "quality": {}}
    Util.json(job + "/job.json", state)
    Util.json(project.workspace + "/latest.json", {"job": job})
    snapshots = Snapshots.new(project.workspace + "/inputs", (Util.get(project.resources, "disk_reserve_mb", 1024) * 1048576).to_i)
    records = []
    mapping = {}
    timeline = plan["timeline"]
    source = nil
    begin
      if plan["source"]
        sealed = snapshots.seal(plan["source"])
        source = sealed["path"]
        records.push(sealed)
        other = plan["inputs"].select ->(path) path != plan["source"]
        frozen = snapshots.tree(other, project.root, project.workspace + "/trees")
        frozen["records"].each ->(r)
          records.push(r)
        mapping = frozen["mapping"]
      else
        primary = {}
        plan["profiles"].keys.each ->(name)
          primary[name] = plan["profiles"][name] if !plan["profiles"][name]["profile"]["timeline"]
        if primary.size > 0
          frozen = Timeline.source(project, @media, plan.merge({"profiles": primary}), job, snapshots, identity["sha256"])
          source = frozen["source"]
          records = frozen["records"]
          mapping = frozen["mapping"]
          timeline = frozen["timeline"]
      Pipeline.validate_documents(plan, records)
      state["inputs"] = records
      Util.json(job + "/job.json", state)
      probe_targets = plan["profiles"].keys.select ->(n) !plan["profiles"][n]["profile"]["video"]["codec"].starts_with?("prores")
      probe_targets = names if names != nil && names.size > 0
      entries = []
      sources = {}
      references = {}
      subtitles_by_name = {}
      contexts = {}
      timelines = {}
      mappings = {}
      plan["profiles"].keys.each ->(name)
        p = plan["profiles"][name]
        parent = p["profile"]["from"]
        origin = Util.get(sources, parent, source)
        context = Util.get(contexts, parent, project)
        current_timeline = Util.get(timelines, parent, timeline)
        current_mapping = Util.get(mappings, parent, mapping)
        if p["profile"]["timeline"]
          settings = project.settings.merge({"timeline": p["profile"]["timeline"], "cut": Util.get(p["profile"], "cut", "full")})
          settings.delete("source")
          settings.delete("mix")
          settings["mix"] = p["profile"]["mix"] if p["profile"]["mix"]
          context = project.with_settings(settings)
          alternate_profiles = {}
          alternate_profiles[name] = p
          frozen = Timeline.source(context, @media, plan.merge({"profiles": alternate_profiles}), job, snapshots, identity["sha256"])
          origin = frozen["source"]
          current_mapping = frozen["mapping"]
          current_timeline = frozen["timeline"]
          frozen["records"].each ->(r)
            records.push(r)
        contexts[name] = context
        timelines[name] = current_timeline
        mappings[name] = current_mapping
        p["resources"] = Budget.new(project.resources).choose(p["width"], p["height"])
        if current_timeline != nil && !parent
          raise "resolved timeline clock differs from plan" if current_timeline["rate"] != p["rate"] || current_timeline["frames"] < p["start"] + p["frames"]
        Pipeline.freeze_profile(project, p, current_mapping)
        opts = options(p, identity["sha256"])
        prepared_audio(context, origin, p, opts, snapshots, current_mapping)
        directory = job + "/" + name
        File.mkdir_p(directory)
        destination = directory + "/output." + p["profile"]["format"]
        probe_only = quality_only && probe_targets.include?(name)
        if p["profile"]["quality"]["mode"] == "search" || probe_only
          raise "quality probes require H.264 or HEVC" if p["profile"]["video"]["codec"].starts_with?("prores")
          choice = Quality.search(context, @media, origin, p, opts, directory + "/quality")
          opts.delete("quality")
          opts["bitrate"] = choice["bitrate"]
          state["quality"][name] = choice
        if !probe_only
          result = @media.request("transcode", origin, opts, directory, destination)
          p["timecode"] = result["tc_start"] if result["tc_start"]
          sealed = snapshots.seal(destination)
          sources[name] = sealed["path"]
          references[name] = origin
          subtitles = project.associated("subtitles", name).map ->(i) Util.get(current_mapping, project.path(i["name"]), project.path(i["name"]))
          subtitles_by_name[name] = subtitles
          verification = verify(context, destination, p, directory + "/checks", origin, current_timeline, subtitles)
          state["outputs"][name] = {"path": destination, "sha256": Util.sha(destination), "result": result, "verification": verification, "reference": origin, "timeline": current_timeline, "project_settings": context.settings, "subtitle_paths": subtitles}
          Util.json(job + "/job.json", state)
          target = project.output_path(p["profile"]["path"])
          entries.push({"source": destination, "destination": target, "role": name, "plan": p})
          index = 0
          subtitles.each ->(subtitle)
            language = project.associated("subtitles", name)[index]["language"]
            suffix = (language ? "." + language : index == 0 ? "" : "." + index.to_s) + ".srt"
            entries.push({"source": subtitle, "destination": target.slice(0, target.size - File.extname(target).size) + suffix, "role": "subtitle"})
            index += 1
          project.associated("chapters", name).each ->(chapter)
            path = project.path(chapter["name"])
            file = Util.get(current_mapping, path, path)
            entries.push({"source": file, "destination": target.slice(0, target.size - File.extname(target).size) + ".chapters" + File.extname(file), "role": "chapters"})
      if !quality_only
        raise "toolchain changed during job" if Inputs.implementation(project.toolchain, @media.package)["sha256"] != identity["sha256"]
        raise "Bitfile changed during job" if Util.sha(project.file) != project.content_sha256
        check = ->(path, entry, reports)
          role = entry["role"]
          if role == "subtitle"
            Text.captions(path)
            {"ok": true, "sha256": Util.sha(path)}
          elsif role == "chapters"
            {"ok": File.stat(path).size > 0, "sha256": Util.sha(path)}
          else
            verify(contexts[role], path, entry["plan"], reports, references[role], timelines[role], subtitles_by_name[role])
        label = Crypto.sha256(JSON.encode((entries.map ->(e) e["role"] + e["destination"]).sort)).slice(0, 16)
        state["release"] = Publisher.new(project.workspace + "/releases/" + label, check).publish(entries, {"job": job, "implementation": identity["sha256"], "inputs": records})
      state["status"] = "complete"
      state["finished"] = Util.now
      state["child_peak_rss_bytes"] = @media.runner.peak_rss
      Util.json(job + "/job.json", state)
      state
    rescue error
      state["status"] = "failed"
      state["finished"] = Util.now
      state["error"] = error.to_s
      state["child_peak_rss_bytes"] = @media.runner.peak_rss
      Util.json(job + "/job.json", state)
      raise error
