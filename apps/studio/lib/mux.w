# studio/mux — the master: a passthrough concatenation of the stored segments (no re-encode), the mix, a tmcd
# track from tc_start and chapters, plus the SRT and YouTube chapter list generated from the resolved timeline;
# and `studio verify`, which checks the A/V contract of TIMELINE.md §2 on any master.
#
# Back end: core/media's Mux (AVAssetWriter passthrough, AAC, tmcd). Segments from the interim ffmpeg encoder
# (--encoder ffmpeg) are joined with the ffmpeg concat demuxer instead, for the comparison.

use base
use project
use encode
use audio

-> mux_master(p, r, out, opts)
  segs = r["segments"]
  base = p.build + "/" + p.cut
  lst = p.out_path("segments.txt")
  lines = []
  nfr = 0
  limit = get(opts, "frames", r["frames"])
  lo = get(opts, "from", 0)
  fbase = nil
  segs.each ->(s)
    if s["f0"] < limit && s["f0"] + s["n"] > lo
      fbase = s["f0"] if fbase == nil
      sp = segment_path(p.build, s["key"])
      die("segment missing: " + s["key"] + " at frame " + s["f0"].to_s + " (run studio render)") if !File.exist?(sp)
      lines.push("file '" + sp + "'")
      nfr += s["n"]
  write_text(lst, lines.join("\n") + "\n")
  # chapters as ffmetadata, in frames
  meta = ";FFMETADATA1\ntitle=" + get(p.ep, "title", p.ep["id"]) + "\n"
  marks = r["tracks"][5]["items"]
  mi = 0
  while mi < marks.size
    m = marks[mi]
    e = nfr
    e = marks[mi + 1]["frame"] if mi + 1 < marks.size
    if m["frame"] < nfr
      meta = meta + "\n[CHAPTER]\nTIMEBASE=" + r["rate"][1].to_s + "/" + r["rate"][0].to_s + "\nSTART=" + m["frame"].to_s + "\nEND=" + [e, nfr].min.to_s + "\ntitle=" + m["title"] + "\n"
    mi += 1
  mfile = p.out_path("chapters.ffmeta")
  write_text(mfile, meta)
  wav = p.out_path("mix.wav")
  audio = File.exist?(wav) && get(opts, "audio", true)
  mov = out.downcase.ends_with?(".mov")
  part = out + (mov ? ".part.mov" : ".part.mp4")
  if p.encoder["backend"] == "ffmpeg"
    die("ffmpeg mux backend removed; use native videotoolbox")
  t0 = clock_ms()
  mo = {rate: r["rate"], tc_start: get(r, "tc_start", "00:00:00:00"), frames: nfr}
  mo[:edit_lists] = get(opts, "edit_lists", "audio")
  if audio
    mo[:audio_codec] = get(opts, "audio_codec", nil)
    mo[:audio] = wav
    kb = get(p.cut_cfg(p.cut), "audio_kbps", nil)
    mo[:audio_kbps] = kb if kb != nil
  # chapters: a QuickTime chapter track (and Nero chpl) at each chapter's first frame
  chs = chapter_list(r, fbase, nfr)
  mo[:chapters] = chs if chs.size > 0
  m = Mux.new(part, mo)
  segs.each ->(s)
    m.append_file(segment_path(p.build, s["key"])) if s["f0"] < limit && s["f0"] + s["n"] > lo
  res = m.close
  File.rename(part, out)
  write_text(p.out_path("captions.srt"), srt_text(r))
  write_text(p.out_path("chapters.txt"), chapters_text(r))
  [res[:frames], clock_ms() - t0, res]

# The resolved chapters as [[title, frame], ...] for a master covering frames [lo, lo + n).
-> chapter_list(r, lo, n)
  out = []
  r["tracks"][5]["items"].each ->(m)
    f = m["frame"] - lo
    out.push([m["title"], f]) if f >= 0 && f < n
  out

