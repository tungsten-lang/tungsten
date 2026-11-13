in Av

+ TimelineResolver
  FLICKS = 705600000
  HALF_FLICKS = 352800000
  FL_MS = 705600
  SEG_MAX = 48
  COMPOSITOR = 3
  RENDERER = {"still": 3, "clip": 3, "frames": 2, "program": 1, "card": 3, "black": 1, "group": 3, "fade_out": 1}
  ENCODER_ID = "vt:hevc:q0.750000:reorder:bt709-1-1-1:tv:left:420v"
  GRADED = {"still": true, "clip": true, "group": true}

  -> .resolve_episode(episode, cut_name)
    new(episode, cut_name).resolve

  -> .get_val(h, k, default)
    return default if h == nil
    v = h[k]
    v == nil ? default : v

  -> .to_f_val(x)
    x == nil ? ~0.0 : x.to_f

  -> .snap_flicks(fl, num, den)
    a = fl * num + den * HALF_FLICKS
    b = den * FLICKS
    q = a / b
    q -= 1 if a % b != 0 && a < 0
    q

  -> .samples_of_frames(n, sr, num, den)
    n * sr * den / num

  -> .pad_int(n, w)
    s = n.to_s
    while s.size < w
      s = "0" + s
    s

  -> .timecode(f, num, den)
    fps = (num + den / 2) / den
    drop = den == 1001 && (fps == 30 || fps == 60)
    n = f
    sep = ":"
    if drop
      sep = ";"
      d = fps / 15
      per10 = fps * 600 - d * 9
      tens = n / per10
      rem = n % per10
      if rem > d
        n = n + d * 9 * tens + d * ((rem - d) / (fps * 60 - d))
      else
        n = n + d * 9 * tens
    ff = n % fps
    s = n / fps
    pad_int(s / 3600, 2) + ":" + pad_int((s / 60) % 60, 2) + ":" + pad_int(s % 60, 2) + sep + pad_int(ff, 2)

  -> .fixed6(x)
    v = (x * ~1000000.0).round.to_i
    neg = v < 0
    v = 0 - v if neg
    s = (v / 1000000).to_s + "." + pad_int(v % 1000000, 6)
    s = "-" + s if neg
    s

  -> .canon(v)
    return "null" if v == nil
    return "true" if v == true
    return "false" if v == false
    t = type(v)
    return JSON.encode_string(v) if t == "String"
    return JSON.encode_string(v.to_s) if t == "Symbol"
    if t == "Float"
      return v.round.to_i.to_s if v == v.round && v.abs < ~1000000000000.0
      return "\"" + fixed6(v) + "\""
    return v.to_s if t == "Int" || t == "BigInt"
    if t == "Array"
      parts = []
      v.each ->(x)
        parts.push(canon(x))
      return "\[" + parts.join(",") + "\]"
    if t == "Hash"
      ks = []
      v.keys.each ->(k)
        ks.push(k.to_s)
      ks = ks.sort
      parts = []
      ks.each ->(k)
        parts.push(JSON.encode_string(k) + ":" + canon(v[k]))
      return "{" + parts.join(",") + "}"
    return canon(v.to_f) if t == "Decimal" || t == "Rational"
    JSON.encode_string(v.to_s)

  -> .hash_of(v)
    Crypto.sha256(canon(v))

  -> .norm_word(w)
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

  -> .split_words(text)
    out = []
    text.split(" ").each ->(w)
      out.push(w) if w != ""
    out

  -> .join_words(words, a, b)
    out = ""
    i = a
    while i < b
      out = out + " " if i > a
      out = out + words[i]
      i += 1
    out

  -> .find_phrase(words, phrase)
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

  -> new(@ep, @cut_name)
    @caption_id = @ep["burned_captions"] != nil ? TimelineResolver.hash_of(@ep["burned_captions"]) : nil
    @cut = @ep["cuts"][@cut_name]
    raise "studio: no cut " + @cut_name.to_s if @cut == nil
    @num = @cut["rate"][0]
    @den = @cut["rate"][1]
    @fpf = FLICKS * @den / @num
    @sr = @cut["sr"]
    @seed = TimelineResolver.get_val(@ep, "seed", 1)
    @assets = TimelineResolver.get_val(@ep, "assets", {})
    @lines = {}
    @line_src = {}
    @line_list = []
    @shot_src = {}
    @shot_fl = {}
    @busy = {}
    @prog_sha = {}
    @prog_dur = {}
    sections = [@ep]
    @ep["cuts"].keys.each ->(key)
      sections.push(@ep["cuts"][key])
    sections.each ->(sec)
      if sec["shots"] != nil
        sec["shots"].each ->(shot)
          if shot["kind"] == "program"
            sid = shot["id"]
            @prog_sha[sid] = shot["source_sha"] != nil ? shot["source_sha"] : "av-plan:" + Crypto.sha256(JSON.encode(shot["program"]))
            @prog_dur[sid] = shot["program_dur"] != nil ? shot["program_dur"] : JSON.encode(shot["program"]["run"]).include?("{dur}")

  -> section(k)
    v = @cut[k]
    v = @ep[k] if v == nil
    v == nil ? [] : v

  -> asset(key)
    a = @assets[key]
    raise "studio: unknown asset " + key.to_s if a == nil
    a

  -> asset_sha(key)
    asset(key)["sha256"]

  -> ms_of(fl)
    q = fl / FL_MS
    q -= 1 if fl % FL_MS != 0 && fl < 0
    q

  -> samples_of_fl(fl)
    fl / (FLICKS / @sr)

  -> cut_frame(fl)
    return TimelineResolver.snap_flicks(fl, @num, @den) if TimelineResolver.get_val(@cut, "snap", "nearest") != "ceil"
    a = fl * @num
    b = @den * FLICKS
    q = a / b
    q -= 1 if a % b != 0 && a < 0
    q += 1 if a - q * b > 0
    q

  -> round_ms(fl)
    ms_of(fl + FL_MS / 2)

  -> line(id)
    r = @lines[id]
    return r if r != nil
    l = @line_src[id]
    raise "studio: unknown line " + id.to_s if l == nil
    raise "studio: anchor cycle through line " + id.to_s if @busy[id] != nil
    @busy[id] = 1
    take = asset(l["take"])
    sp = take["speech_ms"]
    lead = sp[0]
    tail = sp[1]
    after = l["after"]
    base = 0
    if after["shot"] != nil
      base = anchor_fl(after)
    elsif TimelineResolver.get_val(after, "ref", "start") != "start"
      base = line(after["ref"])["seen_end_fl"]
    nominal = base + TimelineResolver.get_val(after, "gap_ms", 0) * FL_MS
    actual = nominal + TimelineResolver.get_val(l, "nudge_ms", 0) * FL_MS
    len = (tail - lead) * FL_MS
    rl = {"id": l["id"], "spk": l["spk"], "text": l["text"], "take": l["take"], "lead": lead,
          "start_fl": actual, "end_fl": actual + len, "nominal_fl": nominal,
          "start": ms_of(actual), "end": ms_of(actual + len), "nominal_start": ms_of(nominal),
          "words_ms": TimelineResolver.get_val(take, "words_ms", []), "words_end_ms": TimelineResolver.get_val(take, "words_end_ms", []),
          "cc": l["cc"], "gain_db": TimelineResolver.get_val(l, "gain_db", 0)}
    if TimelineResolver.get_val(l, "ripple", true)
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

  -> anchor_fl(a)
    raise "studio: missing anchor" if a == nil
    off = TimelineResolver.get_val(a, "ms", 0) * FL_MS + TimelineResolver.get_val(a, "frames", 0) * @fpf
    if a["shot"] != nil
      return shot_edge_fl(a["shot"], TimelineResolver.get_val(a, "edge", "start")) + off
    ref = TimelineResolver.get_val(a, "ref", "start")
    return off if ref == "start"
    r = line(ref)
    if a["phrase"] != nil
      words = TimelineResolver.split_words(r["text"])
      k = TimelineResolver.find_phrase(words, a["phrase"])
      raise "studio: phrase not in line " + ref + ": " + a["phrase"] if k < 0
      ws = r["words_ms"]
      raise "studio: line " + ref + " has no word times for its phrase" if ws.size == 0
      w = ws[[k, ws.size - 1].min]
      return r["seen_start_fl"] + (w - r["lead"]) * FL_MS + off
    return r["seen_end_fl"] + off if TimelineResolver.get_val(a, "edge", "start") == "end"
    r["seen_start_fl"] + off

  -> shot_start_fl(id)
    t = @shot_fl[id]
    return t if t != nil
    s = @shot_src[id]
    raise "studio: anchor on unknown shot " + id.to_s if s == nil
    raise "studio: anchor cycle through shot " + id.to_s if @busy["shot:" + id] != nil
    @busy["shot:" + id] = 1
    t = anchor_fl(s["at"])
    @busy.delete("shot:" + id)
    @shot_fl[id] = t
    t

  -> shot_frames(s)
    n = s["frames"]
    return nil if n == nil
    raise "studio: shot " + s["id"] + ": its program's frame count is unknown" if n == "program"
    n

  -> shot_edge_fl(id, edge)
    t = shot_start_fl(id)
    return t if edge != "end"
    n = shot_frames(@shot_src[id])
    raise "studio: shot " + id.to_s + " has no explicit length to anchor on its end" if n == nil
    t + n * @fpf

  -> words_between(t0, t1)
    out = []
    @line_list.each ->(l)
      if l["start"] >= t0 - 500 && l["start"] < t1
        ws = l["words_ms"]
        at = l["start"] - l["lead"]
        words = TimelineResolver.split_words(l["text"])
        k = 0
        while k < words.size
          w = ws.size > 0 ? ws[[k, ws.size - 1].min] : (l["start"] - at)
          out.push([at + w, TimelineResolver.norm_word(words[k])])
          k += 1
    out

  -> phrase_local(phrase, t0, t1, default)
    return default if phrase == nil
    words = words_between(t0, t1)
    target = []
    TimelineResolver.split_words(phrase).each ->(w)
      nw = TimelineResolver.norm_word(w)
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
    raise "studio: phrase not spoken in its shot: " + phrase.to_s

  -> style(name)
    return nil if name == nil
    styles = TimelineResolver.get_val(@ep, "styles", {})
    st = styles[name]
    raise "studio: unknown style " + name.to_s if st == nil
    st

  -> near(p, kind, t0, t1, shakes, overlays, org)
    sh = []
    shakes.each ->(t)
      sh.push(ms_of(t - org)) if t >= t0 - 1000 * FL_MS && t < t1 + 2000 * FL_MS
    p["shakes"] = sh
    su = []
    overlays.each ->(x)
      c = x[2]
      if TimelineResolver.get_val(c, "on", ["still", "clip"]).include?(kind)
        if x[0] + x[1] * FL_MS > t0 && x[0] < t1 + 2000 * FL_MS
          su.push([ms_of(x[0] - org), x[1], {"el": c["el"], "reveal_ms": TimelineResolver.get_val(c, "reveal_ms", 0), "fade_ms": TimelineResolver.get_val(c, "fade_ms", 0), "stroke_min_alpha": TimelineResolver.get_val(c, "stroke_min_alpha", 0)}])
    p["overlays"] = su
    p

  -> replace_param(s, p, deps)
    rp = s["replace"]
    return nil if rp == nil
    deps.push(asset_sha(rp["match"]))
    deps.push(asset_sha(rp["with"]))
    p["replace"] = {"match": rp["match"], "with": rp["with"]}
    nil

  -> item_for(s, t0f, t1f, shakes, overlays, org)
    kind = s["kind"]
    t0 = ms_of(t0f)
    t1 = ms_of(t1f)
    dur = t1 - t0
    osh = round_ms(t0f - org)
    p = {"dur_ms": dur}
    deps = []
    if kind == "still" || kind == "clip"
      p["src"] = s["src"]
      deps.push(asset_sha(s["src"]))
      p["camera"] = s["camera"]
      p["fx"] = TimelineResolver.get_val(s, "fx", [])
      p["style"] = style(s["style"])
      p["matte"] = s["matte"]
      if s["wipe"] != nil
        w = s["wipe"]
        deps.push(asset_sha(w["src"]))
        at = phrase_local(TimelineResolver.get_val(w["at"], "phrase", nil), t0, t1, TimelineResolver.get_val(w, "default_ms", 6000))
        at += osh if TimelineResolver.get_val(w["at"], "phrase", nil) != nil
        p["wipe"] = {"src": w["src"], "at_ms": at, "ms": w["ms"]}
      if s["clip"] != nil
        c = s["clip"]
        parts = []
        c["parts"].each ->(pt)
          ca = asset(pt["src"])
          deps.push(asset_sha(pt["src"]))
          parts.push({"src": pt["src"], "first": TimelineResolver.get_val(pt, "first", 0), "count": TimelineResolver.get_val(pt, "count", ca["count"] - TimelineResolver.get_val(pt, "first", 0))})
        at = 0
        at = phrase_local(c["at"]["phrase"], t0, t1, 0) + osh if c["at"] != nil
        p["clip"] = {"parts": parts, "xf": TimelineResolver.get_val(c, "xf", 0), "fps": TimelineResolver.get_val(c, "fps", @num / @den), "at_ms": at,
                     "speed": c["speed"], "add_ms": TimelineResolver.get_val(c, "add_ms", 0) + osh, "blend": TimelineResolver.get_val(c, "blend", true),
                     "pre": c["pre"], "zoom": c["zoom"], "hold": c["hold"]}
        p["clip"]["nearest"] = true if TimelineResolver.get_val(c, "nearest", false)
      near(p, kind, t0f, t1f, shakes, overlays, org)
    elsif kind == "frames"
      a = asset(s["src"])
      deps.push(asset_sha(s["src"]))
      p = {"src": s["src"], "count": a["count"]}
      p["in"] = s["in"] if s["in"] != nil
      replace_param(s, p, deps)
    elsif kind == "program"
      psha = @prog_sha[s["id"]]
      raise "studio: program shot " + s["id"] + " has no source hash" if psha == nil
      n = (dur * @num * 2 + 1000 * @den) / (2000 * @den)
      p = {"source_sha": psha, "count": n}
      p["in"] = s["in"] if s["in"] != nil
      p["dur_ms"] = dur if @prog_dur[s["id"]] == true
      deps.push(psha)
      TimelineResolver.get_val(s, "deps", []).each ->(d)
        deps.push(asset_sha(d))
      replace_param(s, p, deps)
    elsif kind == "card"
      p = {"bg": s["bg"], "elements": s["elements"]}
    elsif kind == "group"
      panes = []
      s["panes"].each ->(ch)
        deps.push(asset_sha(ch["src"]))
        at = 0
        at = phrase_local(ch["at"]["phrase"], t0, t1, TimelineResolver.get_val(ch, "default_ms", 0)) + osh if ch["at"] != nil
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
      raise "studio: unknown shot kind " + kind.to_s
    sdeps = []
    deps.each ->(d)
      sdeps.push(d) if d != nil
    sdeps = sdeps.sort
    # Keep nil entries in deps if asset had nil sha256 during read-only av_plan
    if sdeps.size != deps.size
      sdeps = deps
    rh = {"kind": kind, "v": RENDERER[kind], "id": s["id"], "seed": @seed, "p": p, "deps": sdeps}
    recipe = TimelineResolver.hash_of(rh)
    {"id": s["id"], "kind": kind, "params": p, "trans_in": TimelineResolver.get_val(s, "trans_in", {"kind": "cut", "frames": 0}),
     "recipe": recipe, "deps": sdeps}

  -> audio_lines
    out = []
    @line_list.each ->(l)
      s0 = samples_of_fl(l["start_fl"] - l["lead"] * FL_MS)
      out.push({"id": l["id"], "spk": l["spk"], "src": l["take"], "s0": s0, "speech_ms": [l["start"], l["end"]],
                "nominal_ms": l["nominal_start"], "gain_db": l["gain_db"], "flicks": l["start_fl"]})
    out

  -> audio_cues
    out = []
    section("cues").each ->(c)
      k = c["kind"]
      if k == "sfx"
        t = anchor_fl(c["at"])
        out.push({"id": c["id"], "kind": k, "src": c["src"], "name": c["name"], "s0": samples_of_fl(t),
                  "gain_db": c["gain_db"], "filter": c["filter"]})
      elsif k == "amb" || k == "music"
        a = anchor_fl(c["from"])
        b = anchor_fl(c["to"])
        o = {"id": c["id"], "kind": k, "src": c["src"], "name": c["name"], "s0": samples_of_fl(a),
             "s1": samples_of_fl(b), "gain_db": c["gain_db"]}
        o["fade_in_ms"] = c["fade_in_ms"] if c["fade_in_ms"] != nil
        o["fade_out_ms"] = c["fade_out_ms"] if c["fade_out_ms"] != nil
        out.push(o)
      elsif k == "audio"
        t = anchor_fl(c["at"])
        o = {"id": c["id"], "kind": k, "src": c["src"], "s0": samples_of_fl(t), "gain_db": c["gain_db"],
             "norm": c["norm"], "fade_in_ms": c["fade_in_ms"], "fade_out_ms": c["fade_out_ms"]}
        o["s1"] = samples_of_fl(anchor_fl(c["until"])) if c["until"] != nil
        out.push(o)
    out

  -> subtitles
    out = []
    cfg = TimelineResolver.get_val(@cut, "caption_timing", {})
    mode = TimelineResolver.get_val(cfg, "timing", "starts")
    @line_list.each ->(l)
      cc = l["cc"]
      if cc != nil && cc.size > 0
        words = TimelineResolver.split_words(l["text"])
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
              b = [b, ws[cc[ci + 1]["w"][0]] - TimelineResolver.get_val(cfg, "gap_ms", 50)].max
            else
              b += TimelineResolver.get_val(cfg, "tail_ms", 250)
            out.push({"line": l["id"], "from_ms": a, "to_ms": b, "text": c["text"]})
            ci += 1
        else
          aligned = ws.size >= words.size
          lens = []
          total = 0
          cc.each ->(c)
            n = TimelineResolver.join_words(words, c["w"][0], c["w"][1]).size
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
              d = [TimelineResolver.get_val(cfg, "min_ms", 500), nxt - t].max
            out.push({"line": l["id"], "from_ms": t, "to_ms": t + d, "text": c["text"]})
            t += d
            ci += 1
    section("captions").each ->(c)
      t0 = anchor_fl(c["at"])
      out.push({"line": nil, "from_ms": ms_of(t0 + c["from_ms"] * FL_MS + FL_MS / 2), "to_ms": ms_of(t0 + c["to_ms"] * FL_MS + FL_MS / 2), "text": c["text"]})
    out

  -> chapters(v1)
    out = []
    ms = section("markers")
    mi = 0
    while mi < ms.size
      m = ms[mi]
      if m["kind"] == "chapter"
        at = m["at"]
        f = nil
        if type(at) == "String"
          k = 0
          while k < v1.size
            f = v1[k]["f0"] if v1[k]["id"] == at
            k += 1
          raise "studio: chapter at unknown shot " + at if f == nil
        else
          f = TimelineResolver.snap_flicks(anchor_fl(at), @num, @den)
        sec = f * @den / @num
        out.push({"id": m["id"], "title": m["title"], "frame": f, "sec": sec, "tc": TimelineResolver.timecode(f, @num, @den)})
      mi += 1
    out

  -> entry_item(e)
    e[1] == "V1" ? @v1[e[0]] : @v4[e[0]]

  -> segment_quality(ents)
    qk = TimelineResolver.get_val(TimelineResolver.get_val(@cut, "encoder", {}), "quality_by_kind", nil)
    return nil if qk == nil
    q = TimelineResolver.to_f_val(TimelineResolver.get_val(TimelineResolver.get_val(@cut, "encoder", {}), "quality", ~0.75))
    ents.each ->(e)
      it = entry_item(e)
      kq = qk[it["kind"]]
      q = TimelineResolver.to_f_val(kq) if kq != nil && TimelineResolver.to_f_val(kq) > q
    q

  -> intervals(v1, v4)
    cuts = {}
    v1.each ->(it)
      cuts[it["f0"]] = 1
      cuts[it["f1"]] = 1
      tr = it["trans_in"]
      n = TimelineResolver.get_val(tr, "frames", 0)
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
      n = TimelineResolver.get_val(tr, "frames", 0)
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

  -> segments(iv)
    out = []
    iv.each ->(x)
      a = x[0]
      b = x[1]
      s = a
      while s < b
        n = [SEG_MAX, b - s].min
        parts = [ENCODER_ID, COMPOSITOR, @cut["w"], @cut["h"], @num, @den, n]
        parts.push([@caption_id, s]) if @caption_id != nil
        names = []
        x[2].each ->(e)
          it = entry_item(e)
          parts.push([it["recipe"], s - it["f0"], e[2]])
          names.push(it["id"])
        q = segment_quality(x[2])
        parts.push(["q", TimelineResolver.fixed6(q)]) if q != nil
        sg = {"f0": s, "n": n, "key": TimelineResolver.hash_of(parts), "items": names}
        sg["q"] = q if q != nil
        out.push(sg)
        s += n
    out

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
      raise "studio: shot " + shots[i]["id"] + " starts before " + shots[i - 1]["id"] if starts[i] <= starts[i - 1]
      i += 1
    @frames = TimelineResolver.snap_flicks(end_fl, @num, @den)
    total_samples = TimelineResolver.samples_of_frames(@frames, @sr, @num, @den)
    shakes = []
    overlays = []
    section("cues").each ->(c)
      shakes.push(anchor_fl(c["at"])) if c["kind"] == "sfx" && TimelineResolver.get_val(c, "shake", false)
      overlays.push([anchor_fl(c["at"]), c["ms"], c]) if c["kind"] == "overlay"
    v1 = []
    i = 0
    while i < shots.size
      s = shots[i]
      t0 = starts[i]
      t1 = i + 1 < shots.size ? starts[i + 1] : end_fl
      f0 = cut_frame(t0)
      f1 = i + 1 < shots.size ? cut_frame(t1) : @frames
      raise "studio: shot " + s["id"] + " is shorter than a frame" if f1 <= f0
      org = TimelineResolver.get_val(@cut, "snap", "nearest") == "ceil" ? f0 * @fpf : t0
      item = item_for(s, t0, t1, shakes, overlays, org)
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
        raise "studio: fade_out before unknown shot" if fe == nil
        p = {"frames": n, "power": TimelineResolver.to_f_val(TimelineResolver.get_val(c, "power", ~1.0))}
        v4.push({"id": c["id"], "kind": "fade_out", "f0": fe - n, "f1": fe, "params": p,
                 "recipe": TimelineResolver.hash_of({"kind": "fade_out", "v": RENDERER["fade_out"], "p": p})})
    a1 = audio_lines()
    cues_out = audio_cues()
    subs = subtitles()
    i = 0
    while i < shots.size
      raise "studio: shot " + shots[i]["id"] + ": its program wrote no captions" if TimelineResolver.get_val(shots[i], "captions_from_program", false)
      i += 1
    subs = subs.sort ->(x, y)
      x["from_ms"] <=> y["from_ms"]
    markers = chapters(v1)
    iv = intervals(v1, v4)
    segs = segments(iv)
    {"schema": "studio.resolved/1", "episode": @ep["id"], "cut": @cut_name,
     "rate": [@num, @den], "sr": @sr, "w": @cut["w"], "h": @cut["h"],
     "tc_start": TimelineResolver.get_val(@cut, "tc_start", "00:00:00:00"), "frames": @frames, "samples": total_samples,
     "end_ms": ms_of(end_fl), "seed": @seed, "encoder": ENCODER_ID,
     "tracks": [{"id": "V1", "kind": "video", "items": v1},
                {"id": "V4", "kind": "video", "role": "fades", "items": v4},
                {"id": "A1", "kind": "audio", "role": "narration", "items": a1},
                {"id": "A3", "kind": "audio", "role": "cues", "items": cues_out},
                {"id": "T1", "kind": "subtitle", "items": subs},
                {"id": "M", "kind": "marker", "items": markers}],
     "intervals": iv, "segments": segs}
