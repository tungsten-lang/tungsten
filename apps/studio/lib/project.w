# studio/project — locating an episode, verifying its assets by content, writing the resolved timeline,
# diffing two resolved timelines, and the SubRip / chapter text generated from a resolved timeline.

use base
use resolve
use encode
use grade

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
    @encoder = encoder_spec(cut_cfg(@cut))
    ENCODER["id"] = @encoder["id"]
    SEGMENT_EXT["ext"] = @encoder["ext"]
    GRADE["id"] = grade_impl(@ep["cuts"][@cut])

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

  -> cut_cfg(name)
    c = @ep["cuts"][name]
    die("no cut " + name.to_s) if c == nil
    c

  # A section of the document for this cut: the cut's own lines/shots/cues/captions/markers, else the episode's.
  -> section(k)
    v = cut_cfg(@cut)[k]
    v = @ep[k] if v == nil
    v = [] if v == nil
    v

  # ---- program items (TIMELINE.md §3.1 `program`): a Tungsten program compiled from source, its frames a cache
  # keyed by the program hash = H(program text, the files it reads, the compiler) and the run's arguments.
  #
  #   "program": {"source": "scenes.w",                     relative to the episode root, or absolute
  #               "extract": {"marker": "# == module ", "name": "title", "stops": ["# Dispatcher & CLI"]},
  #                                                         optional: the text before the first marker plus the
  #                                                         marked section `name` (up to the next marker or a stop)
  #               "patch": [[find, replace], ...],          optional literal substitutions (each must match)
  #               "append": "...",                          optional text appended (a dispatcher)
  #               "data": ["data/cues.csv", ...],           files the frames depend on (hashed into the key)
  #               "link": {"from": ".", "exclude": ["frames", "out"]},   optional: run in a work dir that links the
  #                                                         entries of a folder (relative to the root)
  #               "run": ["{root}", "title", "{dur}", "{first}", "{last}", "{dir}"],   argv after the binary
  #               "frames": "{dir}/%05d.png",              where frame k lands
  #               "count": "dur" | {"run": ["info", "{work}"]},   the frame count: round(duration x rate), or
  #                                                         the last line the program prints for these arguments
  #               "captions": {"run": ["srt", "{work}"], "file": "{work}/out/captions.srt"}}   optional: captions the
  #                                                         program writes for its frames (a shot opts in with
  #                                                         "captions_from_program": true)
  # Placeholders: {root} the episode root, {dir} the run's cache directory, {work} its linked work directory,
  # {dur} the item's duration in seconds, {first} {last} the frame range (inclusive).
  -> compiler_path
    c = env("STUDIO_TUNGSTEN")
    return c if c != nil && c != ""
    # the engine binary lives at <tungsten>/apps/studio/bin/studio
    dir_of(dir_of(dir_of(dir_of(System.executable_path)))) + "/bin/tungsten"

  -> compiler_id
    if @compiler_id == nil
      cp = File.expand_path(dir_of(compiler_path()) + "/tungsten-compiler")
      st = File.stat(cp)
      @compiler_id = sha(cp + ":" + st.size.to_s + ":" + st.mtime_ns.to_s)
    @compiler_id

  -> program_source(spec)
    path_join(@root, spec["source"])

  # The text of a program: the source, extracted, patched and appended to as the spec says.
  -> program_text(spec)
    src = File.read(program_source(spec))
    ex = spec["extract"]
    if ex != nil
      mark = ex["marker"]
      mod = ex["name"]
      first = src.index(mark)
      die("no " + mark + " sections in " + spec["source"]) if first == nil
      core = src.slice(0, first)
      at = src.index(mark + mod + "\n")
      die("no section " + mod + " in " + spec["source"]) if at == nil
      rest = src.slice(at + 1, src.size - at - 1)
      stop = rest.size
      nxt = rest.index(mark)
      stop = nxt if nxt != nil && nxt < stop
      get(ex, "stops", []).each ->(sm)
        d = rest.index(sm)
        stop = d if d != nil && d < stop
      src = core + src.slice(at, stop + 1)
    get(spec, "patch", []).each ->(pt)
      die("program patch not found in " + spec["source"] + ": " + pt[0]) if src.index(pt[0]) == nil
      src = src.gsub(pt[0], pt[1])
    src = src + spec["append"] if spec["append"] != nil
    src

  -> program_modified?(spec)
    spec["extract"] != nil || spec["patch"] != nil || spec["append"] != nil

  # Fill in source_sha (the program-and-arguments key) of every program shot, and the frame count of programs
  # that report their own, before resolving.
  -> prepare_programs
    @programs = {}
    @counts = {}
    @pcaps = {}
    cache_path = @build + "/programs/counts.json"
    counts = {}
    counts = JSON.parse(File.read(cache_path)) if File.exist?(cache_path)
    section("shots").each ->(s)
      if s["kind"] == "program"
        spec = s["program"]
        text = program_text(spec)
        parts = [text, compiler_id()]
        get(spec, "data", []).each ->(df)
          parts.push(df + ":" + file_sha(path_join(@root, df)))
        ph = sha(parts.join("\n"))
        run = spec["run"]
        h = sha(ph + "\n" + canon(run) + "\n" + canon(spec["frames"]) + "\n" + canon(get(spec, "link", nil)))
        s["source_sha"] = h
        s["program_dur"] = canon(run).index("{dur}") != nil
        @programs[h] = {"text" => text, "spec" => spec, "prog" => ph}
        cs = get(spec, "count", "dur")
        if cs != "dur"
          ck = sha(ph + "\n" + canon(cs))
          if counts[ck] == nil
            counts[ck] = program_count(h, cs)
            mkdir_p(@build + "/programs")
            write_text(cache_path, JSON.encode(counts))
          @counts[h] = counts[ck]
        if spec["captions"] != nil
          @pcaps[h] = program_captions(h, ph, spec["captions"])
    nil

  # Captions a program writes for its own frames (an SRT file, after running it with the given arguments), as
  # [from ms, to ms, text] from the program's frame 0; cached under the program hash and the arguments.
  -> program_captions(h, ph, cs)
    path = @build + "/programs/captions_" + sha(ph + "\n" + canon(cs)) + ".json"
    return JSON.parse(File.read(path)) if File.exist?(path)
    bin = program_bin(h)
    cmd = shq(bin)
    cs["run"].each ->(a)
      cmd = cmd + " " + shq(expand(a, h, nil, nil, nil))
    f = expand(cs["file"], h, nil, nil, nil)
    die("program captions failed: " + cmd) if !OS.system(cmd + " > /dev/null 2>&1") || !File.exist?(f)
    out = parse_srt(File.read(f))
    mkdir_p(@build + "/programs")
    write_text(path, JSON.encode(out))
    << "program " + h.slice(0, 12) + ": " + out.size.to_s + " captions"
    out

  -> file_sha(path)
    OS.capture("shasum -a 256 " + shq(path)).slice(0, 64)

  -> program_bin_dir(ph)
    @build + "/programs/bin/" + ph

  # Compile a program once (under its program hash). An unmodified source compiles in place, so its relative
  # `use`s resolve; a generated text is written next to its binary (or into the work dir when it links the root).
  -> program_bin(h)
    pr = @programs[h]
    d = program_bin_dir(pr["prog"])
    bin = d + "/scene_bin"
    return bin if File.exist?(bin)
    mkdir_p(d)
    src = program_source(pr["spec"])
    if program_modified?(pr["spec"])
      src = d + "/program.w"
      write_text(src, pr["text"])
    t0 = clock_ms()
    die("program compile failed: " + d + "/compile.log") if !OS.system(shq(compiler_path()) + " -o " + shq(bin + ".part") + " " + shq(src) + " > " + shq(d + "/compile.log") + " 2>&1")
    File.rename(bin + ".part", bin)
    << "program " + pr["prog"].slice(0, 12) + " compiled in " + (clock_ms() - t0).to_s + " ms"
    bin

  -> run_dir(h, dur_ms)
    return @build + "/programs/" + h if dur_ms == nil
    @build + "/programs/" + sha(h + ":" + dur_ms.to_s)

  # The work directory: the root's entries linked (all but the excluded names), so a program that reads its
  # video folder and writes frames into it sees its inputs and writes into the cache.
  -> work_dir(h, dur_ms)
    spec = @programs[h]["spec"]
    w = run_dir(h, dur_ms) + "/work"
    lk = spec["link"]
    return w if lk == nil
    if !File.exist?(w + "/.linked")
      mkdir_p(w)
      ex = get(lk, "exclude", [])
      src = File.expand_path(path_join(@root, get(lk, "from", ".")))
      File.entries(src).each ->(nm)
        if nm != "." && nm != ".." && !ex.include?(nm)
          OS.system("ln -sfn " + shq(src + "/" + nm) + " " + shq(w + "/" + nm))
      write_text(w + "/.linked", "")
    w

  -> expand(t, h, dur_ms, first, last)
    s = t.gsub("{root}", @root).gsub("{dir}", run_dir(h, dur_ms))
    s = s.gsub("{work}", work_dir(h, dur_ms)) if s.index("{work}") != nil
    s = s.gsub("{dur}", ((dur_ms + ~0.0) / ~1000.0).to_s) if dur_ms != nil
    s = s.gsub("{first}", first.to_s).gsub("{last}", last.to_s) if first != nil
    s

  -> program_count(h, cs)
    bin = program_bin(h)
    cmd = shq(bin)
    cs["run"].each ->(a)
      cmd = cmd + " " + shq(expand(a, h, nil, nil, nil))
    out = OS.capture(cmd + " 2>/dev/null").strip.split("\n")
    die("program count failed: " + cmd) if out.size == 0
    n = out[out.size - 1].strip.to_i
    die("program count is not a positive number: " + cmd) if n <= 0
    << "program " + h.slice(0, 12) + ": " + n.to_s + " frames"
    n

  # Path of frame idx of a program item's frames.
  -> program_frame(p, idx)
    h = p["source_sha"]
    prepare_programs() if @programs == nil
    pr = @programs[h]
    die("unknown program " + h.to_s) if pr == nil
    t = expand(pr["spec"]["frames"], h, p["dur_ms"], nil, nil)
    seq_path(dir_of(t), base_of(t), 0, idx)

  # A program frame that exists and ends with its PNG IEND chunk (a run killed mid-write leaves a short file).
  -> frame_complete?(path)
    return false if !File.exist?(path)
    n = File.size(path)
    return false if n < 57
    m = File.mmap(path)
    v = m.as_u8
    ok = v[n - 8] == 73 && v[n - 7] == 69 && v[n - 6] == 78 && v[n - 5] == 68
    m.close
    ok

  # Render the frames of program items that the given segments need and that are not cached: the missing frame
  # indices of each run, in contiguous ranges split over up to `jobs` processes.
  -> ensure_program_frames(r, seg_idxs, jobs)
    v1 = r["tracks"][0]["items"]
    need = {}
    segs = r["segments"]
    iv = r["intervals"]
    seg_idxs.each ->(si)
      s = segs[si]
      # the interval this segment belongs to
      lo = 0
      hi = iv.size - 1
      while lo < hi
        mid = (lo + hi + 1) / 2
        if iv[mid][0] <= s["f0"]
          lo = mid
        else
          hi = mid - 1
      iv[lo][2].each ->(e)
        if e[1] == "V1"
          it = v1[e[0]]
          if it["kind"] == "program"
            p = it["params"]
            key = p["source_sha"] + "|" + get(p, "dur_ms", "").to_s
            if need[key] == nil
              need[key] = [p, {}]
            f = s["f0"]
            while f < s["f0"] + s["n"]
              idx = f - it["f0"] + get(p, "in", 0)
              idx = 0 if idx < 0
              idx = p["count"] - 1 if idx > p["count"] - 1
              need[key][1][idx] = 1
              f += 1
    tasks = []
    need.keys.each ->(key)
      p = need[key][0]
      h = p["source_sha"]
      dm = p["dur_ms"]
      miss = []
      need[key][1].keys.sort.each ->(idx)
        miss.push(idx) if !frame_complete?(program_frame(p, idx))
      if miss.size > 0
        mkdir_p(dir_of(program_frame(p, 0)))
        # contiguous runs, then cut into about `jobs` pieces
        runs = []
        miss.each ->(x)
          if runs.size > 0 && runs[runs.size - 1][1] == x - 1
            runs[runs.size - 1][1] = x
          else
            runs.push([x, x])
        per = (miss.size + jobs - 1) / jobs
        per = 1 if per < 1
        runs.each ->(rg)
          a = rg[0]
          while a <= rg[1]
            b = [rg[1], a + per - 1].min
            tasks.push([h, dm, a, b])
            a = b + 1
    return 0 if tasks.size == 0
    t0 = clock_ms()
    nfr = 0
    ti = 0
    while ti < tasks.size
      procs = []
      while ti < tasks.size && procs.size < jobs
        tk = tasks[ti]
        bin = program_bin(tk[0])
        cmd = shq(bin)
        @programs[tk[0]]["spec"]["run"].each ->(a)
          cmd = cmd + " " + shq(expand(a, tk[0], tk[1], tk[2], tk[3]))
        log = run_dir(tk[0], tk[1]) + "/run." + tk[2].to_s + ".log"
        procs.push(Process.spawn(["/bin/sh", "-c", cmd + " > " + shq(log) + " 2>&1"]))
        nfr += tk[3] - tk[2] + 1
        ti += 1
      bad = 0
      procs.each ->(pr)
        bad += 1 if pr.wait != 0
      die("program run failed (" + bad.to_s + " processes): see " + @build + "/programs/*/run.*.log") if bad > 0
    << "programs: " + nfr.to_s + " frames in " + tasks.size.to_s + " runs, " + (clock_ms() - t0).to_s + " ms"
    nfr

  -> resolve
    prepare_programs() if @programs == nil
    r = Resolver.new(@ep, @cut, @asset_sha, @counts, @pcaps)
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

