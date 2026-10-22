# studio — the Tungsten timeline engine (TIMELINE.md §4).
#
#   studio resolve <episode.json> [--cut full]          -> build/<cut>/timeline.resolved.json (+ .srt, chapters)
#   studio diff <old.resolved.json> <new.resolved.json> -> changed frame ranges and segment keys
#   studio frame <episode.json> <f> [--png out] [--fresh]
#   studio render <episode.json> [--cut full] [--jobs N] [--max-frames N] [--from F --to F]
#   studio mix <episode.json>                           -> build/<cut>/mix.wav (+ loudness report)
#   studio mux <episode.json>                           -> build/<cut>/master.mp4, .srt, chapters.txt
#   studio verify <master> [--resolved path]
#   studio fcpxml <episode.json> [--cut full] [--out path] [--master path] -> FCPXML 1.11
#   studio share <episode.json> [--cut full] [--preset share]  -> build/<cut>/share.mp4 (Transcode from the master)
#
# Build: bin/tungsten -o apps/studio/bin/studio apps/studio/studio.w (under the heavy lock).

use lib/base
use lib/resolve
use lib/project
use lib/raster
use lib/render
use lib/encode
use lib/audio
use lib/mixplain
use lib/mux
use lib/fcpxml

-> opt(args, name, default)
  i = 0
  while i < args.size
    return args[i + 1] if args[i] == name && i + 1 < args.size
    i += 1
  default

-> flag?(args, name)
  args.include?(name)

-> cmd_resolve(args)
  p = Project.new(args[1], opt(args, "--cut", "full"))
  t0 = clock_ms()
  p.verify_assets(false)
  t1 = clock_ms()
  r = p.resolve
  t2 = clock_ms()
  out = opt(args, "--out", p.resolved_path)
  p.write_resolved(out)
  base = p.build + "/" + p.cut + "/"
  write_text(p.out_path("captions.srt"), srt_text(r))
  write_text(p.out_path("chapters.txt"), chapters_text(r))
  v1 = r["tracks"][0]["items"]
  << "resolved " + r["frames"].to_s + " frames (" + timecode(r["frames"], r["rate"][0], r["rate"][1]) + "), " + v1.size.to_s + " shots, " + r["intervals"].size.to_s + " intervals, " + r["segments"].size.to_s + " segments, " + r["samples"].to_s + " samples"
  << "assets " + (t1 - t0).to_s + " ms, resolve " + (t2 - t1).to_s + " ms -> " + out
  0

-> cmd_diff(args)
  a = JSON.parse(File.read(args[1]))
  b = JSON.parse(File.read(args[2]))
  d = diff_resolved(a, b)
  << "frames " + d["frames"][0].to_s + " -> " + d["frames"][1].to_s + "; segments " + d["segments"].to_s + ": " + d["reused"].to_s + " reused, " + d["new_segments"].to_s + " new (" + d["new_frames"].to_s + " frames to render)"
  << "items with a new recipe: " + d["changed_items"].join(" ") + "; items only moved: " + d["moved_items"].to_s
  d["ranges"].each ->(rg)
    << "  render \[" + rg[0].to_s + ", " + rg[1].to_s + ") " + (rg[1] - rg[0]).to_s + " frames: " + rg[2].join(" ")
  0

-> run_token
  Crypto.sha256(clock().to_s + ":" + Crypto.random_bytes(8).to_s).slice(0, 10)

# Workers are this binary (STUDIO_BIN overrides).
-> studio_bin
  b = env("STUDIO_BIN")
  return System.executable_path if b == nil || b == ""
  b