# studio share <episode.json> [--cut full] [--preset share]: the share copy (720p H.264 + AAC by default) transcoded
# from the master, chapters and timecode carried, then checked.
-> cmd_share(args)
  p = Project.new(args[1], opt_arg(args, "--cut", "full"))
  r = JSON.parse(File.read(p.resolved_path))
  src = opt_arg(args, "--master", p.out_path("master.mp4"))
  preset = opt_arg(args, "--preset", "share")
  out = opt_arg(args, "--out", p.out_path(preset + ".mp4"))
  die("no master " + src + " (run studio mux)") if !File.exist?(src)
  t0 = clock_ms()
  topts = {preset: preset, retries: opt_arg(args, "--retries", "2").to_i}
  codec = opt_arg(args, "--codec", nil)
  topts[:codec] = codec if codec != nil
  kbps = opt_arg(args, "--kbps", nil)
  topts[:bitrate] = kbps.to_i * 1000 if kbps != nil
  topts[:rate] = r["rate"]
  topts[:frames] = r["frames"]
  resume = opt_arg(args, "--resume", nil)
  topts[:resume_dir] = resume if resume != nil
  topts[:timeout_ms] = opt_arg(args, "--timeout-ms", "30000").to_i
  cancel = opt_arg(args, "--cancel-file", nil)
  topts[:cancel_file] = cancel if cancel != nil
  topts[:edit_lists] = false if args.include?("--no-edit-lists")
  ac = opt_arg(args, "--audio-codec", nil)
  topts[:audio] = ac if ac != nil
  ww = opt_arg(args, "--width", nil)
  hh = opt_arg(args, "--height", nil)
  topts[:width] = ww.to_i if ww != nil
  topts[:height] = hh.to_i if hh != nil
  res = Transcode.run(src, out, topts)
  dt = clock_ms() - t0
  << "share: " + res[:frames].to_s + " frames in " + dt.to_s + " ms (" + res[:fps].to_s + " fps), " + (res[:file_bytes] / 1048576).to_s + " MB -> " + out
  chs = chapter_list(r, 0, r["frames"])
  topts[:frames] = r["frames"]
  topts[:rate] = r["rate"]
  topts[:tc_start] = r["tc_start"]
  topts[:chapters] = chs if chs.size > 0
  ck = Transcode.check(out, topts)
  << MediaVerify.format(ck)
  ck[:ok] ? 0 : 1

-> cmd_mux(args)
  p = Project.new(args[1], opt_arg(args, "--cut", "full"))
  p.verify_assets(true)
  r = p.resolve
  p.write_resolved(p.resolved_path)
  out = opt_arg(args, "--out", p.out_path("master.mp4"))
  opts = {}
  fr = opt_arg(args, "--frames", nil)
  opts["frames"] = fr.to_i if fr != nil
  fr = opt_arg(args, "--to", nil)
  opts["frames"] = fr.to_i if fr != nil
  fr = opt_arg(args, "--from", nil)
  opts["from"] = fr.to_i if fr != nil
  opts["audio"] = false if args.include?("--no-audio")
  opts["edit_lists"] = false if args.include?("--no-edit-lists")
  opts["audio_codec"] = opt_arg(args, "--audio-codec", nil)
  res = mux_master(p, r, out, opts)
  << "mux: " + res[0].to_s + " frames from " + r["segments"].size.to_s + " segments (passthrough) + mix -> " + out + " in " + res[1].to_s + " ms"
  << "mux facts: " + res[2].to_s if res.size > 2
  0

-> opt_arg(args, name, default)
  i = 0
  while i < args.size
    return args[i + 1] if args[i] == name && i + 1 < args.size
    i += 1
  default

# ---------------------------------------------------------------------------------------------- verify

-> probe_val(text, key)
  lines = text.split("\n")
  i = 0
  while i < lines.size
    ln = lines[i]
    return ln.slice(key.size + 1, ln.size - key.size - 1) if ln.starts_with?(key + "=")
    i += 1
  nil

-> check(results, name, ok, detail)
  results.push([name, ok, detail])
  tag = "  FAIL  "
  tag = "  PASS  " if ok
  msg = tag + name + ": " + detail.to_s
  << msg
  ok

