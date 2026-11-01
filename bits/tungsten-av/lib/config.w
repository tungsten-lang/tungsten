# AV-specific Bitfile schema and project validation.
use bit/bitfile

in Av

+ Schema
  -> .fields
    {
      "project": "source timeline cut mix toolchain workspace cache snapshot_inputs timecode generator_clock scene_rate title",
      "output": "path role from source format width height rate fit filter start_frame frames faststart edit_lists timeline cut mix",
      "video": "codec bitrate quality depth chroma level gop reorder speed backend crop rect",
      "audio": "codec bitrate sample_format sample_rate channels layout source",
      "colour": "primaries transfer matrix range untagged",
      "subtitles": "profile language mode", "chapters": "profile format",
      "loudness": "enabled target tolerance true_peak max_clipped_samples max_silence silence_threshold max_channel_difference",
      "text": "enabled font size minimum_size box safe_area foreground background minimum_contrast burned minimum_edge_recall max_error",
      "anomalies": "enabled black_min freeze_min noise allow_black allow_freeze policy",
      "resources": "memory_mb disk_reserve_mb jobs animation_jobs decode_ahead segments_ahead timeout native_timeout_ms retries cache_days",
      "quality": "mode minimum_bitrate maximum_bitrate max_probes probe_frames minimum_ssim minimum_vmaf sample_frames",
      "banding": "auto background gradient samples limits exclude exclude_normalized shots max_samples asset_prefix program_id",
      "publish": "root layout profiles files release_dir", "prepare": "argv cwd", "input": "path generated", "gate": "pattern equal profile"
    }

  -> .per_profile
    "video audio colour loudness text anomalies quality banding".split(" ")

  -> .name?(value)
    type(value) == "String" && Regex.new("\\A\[a-z]\[a-z0-9_-]{0,63}\\z").match?(value)

  -> .number?(value)
    (type(value) == "Int" || type(value) == "Float") && !value.to_f.nan? && !value.to_f.infinite?

  -> .positive(value, name, zero = false)
    raise "[name] must be a finite positive number" if !number?(value) || (zero ? value < 0 : value <= 0)

  -> .integer(value, name, low = 1, high = 2147483647)
    raise "[name] must be an integer in [low]..[high]" if type(value) != "Int" || value < low || value > high

  -> .boolean(value, name)
    raise "[name] must be true or false" if value != true && value != false

  -> .one_of(value, allowed, name)
    raise "unsupported [name]: [value]" if !allowed.include?(value)

  -> .bitrate(value)
    return value if type(value) == "Int" && value > 0
    if type(value) == "String"
      m = Regex.new("\\A(\[0-9]+(?:\\.\[0-9]+)?)\\s*(\[kKmM]?)\\z").match_data(value)
      if m != nil
        unit = m[2].downcase
        n = m[1].to_f * (unit == "m" ? 1000000 : unit == "k" ? 1000 : 1)
        return n.to_i if n > 0 && n == n.to_i.to_f
    raise "bitrate must be positive bits/second, e.g. 1800000 or \"1800k\""

