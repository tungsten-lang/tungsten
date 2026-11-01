# spec: compiled -- native Canvas and the AV companion are platform APIs
use ../lib/av
-> check(name, condition)
  raise "FAIL [name]" if !condition
  << "PASS [name]"
root = File.join(Env.get("TMPDIR") || "/tmp", "av-banding-" + Av:Util.id())
File.mkdir_p(root)
begin
  width = 96
  height = 64
  raw = u8[width * height * 3]
  i = 0
  while i < raw.size
    raw[i] = 100
    i += 1
  gradient = {"cx": ~0.5, "cy": ~0.5, "r": 1, "mid": ~0.5, "colors": [[100,100,100],[100,100,100],[100,100,100]]}
  error = Av:Banding.residual(raw, width, height, 8, gradient)
  mask = Av:Banding.mask(raw, raw, width, height, [])
  metrics = Av:Banding.metrics(error, mask, width, height)
  check("analytical residual", metrics["rms"] < ~1e-10 && metrics["p99"] < ~1e-10)
  check("usable background", metrics["bg_frac"] > ~0.2)
  delta = Av:Banding.temporal_delta(error, error, mask, mask, width * height)
  check("adjacent-frame residual", Av:Banding.metrics(delta[0], delta[1], width, height)["rms"] < ~1e-10)
  excluded = Av:Banding.mask(raw, raw, width, height, [[0, 0, width, height]])
  rejected = false
  begin
    Av:Banding.metrics(error, excluded, width, height)
  rescue problem
    rejected = true
  check("no pass without usable samples", rejected)
  File.mkdir_p(root + "/anim")
  File.write(root + "/anim/core.w", "<radialGradient cx=\"50%\" cy=\"40%\" r=\"80%\">\n<stop offset=\"0\" stop-color=\"#131b2c\"/>\n<stop offset=\"55%\" stop-color=\"#090d15\"/>\n<stop offset=\"1\" stop-color=\"#04060a\"/>\n</radialGradient>")
  authored = Av:Banding.gradient(root, false)
  check("authored gradient", authored["cx"] == ~0.5 && authored["mid"] == ~0.55 && authored["colors"][0] == [19,27,44])
  # The same native kernel checks an actual encoded file and writes diagnostics.
  source = Canvas.new(width, height)
  source.clear("#646464")
  source.write_png(root + "/background.png")
  source.close
  media = Av:Media.new(Av:Util.absolute("../../..", __DIR__), Av:Util.absolute("..", __DIR__), Av:Runner.new(120))
  media.ffmpeg(["-v", "error", "-y", "-loop", "1", "-i", root + "/background.png", "-t", "1", "-r", "24", "-c:v", "prores_ks", "-profile:v", "3", "-pix_fmt", "yuv422p10le", "-color_primaries", "bt709", "-color_trc", "bt709", "-colorspace", "bt709", root + "/movie.mov"])
  File.write(root + "/Bitfile", "av.project \"banding\", source: \"movie.mov\"\n")
  project = Av:Project.load(root)
  spec = {"background": "background.png", "gradient": gradient, "samples": [{"frame": 7, "source": "background.png", "next_source": "background.png"}], "limits": {"rms_detrended": 1, "p99": 2, "blk16": 5, "temporal_rms": ~0.1}}
  plan = {"width": width, "height": height, "rate": [24,1], "frames": 24, "start": 0, "profile": {"banding": spec}}
  File.mkdir_p(root + "/checks")
  result = Av:Banding.run(project, media, root + "/movie.mov", plan, root + "/checks", nil)
  check("native encoded banding", result["ok"])
  check("native diagnostics", File.file?(root + "/checks/banding/contact-sheet.jpg") && File.file?(root + "/checks/banding.html"))
ensure
  Av:Util.remove_tree(root)
