# studio/resolve — the source document (episode.json, authored) -> the resolved timeline (derived).
#
# TIMELINE.md §3. The resolver is a pure function: integer milliseconds and frames in, integer frames and samples
# out. Every instant is held in flicks (1/705,600,000 s), which are exact for milliseconds, every common frame rate
# and every audio rate, so an anchor may add milliseconds and frames freely.
#   1. lines: each line's speech window from its anchor (previous line's end, the start, or a shot) + gap_ms,
#      + nudge_ms. Others see a line at its nudged position when it ripples, at its un-nudged position when not.
#   2. shots: start = anchor (a line edge or phrase + ms, the start, or another shot's start or end + ms + frames);
#      end = the next shot's start. The picture boundary is snap(start): round half up to a frame. A shot with an
#      explicit length (`frames`, or `"program"`: its program's frame count) also has an end edge to anchor on.
#      Lines and shots resolve lazily, so either may anchor on the other.
#   3. items: parameters in item-local time (phrases, shakes, overlays become ms from the item's exact start) and a
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
FL_MS = 705600
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

# words[a...b] joined by single spaces.
-> join_words(words, a, b)
  out = ""
  i = a
  while i < b
    out = out + " " if i > a
    out = out + words[i]
    i += 1
  out

# Index of the first word of `phrase` in `words` (normalised), or -1.
-> find_phrase(words, phrase)
  target = []
  split_words(phrase).each ->(w)
    nw = norm_word(w)
    target.push(nw) if nw != ""
  i = 0
  while i + target.size <= words.size
    ok = true
    j = 0
    while j < target.size && ok
      ok = false if norm_word(words[i + j]) != target[j]
      j += 1
    return i if ok
    i += 1
  -1

