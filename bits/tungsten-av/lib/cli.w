use av
use bit/command

in Av

+ CLI
  ro :project, :media, :profiles, :target, :apply, :directory, :source, :timeline

  -> new(args, @command = nil)
    expanded = []
    args.each ->(argument)
      equals = argument.index("=")
      if argument.starts_with?("--") && equals != nil
        expanded.push(argument.slice(0, equals))
        expanded.push(argument.slice(equals + 1, argument.size))
      else
        expanded.push(argument)
    args = expanded
    @directory = "."
    @profiles = []
    @target = "upload"
    @apply = false
    @as_json = false
    @source = nil
    @timeline = nil
    i = 0
    while i < args.size
      arg = args[i]
      if arg == "--json"
        @as_json = true
      elsif arg == "--apply"
        @apply = true
      elsif arg == "--project" || arg == "--profile" || arg == "--target" || arg == "--source" || arg == "--timeline"
        raise "[arg] needs a value" if i + 1 >= args.size
        i += 1
        value = args[i]
        @directory = value if arg == "--project"
        @profiles.push(value) if arg == "--profile"
        @target = value if arg == "--target"
        @source = value if arg == "--source"
        @timeline = value if arg == "--timeline"
      else
        raise "unknown AV option [arg]"
      i += 1

  -> load
    raise "--source/--timeline belong to init; configure sources in the Bitfile" if @source || @timeline
    raise "--apply belongs to gc" if @apply && @command != "gc"
    @project = Project.load(@directory)
    raise "select an isolated toolchain; builds in ~/tungsten are forbidden" if @project.toolchain == Util.absolute("~/tungsten")
    package = Env.get("BIT_PACKAGE_ROOT") || @project.toolchain + "/bits/tungsten-av"
    @media = Media.new(@project.toolchain, File.realpath(package), Runner.new(Util.get(@project.resources, "timeout", 3600)))
    self

  -> emit(value)
    if @command == "plan" && !@as_json
      << "[value["project"]] — [value["toolchain"]]"
      value["profiles"].keys.each ->(name)
        p = value["profiles"][name]
        v = p["profile"]["video"]
        a = p["profile"]["audio"]
        << "  [name]: [p["width"]]×[p["height"]] [p["rate"][0]]/[p["rate"][1]] fps, [p["frames"]] frames → [p["profile"]["path"]]"
        << "    [v["codec"]] [v["depth"]]-bit [v["chroma"]], audio [a["codec"]] [a["sample_rate"]] Hz / [a["channels"]] ch"
      << "  " + value["stages"].join(" → ")
      << "  BLOCKED: insufficient disk for estimated job and reserve" if !value["ready"]
      << "  disk: [value["disk"]["free_bytes"] / 1073741824] GiB free, estimated [value["disk"]["estimated_bytes"] / 1048576] MiB plus reserve"
    else
      << JSON.encode(value)
    value

  -> emit_job(state)
    result = {"ok": true, "status": state["status"], "outputs": state["outputs"], "quality": state["quality"], "child_peak_rss_bytes": state["child_peak_rss_bytes"]}
    result["release"] = state["release"] if state.has_key?("release")
    emit(result)

  -> files
    CLI.files(@as_json)

  -> .run(command_class, args)
    begin
      command = command_class.new(args)
      command.raw_args = args
      if args.include?("--help") || args.include?("-h")
        command.help
      else
        command.execute
    rescue error
      << JSON.encode({"ok": false, "error": error.to_s})
      exit(1)

  -> .root
    Env.get("TUNGSTEN_ROOT") || Util.absolute("../../..", __DIR__)

  -> .files(as_json = false)
    paths = {
      "Native library entry point": "bits/tungsten-av/lib/av.w",
      "Command arguments and helpers": "bits/tungsten-av/lib/cli.w",
      "Processes and storage": "bits/tungsten-av/lib/support.w",
      "Project Bitfile schema": "bits/tungsten-av/lib/config.w",
      "Preflight and plans": "bits/tungsten-av/lib/planner.w",
      "Jobs and delivery": "bits/tungsten-av/lib/pipeline.w",
      "Frozen timeline rendering": "bits/tungsten-av/lib/timeline.w",
      "Audio and anomaly QC": "bits/tungsten-av/lib/qc.w",
      "Text shaping and layout": "bits/tungsten-av/lib/text.w",
      "Pixel and banding QC": "bits/tungsten-av/lib/banding.w",
      "Bitrate probes": "bits/tungsten-av/lib/quality.w",
      "Input snapshots": "bits/tungsten-av/lib/inputs.w",
      "Atomic releases": "bits/tungsten-av/lib/release.w",
      "OS support": "bits/tungsten-av/native/platform.c",
      "Read-only timeline resolver": "apps/studio/tools/av_plan.w",
      "Timeline engine": "apps/studio/studio.w",
      "Transcode API": "core/media/transcode.w",
      "Native AV implementation": "runtime/media/media_avf.m",
      "Exact-font native outlines": "runtime/quartz.c",
      "Package command dispatcher": "bits/tungsten-bit/lib/package_commands.w"
    }
    records = []
    paths.keys.each ->(purpose)
      relative = paths[purpose]
      if relative.starts_with?("bits/tungsten-av/") && Env.get("BIT_PACKAGE_ROOT") != nil
        path = File.join(File.realpath(Env.get("BIT_PACKAGE_ROOT")), relative.slice(17, relative.size))
      else
        path = File.join(root(), relative)
      records.push({"purpose": purpose, "path": path})
      << "[purpose]:\n  [path]" if !as_json
    << JSON.encode(records) if as_json

  -> init
    directory = Util.canonical(Util.absolute(@directory))
    File.mkdir_p(directory)
    file = directory + "/Bitfile"
    content = File.file?(file) ? File.read(file) : "name " + JSON.encode(File.basename(directory)) + "\nversion \"0.1.0\"\n"
    raise "Bitfile already defines an AV project" if Tungsten:Bit:Bitfile.parse(content, file, ["av"]).directives.size > 0
    source = @source
    timeline = @timeline
    timeline = "studio/episode.json" if !source && !timeline && File.file?(directory + "/studio/episode.json")
    raise "init requires --source or --timeline" if !source && !timeline
    raise "choose source or timeline" if source && timeline
    name = File.basename(directory).downcase.replace(" ", "-")
    name = "film-" + Util.id() if !Schema.name?(name)
    declaration = timeline ? "timeline" : "source"
    value = timeline || source
    extra = "\nav.project " + JSON.encode(name) + ", " + declaration + ": " + JSON.encode(value) + ", toolchain: " + JSON.encode(CLI.root) + "\n"
    extra += "av.output \"master\", path: \"render/master.mov\", format: :mov\nav.video \"master\", codec: :hevc10, quality: 0.85\nav.audio \"master\", codec: :pcm, sample_format: :s24le, sample_rate: 48000, channels: 2\n"
    extra += "av.output \"share\", from: \"master\", path: \"render/share.mp4\", format: :mp4\nav.video \"share\", codec: :hevc10, bitrate: \"1800k\"\nav.audio \"share\", codec: :aac, bitrate: \"192k\"\nav.colour \"all\", untagged: :reject\nav.resources memory_mb: 4096, jobs: 4, animation_jobs: 4, disk_reserve_mb: 1024\n"
    probe = directory + "/.av-init-" + Util.id()
    File.mkdir_p(probe)
    begin
      File.write(probe + "/Bitfile", content + extra)
      Project.load(probe)
    ensure
      Util.remove_tree(probe)
    Util.copy_file(file, file + ".before-av-" + Util.id()) if File.file?(file)
    File.atomic_write(file, content + extra)
    {"ok": true, "bitfile": file}

  -> status
    latest = @project.workspace + "/latest.json"
    return {"status": "no jobs", "workspace": @project.workspace} if !File.file?(latest)
    job = JSON.parse(File.read(latest))["job"]
    state = JSON.parse(File.read(job + "/job.json"))
    if state["status"] == "running"
      handle = ccall("w_av_lock", @project.workspace + "/project.lock")
      if handle >= 0
        Util.unlock(handle)
        state["status"] = "interrupted"
    {"job": job, "status": state["status"], "started": state["started"], "finished": state["finished"], "release": state["release"], "error": state["error"], "outputs": state["outputs"].keys, "child_peak_rss_bytes": state["child_peak_rss_bytes"]}

  -> verify
    plan = Planner.new(@project, @media).build(@profiles, false)
    pipeline = Pipeline.new(@project, @media)
    lock = Util.lock(@project.workspace + "/project.lock")
    results = {}
    begin
      plan["profiles"].keys.each ->(name)
        p = plan["profiles"][name]
        path = @project.output_path(p["profile"]["path"])
        context = pipeline.delivery_context(name, path)
        if context != nil
          Pipeline.freeze_profile(@project, p, context["mapping"])
          results[name] = pipeline.verify(context["project"], path, p, @project.workspace + "/checks/" + name, context["reference"], context["timeline"], context["subtitles"])
        else
          parent = p["profile"]["from"]
          reference = parent ? @project.output_path(@project.profiles[parent]["path"]) : plan["source"]
          results[name] = pipeline.verify(@project, path, p, @project.workspace + "/checks/" + name, reference, p["timeline"] || plan["timeline"])
    ensure
      Util.unlock(lock)
    {"ok": true, "profiles": results}

  -> publish
    lock = Util.lock(@project.workspace + "/project.lock")
    begin
      publish_locked()
    ensure
      Util.unlock(lock)

  -> publish_locked
    declarations = @project.declarations["publish"].select ->(i) i["name"] == @target
    raise "define av.publish [@target], root: ..., profiles: ..." if declarations.size != 1
    declaration = declarations[0]
    plans = Planner.new(@project, @media).build(@profiles, false)["profiles"]
    root = @project.path(declaration["root"])
    pipeline = Pipeline.new(@project, @media)
    entries = []
    Util.get(declaration, "profiles", plans.keys).each ->(name)
      raise "unknown publish profile [name]" if !plans.has_key?(name)
      p = plans[name]
      source = @project.output_path(p["profile"]["path"])
      destination = root + (declaration["layout"] == "profiles" ? "/" + name : "") + "/" + File.basename(source)
      context = pipeline.delivery_context(name, source)
      Pipeline.freeze_profile(@project, p, context["mapping"]) if context != nil
      entries.push({"source": source, "destination": destination, "role": name, "plan": p, "context": context})
      @project.associated("subtitles", name).each ->(item)
        suffix = (item["language"] ? "." + item["language"] : "") + ".srt"
        sidecar = source.slice(0, source.size - File.extname(source).size) + suffix
        if File.file?(sidecar)
          entries.push({"source": sidecar, "destination": destination.slice(0, destination.size - File.extname(destination).size) + suffix, "role": "subtitle"})
    Util.get(declaration, "files", []).each ->(file)
      source = @project.path(file)
      entries.push({"source": source, "destination": root + "/" + File.basename(source), "role": "file"})
    check = ->(path, entry, reports)
      if entry["role"] == "subtitle"
        Text.captions(path)
        {"ok": true, "sha256": Util.sha(path)}
      elsif entry["role"] == "file"
        {"ok": File.stat(path).size > 0, "sha256": Util.sha(path)}
      else
        context = entry["context"]
        if context != nil
          pipeline.verify(context["project"], path, entry["plan"], reports, context["reference"], context["timeline"], context["subtitles"])
        else
          reference = @project.settings["source"] ? @project.path(@project.settings["source"]) : nil
          pipeline.verify(@project, path, entry["plan"], reports, reference)
    release = Publisher.new(@project.path(Util.get(declaration, "release_dir", root + "/.av-releases")), check).publish(entries, {"project": @project.name, "bitfile_sha256": Util.sha(@project.file)})
    {"ok": true, "release": release}

  -> collect
    lock = Util.lock(@project.workspace + "/project.lock")
    begin
      before = Util.now - Util.get(@project.resources, "cache_days", 30) * 86400
      latest = @project.workspace + "/latest.json"
      keep = File.file?(latest) ? JSON.parse(File.read(latest))["job"] : nil
      retained = {}
      release_root = @project.workspace + "/releases"
      if File.directory?(release_root)
        visitor = ->(path)
          if File.file?(path) && File.basename(path) == "manifest.json"
            manifest = JSON.parse(File.read(path))
            job = Util.get(manifest, "provenance", {})["job"]
            retained[job] = true if job
        File.walk(release_root, visitor)
      paths = []
      jobs = @project.workspace + "/jobs"
      if File.directory?(jobs)
        File.children(jobs).each ->(name)
          path = jobs + "/" + name
          if path != keep && !retained.has_key?(path) && File.file?(path + "/job.json") && File.stat(path).mtime_ns / ~1e9 < before
            state = JSON.parse(File.read(path + "/job.json"))
            paths.push(path) if state["status"] != "complete"
      if File.directory?(release_root)
        File.children(release_root).each ->(group)
          directory = release_root + "/" + group
          if File.directory?(directory)
            File.children(directory).each ->(name)
              path = directory + "/" + name
              paths.push(path) if name.starts_with?(".candidate-") && File.stat(path).mtime_ns / ~1e9 < before
      paths.each ->(path)
        raise "refusing GC outside workspace" if !Util.inside?(Util.canonical(path), @project.workspace)
      paths.each ->(path) Util.remove_tree(path) if @apply
      {"apply": @apply, "paths": paths}
    ensure
      Util.unlock(lock)
