# studio/fcpxml — `studio fcpxml <episode> [--cut full] [--out path] [--master path]`: the resolved timeline as an
# FCPXML 1.11 project for Final Cut Pro.
#
# Times are rationals straight from the integers: a frame f is f·den/num s, an audio sample s is s/sr s (reduced).
#   resources  the format (size, frame duration, Rec. 709), the rendered master (picture and final mix), every
#              source the episode names that Final Cut can open (panels and images, clip movies, audio takes,
#              music, effects), and the Basic Title effect
#   spine      the picture: one asset-clip of the master per V1 item, its range [f0, f1), named by its studio id,
#              with a note carrying the kind, transition and recipe (for reading edits back)
#   connected  above the spine: each still's source panel (lane 1, disabled: the master shows it graded and
#              moving), the item's overlay text as a title (lane 2, disabled: baked into the master), the captions
#              (lane 3, SRT role); below: the final mix (lane -1, role "Final Mix"), and the stems by role, disabled
#              (dialogue lines, music, ambience, effects), each anchored to the spine clip it starts in, at its
#              exact sample
#   markers    chapters as chapter-markers on the clip that contains them
# A connected clip's offset is in its parent's timeline; the parent's `start` is its in-point in the master, so
# every offset below is simply the absolute time.

use base
use project
use audio

-> gcd_i(a, b)
  while b != 0
    t = a % b
    a = b
    b = t
  a

# n/d seconds as an FCPXML time.
-> fx_rat(n, d)
  return "0s" if n == 0
  g = gcd_i(n.abs, d)
  n = n / g
  d = d / g
  return n.to_s + "s" if d == 1
  n.to_s + "/" + d.to_s + "s"

-> fx_esc(s)
  s.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub("\"", "&quot;")

