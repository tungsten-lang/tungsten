# studio/project — locating an episode, verifying its assets by content, writing the resolved timeline,
# diffing two resolved timelines, and the SubRip / chapter text generated from a resolved timeline.

use base
use resolve
use encode

+ Project
  ro :ep, :path, :dir, :root, :build, :cut, :resolved, :asset_sha, :encoder

  -> new(@path, @cut)
    @path = File.expand_path(@path)
    @dir = dir_of(@path)
    @ep = JSON.parse(File.read(@path))
    @root = File.expand_path(path_join(@dir, get(@ep, "root", ".")))
    @build = path_join(@dir, "build")
    mkdir_p(@build + "/" + @cut)
    @asset_sha = {}
    @resolved = nil
    @encoder = encoder_spec(@ep["cuts"][@cut])
    ENCODER["id"] = @encoder["id"]
    SEGMENT_EXT["ext"] = @encoder["ext"]

  -> asset_path(key)
    a = @ep["assets"][key]
    die("unknown asset " + key.to_s) if a == nil
    path_join(@root, a["path"])

  # Content addressing (TIMELINE.md §1): an asset's hash is recomputed when its size or mtime changed since the
  # last run (build/assets.json caches size, mtime and SHA-256 per file). If the file no longer matches the hash
  # episode.json recorded, the new hash wins and is reported, so a swapped panel re-renders its shot even when
  # nobody updated the document.
  -> verify_assets(quiet)
    cache_path = @build + "/assets.json"
    cache = {}
    cache = JSON.parse(File.read(cache_path)) if File.exist?(cache_path)
    # pass 1: every file behind every asset, and the ones whose size or mtime changed since they were hashed
    files = {}
    todo = []
    @ep["assets"].keys.each ->(key)
      a = @ep["assets"][key]
      p = path_join(@root, a["path"])
      list = []
      if get(a, "kind", "") == "frames"
        names = []
        File.entries(p).each ->(nm)
          names.push(nm) if nm.ends_with?(".png") || nm.ends_with?(".jpg")
        names.sort.each ->(nm)
          list.push(p + "/" + nm)
      else
        list.push(p)
      files[key] = list
      list.each ->(fp)
        die("missing file " + fp) if !File.exist?(fp)
        st = File.stat(fp)
        sk = st.size.to_s + ":" + st.mtime_ns.to_s
        c = cache[fp]
        if c == nil || c[0] != sk
          cache[fp] = [sk, nil]
          todo.push(fp)
    # hash the changed files in one streaming pass (shasum reads in blocks; no file is held in memory)
    if todo.size > 0
      lst = @build + "/hash_todo.txt"
      File.write(lst, todo.join("\n") + "\n")
      outp = OS.capture("tr '\\n' '\\0' < " + shq(lst) + " | xargs -0 shasum -a 256")
      outp.split("\n").each ->(ln)
        if ln.size > 66
          h = ln.slice(0, 64)
          fp = ln.slice(66, ln.size - 66)
          c = cache[fp]
          c[1] = h if c != nil
    changed = 0
    @ep["assets"].keys.each ->(key)
      a = @ep["assets"][key]
      list = files[key]
      if get(a, "kind", "") == "frames"
        lines = []
        list.each ->(fp)
          h = cache[fp][1]
          die("could not hash " + fp) if h == nil
          lines.push(base_of(fp) + ":" + h + "\n")
        digest = sha(lines.join(""))
      else
        digest = cache[list[0]][1]
        die("could not hash " + list[0]) if digest == nil
      if digest != a["sha256"]
        changed += 1
        << "asset changed on disk: " + key + " (" + a["path"] + ")" if !quiet
      @asset_sha[key] = digest
    write_text(cache_path, JSON.encode(cache))
    << "assets: " + @ep["assets"].size.to_s + " verified, " + todo.size.to_s + " files hashed, " + changed.to_s + " changed" if !quiet
    changed

  # ---- program items (TIMELINE.md §3.1 `program`): a Tungsten scene compiled from its source file, its frames
  # a cache keyed by the program hash = H(generated program text, the data files it reads, the compiler).
  -> compiler_path
    c = env("STUDIO_TUNGSTEN")
    return c if c != nil && c != ""
    "/Users/erik/tungsten-worktrees/engine/bin/tungsten"

  -> compiler_id
    if @compiler_id == nil
      cp = File.expand_path(dir_of(compiler_path()) + "/tungsten-compiler")
      st = File.stat(cp)
      @compiler_id = sha(cp + ":" + st.size.to_s + ":" + st.mtime_ns.to_s)
    @compiler_id

  # One module of a build_scenes.py program (core + the module's section) with a dispatcher for that scene alone,
  # writing its frames to a given directory.
  -> program_text(spec)
    src = File.read(path_join(@root, spec["source"]))
    mod = spec["module"]
    mark = "# ===================================================================================== module "
    first = src.index(mark)
    die("no modules in " + spec["source"]) if first == nil
    core = src.slice(0, first)
    at = src.index(mark + mod + "\n")
    die("no module " + mod + " in " + spec["source"]) if at == nil
    rest = src.slice(at + 1, src.size - at - 1)
    nxt = rest.index(mark)
    disp = rest.index("# Dispatcher & CLI")
    stop = rest.size
    stop = nxt if nxt != nil && nxt < stop
    stop = disp if disp != nil && disp < stop
    body = src.slice(at, stop + 1)
    d = "\n# ---- dispatcher for one scene (generated by studio)\n"
    d = d + "-> render_one(db, anim_id, t, len, path)\n  svg = Svg.new(1920, 1080)\n"
    if mod == "outro"
      d = d + "  draw_outro(svg, db, t, len)\n  svg.write_png(path)\n  return 0\n"
    else
      d = d + "  background(svg)\n  draw_" + mod + "(svg, db, t, len)\n  prog = Motion.clamp01(t / len)\n"
      d = d + "  if anim_id != \"title\"\n    svg.line(0, 1078, ~1920.0 * prog, 1078, {stroke: c_gold, width: 4, stroke_opacity: ~0.65})\n"
      d = d + "  dip = ~1.0 - sm(t, ~0.0, ~0.35) * (~1.0 - sm(t, len - ~0.38, ~0.35))\n  if dip > ~0.003\n    svg.rect(0, 0, 1920, 1080, {fill: c_bg, fill_opacity: dip})\n  svg.write_png(path)\n  0\n"
    d = d + "\n-> main(args)\n  dir = args\[0\]\n  anim_id = args\[1\]\n  dur = args\[2\].to_f\n  first = args\[3\].to_i\n  last = args\[4\].to_i\n  outdir = args\[5\]\n"
    d = d + "  db = load_db(dir, anim_id)\n  f = first\n  while f <= last\n    t = (f + ~0.0) / ~24.0\n"
    d = d + "    render_one(db, anim_id, t, dur, outdir + \"/\" + Motion.pad(f, 5) + \".png\")\n    f += 1\n  0\n\n"
    d = d + "args = \[\]\ni_arg = 0\nwhile i_arg < ARGV.size\n  if ARGV\[i_arg\] != \"--\"\n    args.push(ARGV\[i_arg\])\n  i_arg += 1\nmain(args)\n"
    core + body + d

  # Fill in source_sha (and the frame count) of every program shot before resolving.
  -> prepare_programs
    @programs = {}
    @ep["shots"].each ->(s)
      if s["kind"] == "program"
        spec = s["program"]
        text = program_text(spec)
        parts = [text, compiler_id()]
        get(spec, "data", []).each ->(df)
          parts.push(df + ":" + sha(File.read(path_join(@root, df))))
        h = sha(parts.join("\n"))
        s["source_sha"] = h
        @programs[h] = [text, spec]
    nil

  -> program_dir(h)
    @build + "/programs/" + h

  # Render a program's frames into its cache if they are not all there: compile once, run the scene.
  -> ensure_program(it, fps_num, fps_den)
    p = it["params"]
    h = p["source_sha"]
    n = p["count"]
    d = program_dir(h)
    last = d + "/" + pad_int(n - 1, 5) + ".png"
    return false if File.exist?(last)
    mkdir_p(d)
    pr = @programs[h]
    write_text(d + "/program.w", pr[0])
    bin = d + "/scene_bin"
    t0 = clock_ms()
    if !File.exist?(bin)
      die("program compile failed: " + d) if !OS.system(shq(compiler_path()) + " -o " + shq(bin) + " " + shq(d + "/program.w") + " > " + shq(d + "/compile.log") + " 2>&1")
    t1 = clock_ms()
    dur = (p["dur_ms"] + ~0.0) / ~1000.0
    die("program run failed: " + d) if !OS.system(shq(bin) + " " + shq(@root) + " " + shq(pr[1]["module"]) + " " + dur.to_s + " 0 " + (n - 1).to_s + " " + shq(d) + " > " + shq(d + "/run.log") + " 2>&1")
    << "program " + it["id"] + " (" + h.slice(0, 12) + "): compiled in " + (t1 - t0).to_s + " ms, " + n.to_s + " frames in " + (clock_ms() - t1).to_s + " ms"
    true

  -> resolve
    prepare_programs() if @programs == nil
    r = Resolver.new(@ep, @cut, @asset_sha)
    @resolved = r.resolve
    @resolved

  # Outputs of this document under build/<cut>/: episode.json writes timeline.resolved.json, mix.wav, master.mp4;
  # a variant (edit.json) writes edit.timeline.resolved.json, edit.mix.wav, ... and shares the segment cache.
  -> out_path(name)
    stem = base_of(@path)
    stem = stem.slice(0, stem.size - 5) if stem.ends_with?(".json")
    pre = ""
    pre = stem + "." if stem != "episode"
    @build + "/" + @cut + "/" + pre + name

  -> resolved_path
    out_path("timeline.resolved.json")

  -> write_resolved(path)
    write_text(path, resolved_json(@resolved))