# studio frame <episode.json> <f> [--png out] [--yuv out] [--fresh]: one frame, from its stored segment (decoded)
# or rendered fresh.
-> cmd_frame(args)
  p = Project.new(args[1], opt(args, "--cut", "full"))
  f = args[2].to_i
  p.verify_assets(true)
  r = p.resolve
  die("frame " + f.to_s + " outside 0.." + (r["frames"] - 1).to_s) if f < 0 || f >= r["frames"]
  out = opt(args, "--png", nil)
  yuv = opt(args, "--yuv", nil)
  seg = nil
  si = 0
  segs = r["segments"]
  while si < segs.size && seg == nil
    seg = segs[si] if segs[si]["f0"] <= f && f < segs[si]["f0"] + segs[si]["n"]
    si += 1 if seg == nil
  sp = segment_path(p.build, seg["key"])
  tc = timecode(f, r["rate"][0], r["rate"][1])
  if !flag?(args, "--fresh") && File.exist?(sp)
    target = out
    target = yuv if yuv != nil
    target = p.build + "/frame.png" if target == nil
    die("decode failed") if !decode_segment_frame(sp, f - seg["f0"], target, yuv != nil, r["rate"])
    << "frame " + f.to_s + " (" + tc + ") from segment " + seg["key"].slice(0, 12) + " +" + (f - seg["f0"]).to_s + " -> " + target
    return 0
  p.ensure_program_frames(r, [si], 1)
  eng = Engine.new(p, r)
  t0 = clock_ms()
  eng.frame_into(f)
  t1 = clock_ms()
  target = out
  target = p.build + "/frame.png" if target == nil
  eng.write_png(target)
  << "frame " + f.to_s + " (" + tc + ") rendered fresh in " + (t1 - t0).to_s + " ms -> " + target
  eng.close
  0

# studio render <episode.json> [--jobs N] [--max-frames N] [--from F] [--to F]: render the missing segments, at
# most max-frames per call (one heavy-lock hold), split across N worker processes.
-> cmd_render(args)
  t0 = clock_ms()
  p = Project.new(args[1], opt(args, "--cut", "full"))
  p.verify_assets(true)
  r = p.resolve
  p.write_resolved(p.resolved_path)
  jobs = opt(args, "--jobs", "1").to_i
  budget = opt(args, "--max-frames", "400").to_i
  lo = opt(args, "--from", "0").to_i
  hi = opt(args, "--to", r["frames"].to_s).to_i
  segs = r["segments"]
  missing = []
  missing_frames = 0
  i = 0
  while i < segs.size
    s = segs[i]
    if s["f0"] + s["n"] > lo && s["f0"] < hi && !File.exist?(segment_path(p.build, s["key"]))
      missing.push(i)
      missing_frames += s["n"]
    i += 1
  take = []
  tf = 0
  mi = 0
  while mi < missing.size && (tf == 0 || tf + segs[missing[mi]]["n"] <= budget)
    take.push(missing[mi])
    tf += segs[missing[mi]]["n"]
    mi += 1
  if take.size == 0
    << "render: nothing to do (" + segs.size.to_s + " segments in place)"
    return 0
  mkdir_p(p.build + "/tmp")
  # program frames these segments need, rendered first (the programs run `jobs` at a time)
  p.ensure_program_frames(r, take, jobs)
  if jobs <= 1
    eng = Engine.new(p, r)
    enc = make_encoder(r, p.encoder, p.build + "/tmp/fifo." + run_token())
    render_segments(eng, enc, r, p.build, take)
    eng.close
  else
    lists = []
    loads = []
    j = 0
    while j < jobs
      lists.push([])
      loads.push(0)
      j += 1
    take.each ->(i3)
      best = 0
      j2 = 1
      while j2 < jobs
        best = j2 if loads[j2] < loads[best]
        j2 += 1
      lists[best].push(i3)
      loads[best] = loads[best] + segs[i3]["n"]
    procs = []
    tok = run_token()
    j = 0
    while j < jobs
      if lists[j].size > 0
        jf = p.build + "/tmp/job." + tok + "." + j.to_s + ".txt"
        File.write(jf, lists[j].join(","))
        procs.push(Process.spawn([studio_bin(), "worker", p.path, p.cut, jf]))
      j += 1
    bad = 0
    procs.each ->(pr)
      bad += 1 if pr.wait != 0
    die("render: " + bad.to_s + " worker(s) failed") if bad > 0
  dt = clock_ms() - t0
  << "render: " + tf.to_s + " frames in " + take.size.to_s + " segments, " + dt.to_s + " ms (" + ((tf * 1000) / [dt, 1].max).to_s + " fps); " + (missing_frames - tf).to_s + " frames (" + (missing.size - take.size).to_s + " segments) still missing"
  0