# file:// URL of an absolute path (bytes outside the unreserved set percent-encoded).
-> fx_url(p)
  hex = "0123456789ABCDEF"
  out = "file://"
  i = 0
  while i < p.size
    c = p.byte_at(i)
    if (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 47 || c == 46 || c == 45 || c == 95 || c == 126
      out = out + c.chr
    else
      out = out + "%" + hex.slice(c / 16, 1) + hex.slice(c % 16, 1)
    i += 1
  out

-> fx_color(c)
  fixed6((c[0] + ~0.0) / ~255.0) + " " + fixed6((c[1] + ~0.0) / ~255.0) + " " + fixed6((c[2] + ~0.0) / ~255.0) + " 1"

+ Fcpxml
  -> new(@p, @r)
    @num = @r["rate"][0]
    @den = @r["rate"][1]
    @sr = @r["sr"]
    @v1 = @r["tracks"][0]["items"]
    @assets = {}
    @asset_order = []
    @styles = 0
    @mixer = nil

  -> ft(f)
    fx_rat(f * @den, @num)

  -> st(s)
    fx_rat(s, @sr)

  -> frame_of_sample(s)
    (s * @num) / (@sr * @den)

  -> frame_of_ms(ms)
    snap_ms(ms, @num, @den)

  # The spine clip containing frame f.
  -> parent_of(f)
    i = 0
    while i + 1 < @v1.size && @v1[i + 1]["f0"] <= f
      i += 1
    i

  # An asset id for a source file (registered once).
  -> asset_id(key, path, kind, dur)
    a = @assets[path]
    return a["id"] if a != nil
    id = "a" + (@asset_order.size + 1).to_s
    a = {"id" => id, "name" => key, "path" => path, "kind" => kind, "dur" => dur}
    @assets[path] = a
    @asset_order.push(a)
    id

  # Length of an audio source in samples at sr (decoded once, as the mix decodes it).
  -> audio_len(key)
    @mixer = Mixer.new(@p, @r) if @mixer == nil
    info = wav_info(@mixer.decoded(key))
    info[1] / (4 * info[2])

  -> role_of_line(spk)
    return "dialogue.Narration" if spk == "NARRATOR"
    "dialogue.Characters"

  -> role_of_cue(kind)
    return "music.Score" if kind == "music"
    return "effects.Ambience" if kind == "amb"
    return "effects.SFX" if kind == "sfx"
    "music.Outro"

  # Connected items per spine clip: [xml text, ...]
  -> connected
    con = []
    @v1.each ->(it)
      con.push([])
    ep = @p.ep
    # sources above the picture
    i = 0
    while i < @v1.size
      it = @v1[i]
      p = it["params"]
      if it["kind"] == "still" || it["kind"] == "clip"
        src = p["src"]
        id = asset_id(src, @p.asset_path(src), "image", nil)
        con[i].push("<video ref=\"" + id + "\" lane=\"1\" offset=\"" + ft(it["f0"]) + "\" name=\"" + fx_esc(src) + "\" start=\"0s\" duration=\"" + ft(it["f1"] - it["f0"]) + "\" enabled=\"0\"/>")
        if p["clip"] != nil
          p["clip"]["parts"].each ->(pt)
            ap = @p.asset_path(pt["src"])
            mov = ap.slice(0, ap.size - 7) + ".mp4"
            if ap.ends_with?("_frames") && File.exist?(mov)
              cid = asset_id(pt["src"], mov, "movie", nil)
              con[i].push("<asset-clip ref=\"" + cid + "\" lane=\"1\" offset=\"" + ft(it["f0"]) + "\" name=\"" + fx_esc(pt["src"]) + "\" start=\"" + fx_rat(pt["first"], 24) + "\" duration=\"" + ft(it["f1"] - it["f0"]) + "\" srcEnable=\"video\" enabled=\"0\"/>")
        texts = []
        m = p["matte"]
        if m != nil
          collect_text(m["elements"], texts)
        if texts.size > 0
          con[i].push(title_xml(2, it["f0"], it["f1"] - it["f0"], it["id"] + " overlay", texts.join("\n"), [239, 234, 225], 30))
        get(p, "overlays", []).each ->(ov)
          ms0 = it["t0_ms"] + ov[0]
          fa = frame_of_ms(ms0)
          fb = frame_of_ms(ms0 + ov[1])
          if fb > fa && fa >= it["f0"] && fa < it["f1"]
            e = ov[2]["el"]
            con[i].push(title_xml(2, fa, fb - fa, "super", e["text"], e["fill"], e["size"]))
      i += 1
    # captions
    @r["tracks"][4]["items"].each ->(c)
      fa = frame_of_ms(c["from_ms"])
      fb = frame_of_ms(c["to_ms"])
      if fb > fa && fa < @r["frames"]
        fb = @r["frames"] if fb > @r["frames"]
        @styles += 1
        sid = "cs" + @styles.to_s
        x = "<caption lane=\"3\" offset=\"" + ft(fa) + "\" name=\"" + fx_esc(c["text"].split("\n")[0]) + "\" start=\"0s\" duration=\"" + ft(fb - fa) + "\" role=\"SRT?captionFormat=SRT.en\">"
        x = x + "<text><text-style ref=\"" + sid + "\">" + fx_esc(c["text"]) + "</text-style></text>"
        x = x + "<text-style-def id=\"" + sid + "\"><text-style font=\".AppleSystemUIFont\" fontSize=\"13\" fontFace=\"Regular\" fontColor=\"1 1 1 1\" backgroundColor=\"0 0 0 1\"/></text-style-def></caption>"
        con[parent_of(fa)].push(x)
    # the final mix and the stems below
    mid = asset_id("master", @master, "master", @r["frames"])
    con[0].push("<asset-clip ref=\"" + mid + "\" lane=\"-1\" offset=\"0s\" name=\"final mix\" start=\"0s\" duration=\"" + ft(@r["frames"]) + "\" srcEnable=\"audio\" audioRole=\"Final Mix\"/>")
    @r["tracks"][2]["items"].each ->(l)
      n = audio_len(l["src"])
      aid = asset_id(l["src"], @p.asset_path(l["src"]), "audio", n)
      con[parent_of(frame_of_sample(l["s0"]))].push("<asset-clip ref=\"" + aid + "\" lane=\"-2\" offset=\"" + st(l["s0"]) + "\" name=\"" + fx_esc(l["id"] + " " + l["spk"]) + "\" start=\"0s\" duration=\"" + st(n) + "\" srcEnable=\"audio\" audioRole=\"" + role_of_line(l["spk"]) + "\" enabled=\"0\"/>")
    lanes = {"music" => "-3", "amb" => "-4", "sfx" => "-5", "audio" => "-3"}
    @r["tracks"][3]["items"].each ->(c)
      n = audio_len(c["src"])
      if c["s1"] != nil
        n = [n, c["s1"] - c["s0"]].min
      aid = asset_id(c["src"], @p.asset_path(c["src"]), "audio", audio_len(c["src"]))
      if c["s0"] < @r["samples"] && n > 0
        con[parent_of(frame_of_sample(c["s0"]))].push("<asset-clip ref=\"" + aid + "\" lane=\"" + lanes[c["kind"]] + "\" offset=\"" + st(c["s0"]) + "\" name=\"" + fx_esc(c["id"]) + "\" start=\"0s\" duration=\"" + st(n) + "\" srcEnable=\"audio\" audioRole=\"" + role_of_cue(c["kind"]) + "\" enabled=\"0\"/>")
    con

  -> collect_text(els, out)
    return nil if els == nil
    els.each ->(e)
      if e["t"] == "text"
        out.push(e["text"])
      elsif e["t"] == "fit"
        o = e["options"][0]
        collect_text(o, out)
    nil

  -> title_xml(lane, f, n, name, text, col, size)
    @styles += 1
    sid = "ts" + @styles.to_s
    x = "<title ref=\"basic_title\" lane=\"" + lane.to_s + "\" offset=\"" + ft(f) + "\" name=\"" + fx_esc(name) + "\" start=\"0s\" duration=\"" + ft(n) + "\" enabled=\"0\">"
    x = x + "<text><text-style ref=\"" + sid + "\">" + fx_esc(text) + "</text-style></text>"
    x + "<text-style-def id=\"" + sid + "\"><text-style font=\"Avenir Next\" fontSize=\"" + size.to_s + "\" fontColor=\"" + fx_color(col) + "\"/></text-style-def></title>"

  -> write(out, master)
    @master = master
    con = connected()
    fps_i = @num / @den
    w = @r["w"]
    h = @r["h"]
    fmt = "<format id=\"r1\""
    fmt = fmt + " name=\"FFVideoFormat" + h.to_s + "p" + fps_i.to_s + "\"" if @den == 1
    fmt = fmt + " frameDuration=\"" + fx_rat(@den, @num) + "\" width=\"" + w.to_s + "\" height=\"" + h.to_s + "\" colorSpace=\"1-1-1 (Rec. 709)\"/>"
    lines = []
    lines.push("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
    lines.push("<!DOCTYPE fcpxml>")
    lines.push("<fcpxml version=\"1.11\">")
    lines.push(" <resources>")
    lines.push("  " + fmt)
    @asset_order.each ->(a)
      x = "  <asset id=\"" + a["id"] + "\" name=\"" + fx_esc(a["name"]) + "\" start=\"0s\""
      if a["kind"] == "master"
        x = x + " duration=\"" + ft(a["dur"]) + "\" hasVideo=\"1\" format=\"r1\" hasAudio=\"1\" audioSources=\"1\" audioChannels=\"2\" audioRate=\"" + @sr.to_s + "\""
      elsif a["kind"] == "audio"
        x = x + " duration=\"" + st(a["dur"]) + "\" hasAudio=\"1\" audioSources=\"1\" audioChannels=\"2\" audioRate=\"" + @sr.to_s + "\""
      elsif a["kind"] == "movie"
        x = x + " hasVideo=\"1\""
      else
        x = x + " duration=\"0s\" hasVideo=\"1\""
      lines.push(x + "><media-rep kind=\"original-media\" src=\"" + fx_esc(fx_url(a["path"])) + "\"/></asset>")
    lines.push("  <effect id=\"basic_title\" name=\"Basic Title\" uid=\".../Titles.localized/Bumper:Opener.localized/Basic Title.localized/Basic Title.moti\"/>")
    lines.push(" </resources>")
    lines.push(" <library>")
    lines.push("  <event name=\"" + fx_esc(get(@p.ep, "title", @p.ep["id"])) + "\">")
    lines.push("   <project name=\"" + fx_esc(@p.ep["id"] + " (" + @r["cut"] + ")") + "\">")
    lines.push("    <sequence format=\"r1\" duration=\"" + ft(@r["frames"]) + "\" tcStart=\"0s\" tcFormat=\"NDF\" audioLayout=\"stereo\" audioRate=\"" + (@sr / 1000).to_s + "k\">")
    lines.push("     <spine>")
    mk = @r["tracks"][5]["items"]
    i = 0
    while i < @v1.size
      it = @v1[i]
      tr = it["trans_in"]
      note = "studio:" + it["id"] + " kind=" + it["kind"] + " trans_in=" + tr["kind"] + ":" + get(tr, "frames", 0).to_s + " recipe=" + it["recipe"].slice(0, 16)
      lines.push("      <asset-clip ref=\"" + @assets[master]["id"] + "\" offset=\"" + ft(it["f0"]) + "\" name=\"" + fx_esc(it["id"]) + "\" start=\"" + ft(it["f0"]) + "\" duration=\"" + ft(it["f1"] - it["f0"]) + "\" srcEnable=\"video\" tcFormat=\"NDF\">")
      lines.push("       <note>" + fx_esc(note) + "</note>")
      con[i].each ->(x)
        lines.push("       " + x)
      mk.each ->(m)
        if m["frame"] >= it["f0"] && m["frame"] < it["f1"]
          lines.push("       <chapter-marker start=\"" + ft(m["frame"]) + "\" duration=\"" + ft(1) + "\" value=\"" + fx_esc(m["title"]) + "\" posterOffset=\"0s\"/>")
      lines.push("      </asset-clip>")
      i += 1
    lines.push("     </spine>")
    lines.push("    </sequence>")
    lines.push("   </project>")
    lines.push("  </event>")
    lines.push(" </library>")
    lines.push("</fcpxml>")
    write_text(out, lines.join("\n") + "\n")
    [@v1.size, @asset_order.size]

-> cmd_fcpxml(args)
  cut = "full"
  i = 0
  out = nil
  master = nil
  while i < args.size
    cut = args[i + 1] if args[i] == "--cut" && i + 1 < args.size
    out = args[i + 1] if args[i] == "--out" && i + 1 < args.size
    master = args[i + 1] if args[i] == "--master" && i + 1 < args.size
    i += 1
  p = Project.new(args[1], cut)
  p.verify_assets(true)
  r = p.resolve
  out = p.out_path("timeline.fcpxml") if out == nil
  master = p.out_path("master.mp4") if master == nil
  master = File.expand_path(master)
  t0 = clock_ms()
  res = Fcpxml.new(p, r).write(out, master)
  << "fcpxml: " + res[0].to_s + " spine clips, " + res[1].to_s + " assets, " + r["frames"].to_s + " frames at " + r["rate"][0].to_s + "/" + r["rate"][1].to_s + " -> " + out + " (" + (clock_ms() - t0).to_s + " ms)"
  0