# One line per item / interval / segment, so two resolved timelines diff line by line.
-> resolved_json(r)
  out = "{\n"
  keys = r.keys
  ki = 0
  while ki < keys.size
    k = keys[ki]
    v = r[k]
    sep = ki + 1 < keys.size ? "," : ""
    if k == "tracks"
      out = out + " \"tracks\": \[\n"
      ti = 0
      while ti < v.size
        t = v[ti]
        out = out + "  {\"id\": " + JSON.encode(t["id"]) + ", \"kind\": " + JSON.encode(t["kind"])
        out = out + ", \"role\": " + JSON.encode(t["role"]) if t["role"] != nil
        out = out + ", \"items\": \[\n"
        ii = 0
        while ii < t["items"].size
          out = out + "   " + JSON.encode(t["items"][ii]) + (ii + 1 < t["items"].size ? ",\n" : "\n")
          ii += 1
        out = out + "  \]}" + (ti + 1 < v.size ? ",\n" : "\n")
        ti += 1
      out = out + " \]" + sep + "\n"
    elsif k == "intervals" || k == "segments"
      out = out + " " + JSON.encode(k) + ": \[\n"
      ii = 0
      while ii < v.size
        out = out + "  " + JSON.encode(v[ii]) + (ii + 1 < v.size ? ",\n" : "\n")
        ii += 1
      out = out + " \]" + sep + "\n"
    else
      out = out + " " + JSON.encode(k) + ": " + JSON.encode(v) + sep + "\n"
    ki += 1
  out + "}\n"