# studio raw <episode.json> <from> <to> <path>: frames [from, to) as packed RGB24 into path (a file or a FIFO),
# the pre-encode reference for quality metrics.
-> cmd_raw(args)
  p = Project.new(args[1], opt(args, "--cut", "full"))
  p.verify_assets(true)
  r = p.resolve
  a = args[2].to_i
  b = args[3].to_i
  idxs = []
  si = 0
  r["segments"].each ->(s)
    idxs.push(si) if s["f0"] < b && s["f0"] + s["n"] > a
    si += 1
  p.ensure_program_frames(r, idxs, 1)
  eng = Engine.new(p, r)
  fh = FileHandle.new(args[4], "wb")
  f = a
  while f < b
    fh.write(eng.frame_into(f))
    f += 1
  fh.close
  eng.close
  0

# studio gc <episode.json> [--dry]: delete stored segments that no resolved timeline in build/<cut>/ references.
-> cmd_gc(args)
  p = Project.new(args[1], opt(args, "--cut", "full"))
  keep = {}
  dir = p.build + "/" + p.cut
  File.entries(dir).each ->(nm)
    if nm.ends_with?("timeline.resolved.json")
      r = JSON.parse(File.read(dir + "/" + nm))
      r["segments"].each ->(s)
        keep[s["key"]] = 1
  sd = segment_dir(p.build)
  gone = 0
  bytes = 0
  File.entries(sd).each ->(nm)
    dot = nm.index(".")
    if dot != nil && keep[nm.slice(0, dot)] == nil
      bytes += File.size(sd + "/" + nm)
      File.delete(sd + "/" + nm) if !flag?(args, "--dry")
      gone += 1
  << "gc: " + keep.size.to_s + " segments referenced, " + gone.to_s + " unreferenced (" + (bytes / 1048576).to_s + " MB) " + (flag?(args, "--dry") ? "found" : "deleted")
  0

# studio worker <episode.json> <cut> <jobfile>: render the listed segments (spawned by render).
-> cmd_worker(args)
  p = Project.new(args[1], args[2])
  r = JSON.parse(File.read(p.resolved_path))
  idxs = []
  File.read(args[3]).split(",").each ->(x)
    idxs.push(x.to_i)
  eng = Engine.new(p, r)
  enc = make_encoder(r, p.encoder, args[3] + ".fifo")
  render_segments(eng, enc, r, p.build, idxs)
  eng.close
  File.delete(args[3])
  0

-> main(args)
  if args.size == 0
    << "usage: studio resolve|diff|frame|render|worker|mix|mux|verify|fcpxml|share|raw|gc|selftest ..."
    return 2
  c = args[0]
  return cmd_resolve(args) if c == "resolve"
  return cmd_diff(args) if c == "diff"
  return cmd_frame(args) if c == "frame"
  return cmd_render(args) if c == "render"
  return cmd_worker(args) if c == "worker"
  return cmd_mix_any(args) if c == "mix"
  return cmd_mux(args) if c == "mux"
  return cmd_verify(args) if c == "verify"
  return cmd_fcpxml(args) if c == "fcpxml"
  return cmd_share(args) if c == "share"
  return selftest() if c == "selftest"
  return cmd_raw(args) if c == "raw"
  return cmd_gc(args) if c == "gc"
  << "unknown command " + c
  2

code = main(argv())
exit(code) if code != 0