+ Project
  ro :root, :file, :name, :settings, :declarations, :content_sha256

  -> new(@root, @file, @name, @settings, @declarations, @content_sha256)

  -> .load(directory)
    path = Util.canonical(Util.absolute(directory))
    if !File.file?(path)
      while !File.file?(path + "/Bitfile")
        parent = File.dirname(path)
        raise "No project Bitfile found; run bit av init" if parent == path
        path = parent
      path += "/Bitfile"
    raise "project configuration must be named Bitfile" if File.basename(path) != "Bitfile"
    raise "Bitfile is too large" if File.stat(path).size > 1048576
    text = File.read(path)
    declarations = {}
    fields = Schema.fields
    fields.keys.each ->(kind)
      declarations[kind] = []
    manifest = Tungsten:Bit:Bitfile.parse(text, path, ["av"])
    manifest.directives.each ->(entry)
      begin
        method = "av." + entry.name
        kind = entry.name
        raise "unknown AV directive [method]" if !fields.has_key?(kind)
        args = entry.arguments
        options = entry.options
        options.keys.each ->(key)
          raise "unknown [method] option [key]" if !fields[kind].split(" ").include?(key)
        if kind == "resources"
          raise "av.resources accepts keyword options" if args.size != 0
          label = "all"
        else
          raise "[method] expects one name/path and keyword options" if args.size != 1 || type(args[0]) != "String"
          label = args[0]
        declarations[kind].push(options.merge({"name": label}))
      rescue error
        raise "[path]:[entry.line]: [error]"
    raise "Bitfile must contain exactly one av.project directive" if declarations["project"].size != 1
    settings = declarations["project"][0].dup
    name = settings.delete("name")
    project = Project.new(File.dirname(path), path, name, settings, declarations, Util.sha(path))
    project.validate
    project

  -> with_settings(settings)
    Project.new(@root, @file, @name, settings, @declarations, @content_sha256)

  -> path(value)
    raise "path requires a string" if type(value) != "String"
    Util.canonical(Util.absolute(value, @root))

  -> output_path(value)
    raise "output path requires a string" if type(value) != "String"
    target = Util.absolute(value, @root)
    File.join(Util.canonical(File.dirname(target)), File.basename(target))

  -> workspace
    path(Util.get(@settings, "workspace", ".av"))

  -> toolchain
    selected = Env.get("STUDIO_TW") || @settings["toolchain"] || Env.get("TUNGSTEN_ROOT")
    raise "select an isolated toolchain with av.project toolchain:" if selected == nil
    path(selected)

  -> associated(kind, profile)
    @declarations[kind].select ->(item) Util.get(item, "profile", "all") == "all" || item["profile"] == profile

  -> resources
    result = @declarations["resources"].size == 0 ? {} : @declarations["resources"][0].dup
    result.delete("name")
    result.keys.each ->(key)
      Schema.positive(result[key], "resources." + key, key == "disk_reserve_mb" || key == "retries")
    "jobs animation_jobs decode_ahead segments_ahead retries native_timeout_ms".split(" ").each ->(key)
      Schema.integer(result[key], key, key == "retries" ? 0 : 1) if result.has_key?(key)
    Schema.integer(Util.get(result, "segments_ahead", 3), "segments_ahead", 1, 3)
    Schema.integer(Util.get(result, "decode_ahead", 6), "decode_ahead", 1, 32)
    Schema.integer(Util.get(result, "retries", 2), "retries", 0, 5)
    result

  -> profiles
    outputs = @declarations["output"]
    outputs = [{"name": "master"}] if outputs.size == 0
    names = outputs.map ->(p) p["name"]
    raise "output names must be unique simple names" if Util.unique(names).size != names.size
    names.each ->(name)
      raise "invalid profile name" if !Schema.name?(name)
    Schema.per_profile.each ->(kind)
      labels = @declarations[kind].map ->(p) p["name"]
      raise "duplicate av.[kind] profile" if Util.unique(labels).size != labels.size
      labels.each ->(label)
        raise "unknown profile in av.[kind]" if label != "all" && !names.include?(label)
    pending = {}
    outputs.each ->(output)
      p = Util.copy(output)
      name = p["name"]
      raise "output cut/mix require an alternate timeline" if !p["timeline"] && (p.has_key?("cut") || p.has_key?("mix"))
      raise "choose timeline or from" if p["timeline"] && p["from"]
      p["role"] = names.include?(name) && ["master", "share", "short"].include?(name) ? name : "master" if !p.has_key?("role")
      p["format"] = p["role"] == "share" ? "mp4" : "mov" if !p.has_key?("format")
      Schema.one_of(p["format"], ["mov", "mp4"], "container")
      p["path"] = "render/" + name + "." + p["format"] if !p.has_key?("path")
      raise "output extension must match format" if File.extname(p["path"]).downcase != "." + p["format"]
      Schema.per_profile.each ->(kind)
        settings = {}
        ["all", name].each ->(label)
          @declarations[kind].each ->(item)
            if item["name"] == label
              settings.merge!(item)
              settings.delete("name")
        p[kind] = settings
      defaults(p)
      validate_profile(p)
      pending[name] = p
    ordered = {}
    while pending.size > 0
      progress = false
      pending.keys.each ->(name)
        p = pending[name]
        if !p["from"] || ordered.has_key?(p["from"])
          ordered[name] = pending.delete(name)
          progress = true
      raise "unknown or cyclic output from dependency" if !progress
    targets = ordered.values.map ->(p) output_path(p["path"])
    raise "output paths must be unique" if Util.unique(targets).size != targets.size
    raise "an output would overwrite the source" if @settings["source"] && targets.include?(path(@settings["source"]))
    ordered

  -> defaults(p)
    v = p["video"]
    v["codec"] = "hevc10" if !v.has_key?("codec")
    codec = v["codec"]
    Schema.one_of(codec, ["h264", "hevc", "hevc10", "prores422", "prores422hq", "prores422lt", "prores422proxy"], "video codec")
    depth = codec == "hevc10" || codec.starts_with?("prores") ? 10 : 8
    chroma = codec.starts_with?("prores") ? "422" : "420"
    v["depth"] = depth if !v.has_key?("depth")
    v["chroma"] = chroma if !v.has_key?("chroma")
    raise "codec/depth/chroma conflict" if v["depth"] != depth || v["chroma"].to_s != chroma
    v["chroma"] = chroma
    v["bitrate"] = Schema.bitrate(v["bitrate"]) if v.has_key?("bitrate")
    raise "choose video quality or bitrate" if v.has_key?("quality") && v.has_key?("bitrate")
    raise "ProRes uses quality rather than bitrate" if codec.starts_with?("prores") && v.has_key?("bitrate")
    a = p["audio"]
    a["codec"] = p["format"] == "mp4" ? "aac" : "pcm" if !a.has_key?("codec")
    {"sample_format": "s24le", "sample_rate": 48000, "channels": 2}.keys.each ->(key)
      defaults = {"sample_format": "s24le", "sample_rate": 48000, "channels": 2}
      a[key] = defaults[key] if !a.has_key?(key)
    Schema.one_of(a["codec"], ["aac", "pcm", "copy", "none"], "audio codec")
    Schema.one_of(a["sample_format"], ["s16le", "s24le", "s32le", "f32le"], "PCM format")
    Schema.one_of(a["sample_rate"], [32000, 44100, 48000, 88200, 96000], "audio sample rate")
    Schema.one_of(a["channels"], [1, 2], "audio channels")
    raise "audio layout conflicts with channels" if a.has_key?("layout") && a["layout"] != (a["channels"] == 1 ? "mono" : "stereo")
    raise "PCM delivery requires MOV" if a["codec"] == "pcm" && p["format"] != "mov"
    if a.has_key?("bitrate")
      a["bitrate"] = Schema.bitrate(a["bitrate"])
      raise "AAC bitrate requires whole kbps and codec aac" if a["codec"] != "aac" || a["bitrate"] % 1000 != 0
    p["edit_lists"] = !(p["format"] == "mov" && ["pcm", "none"].include?(a["codec"])) if !p.has_key?("edit_lists")
    raise "strict no-edit audio requires PCM MOV" if p["edit_lists"] == false && !["pcm", "none"].include?(a["codec"])
    c = p["colour"]
    {"primaries": "bt709", "transfer": "bt709", "matrix": "bt709", "range": "limited", "untagged": "reject"}.keys.each ->(key)
      defaults = {"primaries": "bt709", "transfer": "bt709", "matrix": "bt709", "range": "limited", "untagged": "reject"}
      c[key] = defaults[key] if !c.has_key?(key)
      raise "renderer delivers BT.709 limited-range SDR" if key != "untagged" && c[key] != defaults[key]
    Schema.one_of(c["untagged"], ["reject", "bt709"], "untagged colour")
    ["loudness", "text", "anomalies"].each ->(kind)
      p[kind]["enabled"] = false if !p[kind].has_key?("enabled")
    q = p["quality"]
    Schema.one_of(Util.get(q, "mode", "fixed"), ["fixed", "search"], "quality mode")
    raise "bitrate search requires H.264 or HEVC" if q["mode"] == "search" && codec.starts_with?("prores")
    ["minimum_bitrate", "maximum_bitrate"].each ->(key)
      q[key] = Schema.bitrate(q[key]) if q.has_key?(key)

  -> validate_profile(p)
    ["width", "height", "frames", "start_frame"].each ->(key)
      if p.has_key?(key)
        Schema.integer(p[key], key, key == "start_frame" ? 0 : 1)
        raise "[key] must be even and <= 16384" if key != "frames" && key != "start_frame" && (p[key] % 2 != 0 || p[key] > 16384)
    if p.has_key?("rate")
      r = p["rate"]
      raise "rate must be a positive numerator/denominator pair" if type(r) != "Array" || r.size != 2
      Schema.integer(r[0], "rate numerator")
      Schema.integer(r[1], "rate denominator")
      g = r[0].gcd(r[1])
      p["rate"] = [r[0] / g, r[1] / g]
    ["edit_lists", "faststart"].each ->(key)
      Schema.boolean(p[key], key) if p.has_key?(key)
    Schema.one_of(Util.get(p, "fit", "stretch"), ["stretch", "contain", "cover"], "fit")
    Schema.one_of(Util.get(p, "filter", "lanczos3"), ["lanczos3", "bicubic", "bilinear"], "filter")
    v = p["video"]
    ["speed", "reorder"].each ->(key)
      Schema.boolean(v[key], key) if v.has_key?(key)
    Schema.integer(v["gop"], "gop", 1, 1000) if v.has_key?("gop")
    if v.has_key?("quality")
      raise "quality must be in 0..1" if !Schema.number?(v["quality"]) || v["quality"] < 0 || v["quality"] > 1
    ["crop", "rect"].each ->(key)
      if v.has_key?(key)
        r = v[key]
        raise "[key] must be x,y,positive width,height" if type(r) != "Array" || r.size != 4 || !Util.all(r.map ->(x) Schema.number?(x)) || r[0] < 0 || r[1] < 0 || r[2] <= 0 || r[3] <= 0
    ["loudness", "text", "anomalies"].each ->(kind)
      Schema.boolean(p[kind]["enabled"], kind + ".enabled")
    l = p["loudness"]
    raise "audio QC requires an audio output" if l["enabled"] && p["audio"]["codec"] == "none"
    "tolerance max_silence max_clipped_samples max_channel_difference".split(" ").each ->(key)
      Schema.positive(l[key], key, true) if l.has_key?(key)
    "target true_peak silence_threshold".split(" ").each ->(key)
      raise "[key] must be between -100 and 0 dB" if l.has_key?(key) && (!Schema.number?(l[key]) || l[key] < -100 || l[key] > 0)
    t = p["text"]
    "size minimum_size minimum_contrast max_error".split(" ").each ->(key)
      Schema.positive(t[key], key) if t.has_key?(key)
    "safe_area minimum_edge_recall".split(" ").each ->(key)
      raise "[key] must be in 0..1" if t.has_key?(key) && (!Schema.number?(t[key]) || t[key] < 0 || t[key] > 1)
    if t.has_key?("box")
      b = t["box"]
      raise "text box must be normalized inside image" if type(b) != "Array" || b.size != 4 || !Util.all(b.map ->(x) Schema.number?(x) && x >= 0 && x <= 1) || b[2] <= 0 || b[3] <= 0 || b[0] + b[2] > 1 || b[1] + b[3] > 1
    raise "text QC requires an explicit font file" if t["enabled"] && !t["font"]
    a = p["anomalies"]
    "black_min freeze_min noise".split(" ").each ->(key)
      Schema.positive(a[key], key) if a.has_key?(key)
    Schema.one_of(Util.get(a, "policy", "fail"), ["fail", "report"], "anomalies policy")
    ["allow_black", "allow_freeze"].each ->(key)
      ranges = Util.get(a, key, [])
      raise "[key] must contain increasing second intervals" if type(ranges) != "Array" || !Util.all(ranges.map ->(r) type(r) == "Array" && r.size == 2 && Schema.number?(r[0]) && Schema.number?(r[1]) && r[0] >= 0 && r[1] > r[0])
    q = p["quality"]
    raise "minimum bitrate exceeds maximum" if Util.get(q, "minimum_bitrate", 500000) > Util.get(q, "maximum_bitrate", Util.get(v, "bitrate", 8000000))
    Schema.integer(q["max_probes"], "max_probes", 1, 12) if q.has_key?("max_probes")
    Schema.integer(q["probe_frames"], "probe_frames", 1, 240) if q.has_key?("probe_frames")
    if q.has_key?("sample_frames")
      raise "quality sample_frames needs 1..16 frames" if type(q["sample_frames"]) != "Array" || q["sample_frames"].size < 1 || q["sample_frames"].size > 16
    ["minimum_ssim", "minimum_vmaf"].each ->(key)
      maximum = key == "minimum_ssim" ? 1 : 100
      raise "[key] is outside metric range" if q.has_key?(key) && (!Schema.number?(q[key]) || q[key] < 0 || q[key] > maximum)

  -> validate
    raise "invalid project name" if !Schema.name?(@name)
    raise "av.project requires exactly one source or timeline" if !!@settings["source"] == !!@settings["timeline"]
    raise "snapshot_inputs must be true" if Util.get(@settings, "snapshot_inputs", true) != true
    "source timeline mix toolchain workspace cache title".split(" ").each ->(key)
      raise "project.[key] requires a nonempty string" if @settings.has_key?(key) && (type(@settings[key]) != "String" || @settings[key] == "")
    raise "workspace must be a dedicated project subdirectory" if !Util.inside?(workspace, @root) || workspace.split("/").include?(".git")
    raise "cache must be inside workspace" if @settings["cache"] && !Util.inside?(path(@settings["cache"]), workspace)
    ["resources", "prepare", "publish", "input"].each ->(kind)
      labels = @declarations[kind].map ->(i) i["name"]
      raise "duplicate av.[kind] name" if Util.unique(labels).size != labels.size
    @declarations["prepare"].each ->(item)
      a = item["argv"]
      raise "prepare argv must be a nonempty string array" if type(a) != "Array" || a.size == 0 || !Util.all(a.map ->(s) type(s) == "String" && !s.include?("\0"))
      raise "use an explicit executable instead of a host Python placeholder" if a.include?("{python}")
    profiles = profiles()
    ["subtitles", "chapters", "gate"].each ->(kind)
      @declarations[kind].each ->(item)
        profile = Util.get(item, "profile", "all")
        raise "unknown [kind] profile" if profile != "all" && !profiles.has_key?(profile)
        if kind == "subtitles"
          Schema.one_of(Util.get(item, "mode", "sidecar"), ["sidecar", "timeline"], "subtitle mode")
          raise "timeline subtitles require a timeline project" if item["mode"] == "timeline" && !@settings["timeline"]
          raise "invalid subtitle language tag" if item["language"] && !Regex.new("\\A\[A-Za-z]{2,8}(?:-\[A-Za-z0-9]{1,8})*\\z").match?(item["language"])
        if kind == "gate"
          pattern = item["pattern"]
          raise "gate pattern must be a bounded string" if type(pattern) != "String" || pattern == "" || pattern.size > 4096
          Regex.new(pattern)
          if item.has_key?("equal")
            pair = item["equal"]
            raise "gate equal must contain positive capture indices" if type(pair) != "Array" || pair.size != 2
            pair.each ->(i)
              Schema.integer(i, "gate capture")
    @declarations["publish"].each ->(item)
      raise "publish root is required" if type(item["root"]) != "String"
      Schema.one_of(Util.get(item, "layout", "flat"), ["flat", "profiles"], "publish layout")
      Util.get(item, "profiles", profiles.keys).each ->(name)
        raise "publish references unknown profile" if !profiles.has_key?(name)
      files = Util.get(item, "files", [])
      raise "publish files must be a string array" if type(files) != "Array" || !Util.all(files.map ->(v) type(v) == "String")
    resources()
    true