# studio diff: what changed between two resolved timelines, before anything renders.
-> diff_resolved(a, b)
  have = {}
  a["segments"].each ->(s)
    have[s["key"]] = 1
  fresh = []
  reused = 0
  b["segments"].each ->(s)
    if have[s["key"]] == nil
      fresh.push(s)
    else
      reused += 1
  # merge contiguous new segments into frame ranges
  ranges = []
  fresh.each ->(s)
    if ranges.size > 0 && ranges[ranges.size - 1][1] == s["f0"]
      ranges[ranges.size - 1][1] = s["f0"] + s["n"]
      s["items"].each ->(nm)
        ranges[ranges.size - 1][2].push(nm) if !ranges[ranges.size - 1][2].include?(nm)
    else
      ranges.push([s["f0"], s["f0"] + s["n"], s["items"].dup])
  nfr = 0
  fresh.each ->(s)
    nfr += s["n"]
  # items whose recipe changed, and items that only moved
  old = {}
  a["tracks"][0]["items"].each ->(it)
    old[it["id"]] = it
  changed = []
  moved = 0
  b["tracks"][0]["items"].each ->(it)
    o = old[it["id"]]
    if o == nil || o["recipe"] != it["recipe"]
      changed.push(it["id"])
    elsif o["f0"] != it["f0"] || o["f1"] != it["f1"]
      moved += 1
  {"frames" => [a["frames"], b["frames"]], "segments" => b["segments"].size, "reused" => reused,
   "new_segments" => fresh.size, "new_frames" => nfr, "ranges" => ranges, "changed_items" => changed, "moved_items" => moved,
   "new_keys" => fresh}

# textwrap.wrap(text, width): greedy fill, words also break after an inner hyphen (Python's break_on_hyphens).
-> wrap_text(text, width)
  pieces = []
  split_words(text).each ->(w)
    parts = []
    cur = ""
    i = 0
    while i < w.size
      ch = w.slice(i, 1)
      cur = cur + ch
      if ch == "-" && i > 0 && i + 1 < w.size && cur.size > 1
        nxt = w.byte_at(i + 1)
        prv = w.byte_at(i - 1)
        if ((nxt >= 65 && nxt <= 90) || (nxt >= 97 && nxt <= 122)) && ((prv >= 65 && prv <= 90) || (prv >= 97 && prv <= 122))
          parts.push(cur)
          cur = ""
      i += 1
    parts.push(cur) if cur != ""
    k = 0
    while k < parts.size
      pieces.push([parts[k], k == 0])
      k += 1
  lines = []
  line = ""
  pieces.each ->(p)
    add = p[0]
    add = " " + add if p[1] && line != ""
    if line != "" && (line + add).size > width
      lines.push(line)
      line = p[0]
    else
      line = line + add
  lines.push(line) if line != ""
  lines

-> srt_text(r)
  subs = r["tracks"][4]["items"]
  out = []
  n = 1
  subs.each ->(s)
    # narration cues wrap at 48 columns (textwrap); the outro's own captions are written as they are (tools/srt.py)
    body = s["text"]
    body = wrap_text(s["text"], 48).join("\n") if s["line"] != nil
    out.push(n.to_s + "\n" + srt_time(s["from_ms"]) + " --> " + srt_time(s["to_ms"]) + "\n" + body + "\n")
    n += 1
  out.join("\n")

-> chapters_text(r)
  out = ""
  r["tracks"][5]["items"].each ->(m)
    out = out + chapter_time(m["sec"]) + " " + m["title"] + "\n"
  out
