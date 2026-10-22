# studio/resolve — the source document (episode.json, authored) -> the resolved timeline (derived).
#
# TIMELINE.md §3. The resolver is a pure function: integer milliseconds in, integer frames and samples out.
#   1. lines: each line's speech window from its anchor (previous line's end + gap_ms, + nudge_ms). Others see a
#      line at its nudged position when it ripples, at its un-nudged position when it does not.
#   2. shots: start = anchor (a line edge + ms, the start, or another shot); end = the next shot's start. The
#      picture boundary is snap(start): round half up to a frame.
#   3. items: parameters in item-local time (phrases, shakes, supers become ms from the item's exact start) and a
#      recipe hash over kind, parameters, dependency hashes and the kind's renderer version.
#   4. intervals: the edit decision table, constant active sets; segments: <= 48-frame runs aligned to each
#      interval's start, keyed by what they show in item-local time.

SEG_MAX = 48
# The compositor (transitions, fades, packing) is part of every frame key.
COMPOSITOR = 3
# Renderer versions, per kind: bump one when its pixels change, and only that kind's segments re-render.
RENDERER = {"still" => 3, "clip" => 3, "frames" => 2, "program" => 1, "card" => 3, "black" => 1, "group" => 3, "fade_out" => 1}
# Encoder settings in force (the segment key covers them): set from encoder_spec by the project.
ENCODER = {"id" => "vt:hevc:q0.750000:reorder:bt709-1-1-1:tv:left:420v"}
# The grade implementation in force (lib/grade.w), set by the project. It enters the recipe of every kind that is
# graded, so frame and segment keys say which implementation made the pixels; the CPU reference adds nothing (keys
# made before the Metal grade existed stay valid).
GRADE = {"id" => "cpu"}
GRADED = {"still" => true, "clip" => true, "group" => true}

# Normalise a word as tools/cues.py does: lower case, keep only a-z0-9.
-> norm_word(w)
  s = w.downcase
  out = ""
  i = 0
  n = s.size
  while i < n
    c = s.byte_at(i)
    if (c >= 97 && c <= 122) || (c >= 48 && c <= 57)
      out = out + c.chr
    i += 1
  out

-> split_words(text)
  out = []
  text.split(" ").each ->(w)
    out.push(w) if w != ""
  out