+ Resolver
  ro :out, :num, :den, :sr, :frames

  -> new(@ep, @cut_name, @assets_sha, @counts, @pcaps)
    @cut = @ep["cuts"][@cut_name]
    die("no cut " + @cut_name.to_s) if @cut == nil
    @num = @cut["rate"][0]
    @den = @cut["rate"][1]
    @fpf = FLICKS * @den / @num
    @sr = @cut["sr"]
    @seed = get(@ep, "seed", 1)
    @assets = @ep["assets"]
    @lines = {}
    @line_src = {}
    @line_list = []
    @shot_src = {}
    @shot_fl = {}
    @busy = {}
    @out = nil

  # A cut may carry its own lines, shots, cues, captions and markers; otherwise the episode's are used.
  -> section(k)
    v = @cut[k]
    v = @ep[k] if v == nil
    v = [] if v == nil
    v

  -> asset(key)
    a = @assets[key]
    die("unknown asset " + key.to_s) if a == nil
    a

  -> asset_sha(key)
    s = nil
    s = @assets_sha[key] if @assets_sha != nil
    s = asset(key)["sha256"] if s == nil
    s

  -> ms_of(fl)
    q = fl / FL_MS
    q -= 1 if fl % FL_MS != 0 && fl < 0
    q

  -> samples_of_fl(fl)
    fl / (FLICKS / @sr)

  # ------------------------------------------------------------------------------------------ 1. lines
  -> line(id)
    r = @lines[id]
    return r if r != nil
    l = @line_src[id]
    die("unknown line " + id.to_s) if l == nil
    die("anchor cycle through line " + id.to_s) if @busy[id] != nil
    @busy[id] = 1
    take = asset(l["take"])
    sp = take["speech_ms"]
    lead = sp[0]
    tail = sp[1]
    after = l["after"]
    base = 0
    if after["shot"] != nil
      base = anchor_fl(after)
    elsif get(after, "ref", "start") != "start"
      base = line(after["ref"])["seen_end_fl"]
    nominal = base + get(after, "gap_ms", 0) * FL_MS
    actual = nominal + get(l, "nudge_ms", 0) * FL_MS
    len = (tail - lead) * FL_MS
    rl = {"id" => l["id"], "spk" => l["spk"], "text" => l["text"], "take" => l["take"], "lead" => lead,
          "start_fl" => actual, "end_fl" => actual + len, "nominal_fl" => nominal,
          "start" => ms_of(actual), "end" => ms_of(actual + len), "nominal_start" => ms_of(nominal),
          "words_ms" => get(take, "words_ms", []), "words_end_ms" => get(take, "words_end_ms", []),
          "cc" => l["cc"], "gain_db" => get(l, "gain_db", 0)}
    if get(l, "ripple", true)
      rl["seen_start_fl"] = actual
      rl["seen_end_fl"] = actual + len
    else
      rl["seen_start_fl"] = nominal
      rl["seen_end_fl"] = nominal + len
    @busy.delete(id)
    @lines[id] = rl
    rl

  -> resolve_lines
    section("lines").each ->(l)
      @line_src[l["id"]] = l
    section("lines").each ->(l)
      @line_list.push(line(l["id"]))

  # ------------------------------------------------------------------------------------------ anchors
  # An anchor, in flicks: {ref: line|start, edge: start|end, phrase, ms, frames} or {shot: id, edge, ms, frames}.
  -> anchor_fl(a)
    die("missing anchor") if a == nil
    off = get(a, "ms", 0) * FL_MS + get(a, "frames", 0) * @fpf
    if a["shot"] != nil
      return shot_edge_fl(a["shot"], get(a, "edge", "start")) + off
    ref = get(a, "ref", "start")
    return off if ref == "start"
    r = line(ref)
    if a["phrase"] != nil
      words = split_words(r["text"])
      k = find_phrase(words, a["phrase"])
      die("phrase not in line " + ref + ": " + a["phrase"]) if k < 0
      ws = r["words_ms"]
      die("line " + ref + " has no word times for its phrase") if ws.size == 0
      w = ws[[k, ws.size - 1].min]
      return r["seen_start_fl"] + (w - r["lead"]) * FL_MS + off
    if get(a, "edge", "start") == "end"
      return r["seen_end_fl"] + off
    r["seen_start_fl"] + off

  -> shot_start_fl(id)
    t = @shot_fl[id]
    return t if t != nil
    s = @shot_src[id]
    die("anchor on unknown shot " + id.to_s) if s == nil
    die("anchor cycle through shot " + id.to_s) if @busy["shot:" + id] != nil
    @busy["shot:" + id] = 1
    t = anchor_fl(s["at"])
    @busy.delete("shot:" + id)
    @shot_fl[id] = t
    t

  # The explicit length of a shot in frames (nil when it simply runs to the next shot).
  -> shot_frames(s)
    n = s["frames"]
    return nil if n == nil
    if n == "program"
      c = nil
      c = @counts[s["source_sha"]] if @counts != nil
      die("shot " + s["id"] + ": its program's frame count is unknown") if c == nil
      return c
    n

  -> shot_edge_fl(id, edge)
    t = shot_start_fl(id)
    return t if edge != "end"
    n = shot_frames(@shot_src[id])
    die("shot " + id.to_s + " has no explicit length to anchor on its end") if n == nil
    t + n * @fpf

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
    shots = section("shots")
    shots.each ->(s)
      @shot_src[s["id"]] = s
    resolve_lines()
    starts = []
    shots.each ->(s)
      starts.push(shot_start_fl(s["id"]))
    end_fl = anchor_fl(@cut["end"])
    i = 1
    while i < starts.size
      die("shot " + shots[i]["id"] + " starts before " + shots[i - 1]["id"]) if starts[i] <= starts[i - 1]
      i += 1
    @frames = snap_flicks(end_fl, @num, @den)
    total_samples = samples_of_frames(@frames, @sr, @num, @den)

    # shake times (sfx cues flagged shake) and timed overlays (supers), absolute flicks
    shakes = []
    overlays = []
    section("cues").each ->(c)
      if c["kind"] == "sfx" && get(c, "shake", false)
        shakes.push(anchor_fl(c["at"]))
      if c["kind"] == "overlay"
        overlays.push([anchor_fl(c["at"]), c["ms"], c])

    v1 = []
    i = 0
    while i < shots.size
      s = shots[i]
      t0 = starts[i]
      t1 = i + 1 < shots.size ? starts[i + 1] : end_fl
      f0 = snap_flicks(t0, @num, @den)
      f1 = i + 1 < shots.size ? snap_flicks(t1, @num, @den) : @frames
      die("shot " + s["id"] + " is shorter than a frame") if f1 <= f0
      item = item_for(s, t0, t1, shakes, overlays)
      item["f0"] = f0
      item["f1"] = f1
      item["t0_ms"] = ms_of(t0)
      item["t1_ms"] = ms_of(t1)
      item["flicks0"] = t0
      v1.push(item)
      i += 1

    v4 = []
    section("cues").each ->(c)
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
    cues_out = audio_cues()
    subs = subtitles()
    # captions a program writes for its own frames, on the shots that ask for them
    i = 0
    while i < shots.size
      s = shots[i]
      if get(s, "captions_from_program", false)
        pc = nil
        pc = @pcaps[s["source_sha"]] if @pcaps != nil
        die("shot " + s["id"] + ": its program wrote no captions") if pc == nil
        t0 = starts[i] - get(s, "in", 0) * @fpf
        pc.each ->(c)
          subs.push({"line" => nil, "from_ms" => ms_of(t0 + c[0] * FL_MS + FL_MS / 2), "to_ms" => ms_of(t0 + c[1] * FL_MS + FL_MS / 2), "text" => c[2]})
      i += 1
    subs = subs.sort ->(x, y)
      x["from_ms"] <=> y["from_ms"]
    markers = chapters(v1)
    iv = intervals(v1, v4)
    segs = segments(iv)

    @out = {"schema" => "studio.resolved/1", "episode" => @ep["id"], "cut" => @cut_name,
            "rate" => [@num, @den], "sr" => @sr, "w" => @cut["w"], "h" => @cut["h"],
            "tc_start" => get(@cut, "tc_start", "00:00:00:00"), "frames" => @frames, "samples" => total_samples,
            "end_ms" => ms_of(end_fl), "seed" => @seed, "encoder" => ENCODER["id"],
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

  # Shakes and timed overlays near an item, in item-local ms (they may fall before 0 or after dur: the item is
  # also drawn as the outgoing side of the next item's dissolve).
  -> near(p, kind, t0, t1, shakes, overlays)
    sh = []
    shakes.each ->(t)
      sh.push(ms_of(t - t0)) if t >= t0 - 1000 * FL_MS && t < t1 + 2000 * FL_MS
    p["shakes"] = sh
    su = []
    overlays.each ->(x)
      c = x[2]
      if get(c, "on", ["still", "clip"]).include?(kind)
        if x[0] + x[1] * FL_MS > t0 && x[0] < t1 + 2000 * FL_MS
          su.push([ms_of(x[0] - t0), x[1], {"el" => c["el"], "reveal_ms" => get(c, "reveal_ms", 0), "fade_ms" => get(c, "fade_ms", 0),
                                           "stroke_min_alpha" => get(c, "stroke_min_alpha", 0)}])
    p["overlays"] = su
    p

  -> item_for(s, t0f, t1f, shakes, overlays)
    kind = s["kind"]
    t0 = ms_of(t0f)
    t1 = ms_of(t1f)
    dur = t1 - t0
    p = {"dur_ms" => dur}
    deps = []
    if kind == "still" || kind == "clip"
      p["src"] = s["src"]
      deps.push(asset_sha(s["src"]))
      p["camera"] = s["camera"]
      p["fx"] = get(s, "fx", [])
      p["style"] = style(s["style"])
      p["matte"] = s["matte"]
      if s["wipe"] != nil
        w = s["wipe"]
        deps.push(asset_sha(w["src"]))
        at = phrase_local(get(w["at"], "phrase", nil), t0, t1, get(w, "default_ms", 6000))
        p["wipe"] = {"src" => w["src"], "at_ms" => at, "ms" => w["ms"]}
      if s["clip"] != nil
        c = s["clip"]
        parts = []
        c["parts"].each ->(pt)
          ca = asset(pt["src"])
          deps.push(asset_sha(pt["src"]))
          parts.push({"src" => pt["src"], "first" => get(pt, "first", 0), "count" => get(pt, "count", ca["count"] - get(pt, "first", 0))})
        at = 0
        at = phrase_local(c["at"]["phrase"], t0, t1, 0) if c["at"] != nil
        p["clip"] = {"parts" => parts, "xf" => get(c, "xf", 0), "fps" => get(c, "fps", @num / @den), "at_ms" => at,
                     "speed" => c["speed"], "add_ms" => get(c, "add_ms", 0), "blend" => get(c, "blend", true),
                     "pre" => c["pre"], "zoom" => c["zoom"], "hold" => c["hold"]}
      near(p, kind, t0f, t1f, shakes, overlays)
    elsif kind == "frames"
      # a frame sequence shows frame k at local frame k: its duration is not part of what it draws
      a = asset(s["src"])
      deps.push(asset_sha(s["src"]))
      p = {"src" => s["src"], "count" => a["count"]}
      p["in"] = s["in"] if s["in"] != nil
    elsif kind == "program"
      die("program shot " + s["id"] + " has no source hash (Project.prepare_programs)") if s["source_sha"] == nil
      # frames the program renders: its own count, or round(duration x rate) (the legacy scene runner's count), so
      # a one-frame snap of the cut does not change the program's output
      n = nil
      n = @counts[s["source_sha"]] if @counts != nil
      n = (dur * @num * 2 + 1000 * @den) / (2000 * @den) if n == nil
      p = {"source_sha" => s["source_sha"], "count" => n}
      p["in"] = s["in"] if s["in"] != nil
      p["dur_ms"] = dur if get(s, "program_dur", false)
      deps.push(s["source_sha"])
      get(s, "deps", []).each ->(d)
        deps.push(asset_sha(d))
    elsif kind == "card"
      p = {"bg" => s["bg"], "elements" => s["elements"]}
    elsif kind == "group"
      panes = []
      s["panes"].each ->(ch)
        deps.push(asset_sha(ch["src"]))
        at = 0
        at = phrase_local(ch["at"]["phrase"], t0, t1, get(ch, "default_ms", 0)) if ch["at"] != nil
        q = {}
        ch.keys.each ->(k)
          q[k] = ch[k] if k != "at" && k != "default_ms"
        q["at_ms"] = at
        panes.push(q)
      p["panes"] = panes
      p["style"] = style(s["style"])
      p["matte"] = s["matte"]
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
      s0 = samples_of_fl(l["start_fl"] - l["lead"] * FL_MS)
      it = {"id" => l["id"], "spk" => l["spk"], "src" => l["take"], "s0" => s0, "speech_ms" => [l["start"], l["end"]],
            "nominal_ms" => l["nominal_start"], "gain_db" => l["gain_db"], "flicks" => l["start_fl"]}
      out.push(it)
    out

  -> audio_cues
    out = []
    section("cues").each ->(c)
      k = c["kind"]
      if k == "sfx"
        t = anchor_fl(c["at"])
        out.push({"id" => c["id"], "kind" => k, "src" => c["src"], "name" => c["name"], "s0" => samples_of_fl(t),
                  "gain_db" => c["gain_db"], "filter" => c["filter"]})
      elsif k == "amb" || k == "music"
        a = anchor_fl(c["from"])
        b = anchor_fl(c["to"])
        o = {"id" => c["id"], "kind" => k, "src" => c["src"], "name" => c["name"], "s0" => samples_of_fl(a),
             "s1" => samples_of_fl(b), "gain_db" => c["gain_db"]}
        o["fade_in_ms"] = c["fade_in_ms"] if c["fade_in_ms"] != nil
        o["fade_out_ms"] = c["fade_out_ms"] if c["fade_out_ms"] != nil
        out.push(o)
      elsif k == "audio"
        t = anchor_fl(c["at"])
        o = {"id" => c["id"], "kind" => k, "src" => c["src"], "s0" => samples_of_fl(t), "gain_db" => c["gain_db"],
             "norm" => c["norm"], "fade_in_ms" => c["fade_in_ms"], "fade_out_ms" => c["fade_out_ms"]}
        # `until`: the cue is cut (padded with nothing) at this anchor
        o["s1"] = samples_of_fl(anchor_fl(c["until"])) if c["until"] != nil
        out.push(o)
    out

  # SubRip cues from the lines' caption chunks. A chunk is {w: [first word, end word), text}: its text is laid out
  # by the author (wrapping, speaker labels); its times come from the take's word times, so it follows a nudge or
  # a re-take. Timing rules (cut "caption_timing"):
  #   starts: a chunk runs from its first word's start (the line's start for the first) to the next chunk's first
  #           word (the line's end for the last), at least min_ms; a take without word times splits the line's
  #           time by characters (tools/srt.py of the first Profiles episodes)
  #   spans:  a chunk runs from its first word's start to its last word's end, held to gap_ms before the next
  #           chunk, the last one tail_ms longer
  -> subtitles
    out = []
    cfg = get(@cut, "caption_timing", {})
    mode = get(cfg, "timing", "starts")
    @line_list.each ->(l)
      cc = l["cc"]
      if cc != nil && cc.size > 0
        words = split_words(l["text"])
        at = l["start"] - l["lead"]
        ws = []
        l["words_ms"].each ->(w)
          ws.push(at + w)
        we = []
        l["words_end_ms"].each ->(w)
          we.push(at + w)
        if mode == "spans"
          ci = 0
          while ci < cc.size
            c = cc[ci]
            a = ws[c["w"][0]]
            b = we[c["w"][1] - 1]
            if ci + 1 < cc.size
              b = [b, ws[cc[ci + 1]["w"][0]] - get(cfg, "gap_ms", 50)].max
            else
              b += get(cfg, "tail_ms", 250)
            out.push({"line" => l["id"], "from_ms" => a, "to_ms" => b, "text" => c["text"]})
            ci += 1
        else
          aligned = ws.size >= words.size
          lens = []
          total = 0
          cc.each ->(c)
            n = join_words(words, c["w"][0], c["w"][1]).size
            lens.push(n)
            total += n
          t = l["start"]
          ci = 0
          while ci < cc.size
            c = cc[ci]
            wi = c["w"][0]
            d = (l["end"] - l["start"]) * lens[ci] / total
            if aligned
              t = ci == 0 ? l["start"] : [t, ws[wi]].max
              nxt = ci + 1 < cc.size ? ws[c["w"][1]] : l["end"]
              d = [get(cfg, "min_ms", 500), nxt - t].max
            out.push({"line" => l["id"], "from_ms" => t, "to_ms" => t + d, "text" => c["text"]})
            t += d
            ci += 1
    section("captions").each ->(c)
      t0 = anchor_fl(c["at"])
      out.push({"line" => nil, "from_ms" => ms_of(t0 + c["from_ms"] * FL_MS + FL_MS / 2), "to_ms" => ms_of(t0 + c["to_ms"] * FL_MS + FL_MS / 2), "text" => c["text"]})
    out

  # Chapters: at a shot's first frame, or at an anchor (snapped); the time is floored to the second.
  -> chapters(v1)
    out = []
    ms = section("markers")
    mi = 0
    while mi < ms.size
      m = ms[mi]
      if m["kind"] == "chapter"
        at = m["at"]
        f = nil
        if at.is_a?(String)
          k = 0
          while k < v1.size
            f = v1[k]["f0"] if v1[k]["id"] == at
            k += 1
          die("chapter at unknown shot " + at) if f == nil
        else
          f = snap_flicks(anchor_fl(at), @num, @den)
        sec = f * @den / @num
        out.push({"id" => m["id"], "title" => m["title"], "frame" => f, "sec" => sec, "tc" => timecode(f, @num, @den)})
      mi += 1
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