-> srt_text(r)
  subs = r["tracks"][4]["items"]
  out = []
  n = 1
  subs.each ->(s)
    # the text is laid out by the author (line breaks, speaker labels): written as it is
    out.push(n.to_s + "\n" + srt_time(s["from_ms"]) + " --> " + srt_time(s["to_ms"]) + "\n" + s["text"] + "\n")
    n += 1
  out.join("\n")

# SubRip text -> [[from ms, to ms, text], ...].
-> srt_ms(t)
  h = t.slice(0, 2).to_i
  m = t.slice(3, 2).to_i
  sec = t.slice(6, 2).to_i
  f = t.slice(9, 3).to_i
  ((h * 60 + m) * 60 + sec) * 1000 + f

-> parse_srt(text)
  out = []
  text.gsub("\r", "").split("\n\n").each ->(blk)
    ls = []
    blk.split("\n").each ->(x)
      ls.push(x) if x != ""
    if ls.size >= 3 && ls[1].index(" --> ") != nil
      a = srt_ms(ls[1].slice(0, 12))
      b = srt_ms(ls[1].slice(17, 12))
      body = ls[2]
      k = 3
      while k < ls.size
        body = body + "\n" + ls[k]
        k += 1
      out.push([a, b, body])
  out

-> chapters_text(r)
  out = ""
  r["tracks"][5]["items"].each ->(m)
    out = out + chapter_time(m["sec"]) + " " + m["title"] + "\n"
  out