# studio verify <master> [--resolved path] [--mix path]
-> cmd_verify(args)
  master = args[1]
  rp = opt_arg(args, "--resolved", nil)
  die("verify: --resolved <timeline.resolved.json> is required") if rp == nil
  r = JSON.parse(File.read(rp))
  num = r["rate"][0]
  den = r["rate"][1]
  sr = r["sr"]
  nfr = opt_arg(args, "--frames", r["frames"].to_s).to_i
  res = []
  << "verify " + master
  vo = {rate: [num, den], frames: nfr, tc_start: r["tc_start"]}
  vo[:edit_lists] = false if args.include?("--no-edit-lists")
  chs = chapter_list(r, 0, nfr)
  vo[:chapters] = chs if chs.size > 0
  mv = MediaVerify.check(master, vo)
  << "MediaVerify (core/media, AVFoundation):"
  << MediaVerify.format(mv)
  mv[:checks].each ->(c)
    res.push(["media:" + c[:name].to_s, c[:ok], c[:detail]])
  << "studio checks (native MediaVerify):"
  probe = MediaVerify.probe_streams(master)
  facts = mv[:facts]
  vstream = nil
  astream = nil
  tstream = nil
  probe["streams"].each ->(st)
    vstream = st if st["codec_type"] == "video" && vstream == nil
    astream = st if st["codec_type"] == "audio" && astream == nil
    tstream = st if st["codec_tag_string"] == "tmcd" && tstream == nil
  vcname = vstream == nil ? "" : vstream["codec_name"].to_s
  vw = vstream == nil ? 0 : vstream["width"]
  vh = vstream == nil ? 0 : vstream["height"]
  check(res, "video stream", (vcname == "h264" || vcname == "hevc" || vcname == "prores") && vw == r["w"] && vh == r["h"], vcname + " " + vw.to_s + "x" + vh.to_s)
  rate = num.to_s + "/" + den.to_s
  rfr = vstream == nil ? "" : vstream["r_frame_rate"].to_s
  afr = vstream == nil ? "" : vstream["avg_frame_rate"].to_s
  check(res, "CFR " + rate, rfr == rate && afr == rate, "r_frame_rate " + rfr + ", avg " + afr)
  vframes = facts[:video_frames]
  check(res, "frame count", vframes == nfr, vframes.to_s + " of " + nfr.to_s)
  bad_pts = facts[:pts_off] == nil ? 0 : facts[:pts_off]
  bad_dur = facts[:dur_off] == nil ? 0 : facts[:dur_off]
  tbd = facts[:video_timescale] == nil ? num : facts[:video_timescale]
  step = tbd * den / num
  check(res, "exact PTS", bad_pts == 0 && bad_dur == 0 && vframes == nfr, vframes.to_s + " packets, PTS = f * " + step.to_s + "/" + tbd.to_s + " s: " + bad_pts.to_s + " off, " + bad_dur.to_s + " durations != " + step.to_s)
  tc = tstream == nil ? facts[:tmcd_string] : get(tstream, "tags", {})["timecode"]
  has_tmcd = tstream != nil || facts[:tmcd] == true
  check(res, "tmcd " + r["tc_start"], has_tmcd && tc == r["tc_start"], "tmcd track " + (has_tmcd ? "present" : "missing") + ", timecode " + tc.to_s)
  csp = vstream == nil ? "" : vstream["color_space"].to_s
  cpr = vstream == nil ? "" : vstream["color_primaries"].to_s
  ctr = vstream == nil ? "" : vstream["color_transfer"].to_s
  crg = vstream == nil ? "" : vstream["color_range"].to_s
  cloc = vstream == nil ? "" : vstream["chroma_location"].to_s
  ok = csp == "bt709" && cpr == "bt709" && ctr == "bt709" && crg == "tv"
  check(res, "BT.709 tags", ok, "matrix " + csp + ", primaries " + cpr + ", transfer " + ctr + ", range " + crg + ", chroma " + cloc)
  if astream == nil
    check(res, "audio", false, "no audio stream")
  else
    na = facts[:audio_samples] == nil ? 0 : facts[:audio_samples]
    want = nfr * sr * den / num
    check(res, "audio length = video length", na == want, na.to_s + " samples decoded, " + want.to_s + " expected (" + nfr.to_s + " frames x " + (sr * den / num).to_s + ")")
    mixp = opt_arg(args, "--mix", nil)
    if mixp != nil
      wav_tmp = p_tmp(master) + ".verify.wav"
      MediaVerify.prepare_audio(master, wav_tmp, sample_rate: sr, channels: 2)
      lag = sync_lag(wav_tmp, mixp, sr)
      File.delete(wav_tmp) if File.exist?(wav_tmp)
      check(res, "sync marker", lag[0] == 0 || lag[0] == 1 || lag[0] == -1, "decoded audio vs the mix at " + lag[1].to_s + " onsets: lag " + lag[0].to_s + " samples (picture frame 0 = audio sample 0)")
  fails = 0
  res.each ->(x)
    fails += 1 if !x[1]
  head = "verify: FAIL ("
  head = "verify: PASS (" if fails == 0
  msg = head + (res.size - fails).to_s + "/" + res.size.to_s + ")"
  << msg
  fails == 0 ? 0 : 1

-> p_tmp(master)
  master

# The sync marker: the narration onsets in the mix (the loudest attack per minute) located again in the decoded
# master by cross-correlation over +-2000 samples. The lag is the same at every onset when the container's priming
# and edit list are right; 0 means audio sample 0 sits on picture frame 0.
-> sync_lag(wav_path, mix_path, sr)
  dec = read_wav_f32(wav_path)
  dv = dec[0]
  mix = read_wav_f32(mix_path)
  n = [dv.size, mix[0].size].min
  lags = {}
  count = 0
  t = sr * 30
  while t + sr * 2 < n / 2 && count < 12
    best = 0
    besti = -1
    i = t
    e = t + sr * 60
    e = n / 2 - sr * 2 if e > n / 2 - sr * 2
    while i < e
      v = mix[0][i * 2].abs
      if v > best
        best = v
        besti = i
      i += 256
    if besti > 0
      lag = xcorr_lag(dv, mix[0], besti, 4096, 2000)
      lags[lag] = get(lags, lag, 0) + 1
      count += 1
    t += sr * 180
  top = 0
  topn = -1
  lags.keys.each ->(k)
    if lags[k] > topn
      topn = lags[k]
      top = k
  [top, count]

-> xcorr_lag(a, b, at, win, maxlag) (f32[] f32[] i64 i64 i64) i64
  best = (~0.0 - ~1.0e300)
  bl = 0
  l = 0 - maxlag
  while l <= maxlag
    s = ~0.0
    i = at
    while i < at + win
      s = s + (a[(i + l) * 2] ## f64) * (b[i * 2] ## f64)
      i += 1
    if s > best
      best = s
      bl = l
    l += 1
  bl