+ Resolver
  ro :out, :num, :den, :sr, :frames

  -> new(@ep, @cut_name, @assets_sha)
    @cut = @ep["cuts"][@cut_name]
    die("no cut " + @cut_name.to_s) if @cut == nil
    @num = @cut["rate"][0]
    @den = @cut["rate"][1]
    @sr = @cut["sr"]
    @seed = get(@ep, "seed", 1)
    @assets = @ep["assets"]
    @lines = {}
    @line_list = []
    @shot_ms = {}
    @out = nil

  -> asset(key)
    a = @assets[key]
    die("unknown asset " + key.to_s) if a == nil
    a

  -> asset_sha(key)
    s = nil
    s = @assets_sha[key] if @assets_sha != nil
    s = asset(key)["sha256"] if s == nil
    s

  # ------------------------------------------------------------------------------------------ 1. lines
  -> resolve_lines
    @ep["lines"].each ->(l)
      take = asset(l["take"])
      sp = take["speech_ms"]
      lead = sp[0]
      tail = sp[1]
      after = l["after"]
      ref = after["ref"]
      base = 0
      if ref != "start"
        r = @lines[ref]
        die("line " + l["id"] + ": after unknown or later line " + ref.to_s) if r == nil
        base = r["seen_end"]
      nominal = base + after["gap_ms"]
      actual = nominal + get(l, "nudge_ms", 0)
      len = tail - lead
      rl = {"id" => l["id"], "spk" => l["spk"], "text" => l["text"], "take" => l["take"], "lead" => lead,
            "start" => actual, "end" => actual + len, "nominal_start" => nominal, "nominal_end" => nominal + len,
            "words_ms" => get(take, "words_ms", [])}
      if get(l, "ripple", true)
        rl["seen_start"] = actual
        rl["seen_end"] = actual + len
      else
        rl["seen_start"] = nominal
        rl["seen_end"] = nominal + len
      @lines[l["id"]] = rl
      @line_list.push(rl)

  # An anchor in ms: {ref: line|start, edge: start|end, ms} or {shot: id, ms}.
  -> anchor_ms(a)
    die("missing anchor") if a == nil
    off = get(a, "ms", 0)
    if a["shot"] != nil
      s = @shot_ms[a["shot"]]
      die("anchor on unknown shot " + a["shot"].to_s) if s == nil
      return s + off
    ref = get(a, "ref", "start")
    return off if ref == "start"
    r = @lines[ref]
    die("anchor on unknown line " + ref.to_s) if r == nil
    if get(a, "edge", "start") == "end"
      return r["seen_end"] + off
    r["seen_start"] + off

  # Words spoken in [t0 - 500, t1) as (absolute ms, word), the window tools/cues.py uses for a shot.
  -> words_between(t0, t1)
    out = []
    @line_list.each ->(l)
      if l["start"] >= t0 - 500 && l["start"] < t1
        ws = l["words_ms"]
        at = l["start"] - l["lead"]
        words = split_words(l["text"])
        k = 0
        while k < words.size
          w = ws.size > 0 ? ws[[k, ws.size - 1].min] : (l["start"] - at)
          out.push([at + w, norm_word(words[k])])
          k += 1
    out

  # A phrase anchor relative to an item: ms from the item's exact start at which the phrase is spoken.
  -> phrase_local(phrase, t0, t1, default)
    return default if phrase == nil
    words = words_between(t0, t1)
    target = []
    split_words(phrase).each ->(w)
      nw = norm_word(w)
      target.push(nw) if nw != ""
    i = 0
    while i + target.size <= words.size
      ok = true
      j = 0
      while j < target.size && ok
        ok = false if words[i + j][1] != target[j]
        j += 1
      return words[i][0] - t0 if ok
      i += 1
    die("phrase not spoken in its shot: " + phrase.to_s)

  # ------------------------------------------------------------------------------------------ 2. shots
  -> resolve
    resolve_lines()
    shots = @ep["shots"]
    starts = []
    shots.each ->(s)
      t = anchor_ms(s["at"])
      @shot_ms[s["id"]] = t
      starts.push(t)
    end_ms = anchor_ms(@cut["end"])
    i = 1
    while i < starts.size
      die("shot " + shots[i]["id"] + " starts before " + shots[i - 1]["id"]) if starts[i] <= starts[i - 1]
      i += 1
    @frames = snap_ms(end_ms, @num, @den)
    total_samples = samples_of_frames(@frames, @sr, @num, @den)

    # shake times (sfx cues flagged shake) and supers, absolute ms
    shakes = []
    supers = []
    @ep["cues"].each ->(c)
      if c["kind"] == "sfx" && get(c, "shake", false)
        shakes.push(anchor_ms(c["at"]))
      if c["kind"] == "super"
        supers.push([anchor_ms(c["at"]), c["ms"], c["text"]])

    v1 = []
    i = 0
    while i < shots.size
      s = shots[i]
      t0 = starts[i]
      t1 = i + 1 < shots.size ? starts[i + 1] : end_ms
      f0 = snap_ms(t0, @num, @den)
      f1 = i + 1 < shots.size ? snap_ms(t1, @num, @den) : @frames
      die("shot " + s["id"] + " is shorter than a frame") if f1 <= f0
      item = item_for(s, t0, t1, shakes, supers)
      item["f0"] = f0
      item["f1"] = f1
      item["t0_ms"] = t0
      item["t1_ms"] = t1
      item["flicks0"] = flicks_of_ms(t0)
      v1.push(item)
      i += 1

    v4 = []
    @ep["cues"].each ->(c)
      if c["kind"] == "fade_out"
        n = c["frames"]
        fe = @frames
        if c["before"] != "end"
          fe = nil
          v1.each ->(it)
            fe = it["f0"] if it["id"] == c["before"]
        die("fade_out before unknown shot") if fe == nil
        p = {"frames" => n, "power" => to_f(get(c, "power", ~1.0))}
        v4.push({"id" => c["id"], "kind" => "fade_out", "f0" => fe - n, "f1" => fe, "params" => p,
                 "recipe" => hash_of({"kind" => "fade_out", "v" => RENDERER["fade_out"], "p" => p})})

    a1 = audio_lines()
    cues_out = audio_cues(end_ms)
    subs = subtitles()
    markers = chapters(v1)
    iv = intervals(v1, v4)
    segs = segments(iv)

    @out = {"schema" => "studio.resolved/1", "episode" => @ep["id"], "cut" => @cut_name,
            "rate" => [@num, @den], "sr" => @sr, "w" => @cut["w"], "h" => @cut["h"],
            "tc_start" => get(@cut, "tc_start", "00:00:00:00"), "frames" => @frames, "samples" => total_samples,
            "end_ms" => end_ms, "seed" => @seed, "encoder" => ENCODER["id"],
            "tracks" => [{"id" => "V1", "kind" => "video", "items" => v1},
                         {"id" => "V4", "kind" => "video", "role" => "fades", "items" => v4},
                         {"id" => "A1", "kind" => "audio", "role" => "narration", "items" => a1},
                         {"id" => "A3", "kind" => "audio", "role" => "cues", "items" => cues_out},
                         {"id" => "T1", "kind" => "subtitle", "items" => subs},
                         {"id" => "M", "kind" => "marker", "items" => markers}],
            "intervals" => iv, "segments" => segs}
    @out

  # ------------------------------------------------------------------------------------------ 3. items
  -> style(name)
    return nil if name == nil
    st = @ep["styles"][name]
    die("unknown style " + name.to_s) if st == nil
    st

  -> item_for(s, t0, t1, shakes, supers)
    kind = s["kind"]
    dur = t1 - t0
    p = {"dur_ms" => dur}
    deps = []
    if kind == "still" || kind == "clip"
      p["src"] = s["src"]
      deps.push(asset_sha(s["src"]))
      p["camera"] = s["camera"]
      p["fx"] = get(s, "fx", [])
      p["style"] = style(s["style"])
      p["bar"] = s["bar"]
      if s["wipe"] != nil
        w = s["wipe"]
        deps.push(asset_sha(w["src"]))
        at = phrase_local(get(w["at"], "phrase", nil), t0, t1, get(w, "default_ms", 6000))
        p["wipe"] = {"src" => w["src"], "at_ms" => at, "ms" => w["ms"]}
      if s["clip"] != nil
        c = s["clip"]
        ca = asset(c["src"])
        deps.push(asset_sha(c["src"]))
        at = 0
        at = phrase_local(c["at"]["phrase"], t0, t1, 0) if c["at"] != nil
        p["clip"] = {"src" => c["src"], "count" => ca["count"], "fps" => c["fps"], "min_speed" => c["min_speed"],
                     "max_speed" => c["max_speed"], "blend" => c["blend"], "xf_in_ms" => c["xf_in_ms"], "at_ms" => at}
      # shakes and supers near the item, in item-local ms (they may fall before 0 or after dur: the item is
      # also drawn as the outgoing side of the next item's dissolve)
      sh = []
      shakes.each ->(t)
        sh.push(t - t0) if t >= t0 - 1000 && t < t1 + 2000
      p["shakes"] = sh
      su = []
      supers.each ->(x)
        su.push([x[0] - t0, x[1], x[2]]) if x[0] + x[1] > t0 && x[0] < t1 + 2000
      p["supers"] = su
    elsif kind == "frames"
      # a frame sequence shows frame k at local frame k: its duration is not part of what it draws
      a = asset(s["src"])
      deps.push(asset_sha(s["src"]))
      p = {"src" => s["src"], "count" => a["count"]}
    elsif kind == "program"
      die("program shot " + s["id"] + " has no source hash (Project.prepare_programs)") if s["source_sha"] == nil
      p["program"] = s["program"]
      p["source_sha"] = s["source_sha"]
      # frames the program renders: round(duration x rate), as the legacy scene runner counted them, so a
      # one-frame snap of the cut does not change the program's output
      p["count"] = (dur * @num * 2 + 1000 * @den) / (2000 * @den)
      deps.push(s["source_sha"])
      get(s, "deps", []).each ->(d)
        deps.push(asset_sha(d))
    elsif kind == "card"
      p = {"layout" => s["layout"], "style" => style(s["style"])}
    elsif kind == "group"
      kids = []
      s["children"].each ->(ch)
        deps.push(asset_sha(ch["src"]))
        at = 0
        at = phrase_local(ch["at"]["phrase"], t0, t1, 0) if ch["at"] != nil
        kids.push({"id" => ch["id"], "src" => ch["src"], "label" => ch["label"], "pane" => ch["pane"], "at_ms" => at})
      p["layout"] = s["layout"]
      p["children"] = kids
      p["camera"] = s["camera"]
      p["style"] = style(s["style"])
      p["bar"] = s["bar"]
    elsif kind == "black"
      p = {}
    else
      die("unknown shot kind " + kind.to_s)
    deps = deps.sort
    rh = {"kind" => kind, "v" => RENDERER[kind], "id" => s["id"], "seed" => @seed, "p" => p, "deps" => deps}
    rh["grade"] = GRADE["id"] if GRADED[kind] == true && GRADE["id"] != "cpu"
    recipe = hash_of(rh)
    {"id" => s["id"], "kind" => kind, "params" => p, "trans_in" => get(s, "trans_in", {"kind" => "cut", "frames" => 0}),
     "recipe" => recipe, "deps" => deps}

  # ------------------------------------------------------------------------------------------ audio, subtitles
  -> audio_lines
    out = []
    @line_list.each ->(l)
      s0 = samples_of_ms(l["start"] - l["lead"], @sr)
      out.push({"id" => l["id"], "spk" => l["spk"], "src" => l["take"], "s0" => s0, "speech_ms" => [l["start"], l["end"]],
                "nominal_ms" => l["nominal_start"], "gain_db" => 0, "flicks" => flicks_of_ms(l["start"])})
    out

  -> audio_cues(end_ms)
    out = []
    @ep["cues"].each ->(c)
      k = c["kind"]
      if k == "sfx"
        t = anchor_ms(c["at"])
        out.push({"id" => c["id"], "kind" => k, "src" => c["src"], "name" => c["name"], "s0" => samples_of_ms(t, @sr),
                  "gain_db" => c["gain_db"], "filter" => c["filter"]})
      elsif k == "amb" || k == "music"
        a = anchor_ms(c["from"])
        b = anchor_ms(c["to"])
        o = {"id" => c["id"], "kind" => k, "src" => c["src"], "name" => c["name"], "s0" => samples_of_ms(a, @sr),
             "s1" => samples_of_ms(b, @sr), "gain_db" => c["gain_db"]}
        o["fade_in_ms"] = c["fade_in_ms"] if c["fade_in_ms"] != nil
        o["fade_out_ms"] = c["fade_out_ms"] if c["fade_out_ms"] != nil
        out.push(o)
      elsif k == "audio"
        t = anchor_ms(c["at"])
        out.push({"id" => c["id"], "kind" => k, "src" => c["src"], "s0" => samples_of_ms(t, @sr), "gain_db" => c["gain_db"],
                  "norm" => c["norm"], "fade_in_ms" => c["fade_in_ms"], "fade_out_ms" => c["fade_out_ms"]})
    out

  # SubRip cues, as tools/srt.py built them: sentence-ish chunks timed by the take's word starts.
  -> subtitles
    out = []
    labels = {"ARCHIMEDES" => 1, "ERATOSTHENES" => 1, "HIERON" => 1, "MARCELLUS" => 1, "SOLDIER" => 1, "CICERO" => 1}
    @line_list.each ->(l)
      words = split_words(l["text"])
      at = l["start"] - l["lead"]
      ws = []
      l["words_ms"].each ->(w)
        ws.push(at + w)
      aligned = ws.size >= words.size
      chunks = []
      cur = []
      words.each ->(w)
        cur.push(w)
        ln = cur.join(" ").size
        last = w.slice(w.size - 1, 1)
        if (ln > 76 && ".,;—?!".include?(last)) || (ln >= 40 && ".?!".include?(last))
          chunks.push(cur)
          cur = []
      chunks.push(cur) if cur.size > 0
      total = 0
      chunks.each ->(c)
        total += c.join(" ").size
      t = l["start"]
      wi = 0
      ci = 0
      while ci < chunks.size
        c = chunks[ci]
        d = (l["end"] - l["start"]) * c.join(" ").size / total
        if aligned
          t = ci == 0 ? l["start"] : [t, ws[wi]].max
          nxt = ci + 1 < chunks.size ? ws[wi + c.size] : l["end"]
          d = [500, nxt - t].max
        wi += c.size
        txt = c.join(" ")
        txt = "\[" + l["spk"] + "\] " + txt if labels[l["spk"]] != nil && ci == 0
        out.push({"line" => l["id"], "from_ms" => t, "to_ms" => t + d, "text" => txt})
        t += d
        ci += 1
    get(@ep, "captions", []).each ->(c)
      t0 = anchor_ms(c["at"])
      out.push({"line" => nil, "from_ms" => t0 + c["from_ms"], "to_ms" => t0 + c["to_ms"], "text" => c["text"]})
    out

  -> chapters(v1)
    out = []
    get(@ep, "markers", []).each ->(m)
      if m["kind"] == "chapter"
        f = nil
        v1.each ->(it)
          f = it["f0"] if it["id"] == m["at"]
        die("chapter at unknown shot " + m["at"].to_s) if f == nil
        sec = f * @den / @num
        out.push({"id" => m["id"], "title" => m["title"], "frame" => f, "sec" => sec, "tc" => timecode(f, @num, @den)})
    out

  # ------------------------------------------------------------------------------------------ 4. intervals
  # Entries are [item index on its track, track, role]; an interval is [f0, f1, entries].
  -> intervals(v1, v4)
    cuts = {}
    v1.each ->(it)
      cuts[it["f0"]] = 1
      cuts[it["f1"]] = 1
      tr = it["trans_in"]
      n = get(tr, "frames", 0)
      if n > 0
        e = [it["f0"] + n, it["f1"]].min
        cuts[e] = 1
    v4.each ->(it)
      cuts[it["f0"]] = 1
      cuts[it["f1"]] = 1
    bounds = cuts.keys.sort
    out = []
    bi = 0
    vi = 0
    while bi + 1 < bounds.size
      a = bounds[bi]
      b = bounds[bi + 1]
      while vi + 1 < v1.size && v1[vi + 1]["f0"] <= a
        vi += 1
      it = v1[vi]
      ents = []
      tr = it["trans_in"]
      n = get(tr, "frames", 0)
      in_trans = n > 0 && a < it["f0"] + n
      if in_trans && tr["kind"] == "dissolve" && vi > 0
        ents.push([vi - 1, "V1", "out"])
        ents.push([vi, "V1", "dissolve:" + n.to_s])
      elsif in_trans && tr["kind"] == "fadein"
        ents.push([vi, "V1", "fadein:" + n.to_s])
      else
        ents.push([vi, "V1", "main"])
      k = 0
      while k < v4.size
        ents.push([k, "V4", "fade"]) if v4[k]["f0"] <= a && a < v4[k]["f1"]
        k += 1
      out.push([a, b, ents])
      bi += 1
    @v1 = v1
    @v4 = v4
    out

  -> entry_item(e)
    return @v1[e[0]] if e[1] == "V1"
    @v4[e[0]]

  # Frame key of frame f in an interval (TIMELINE.md §3.3): what the frame shows, in item-local time.
  -> frame_key(f, ents)
    parts = [COMPOSITOR, @cut["w"], @cut["h"], @num, @den]
    ents.each ->(e)
      it = entry_item(e)
      parts.push([it["recipe"], f - it["f0"], e[2]])
    hash_of(parts)

  # Segments: runs of <= SEG_MAX frames aligned to each interval's start. A segment's key covers the encoder and
  # the frame keys of its frames; since those are fixed by the entries' recipes, roles and local offsets, the key
  # hashes exactly that (and stays equal to hashing the frame keys one by one).
  -> segments(iv)
    out = []
    iv.each ->(x)
      a = x[0]
      b = x[1]
      s = a
      while s < b
        n = [SEG_MAX, b - s].min
        parts = [ENCODER["id"], COMPOSITOR, @cut["w"], @cut["h"], @num, @den, n]
        names = []
        x[2].each ->(e)
          it = entry_item(e)
          parts.push([it["recipe"], s - it["f0"], e[2]])
          names.push(it["id"])
        out.push({"f0" => s, "n" => n, "key" => hash_of(parts), "items" => names})
        s += n
    out
