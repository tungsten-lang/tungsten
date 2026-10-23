# tungsten media — check and probe video masters (core/media).
#
#   bin/tungsten media verify FILE [--rate 24/1] [--frames N] [--tc HH:MM:SS:FF | --no-tc]
#                                  [--no-audio] [--sync] [--flashes 12,60,...] [--bars]
#                                  [--siting left] [--no-faststart] [--chapters FILE] [--json]
#   bin/tungsten media sync-test OUT [--rate 24/1] [--seconds 10] [--size 1280x720]
#                                    [--codec h264] [--tc HH:MM:SS:FF] [--audio aac|pcm]
#   bin/tungsten media probe FILE      raw AVFoundation facts
#   bin/tungsten media codecs          codecs VideoToolbox opens here
#   bin/tungsten media tc FRAME RATE   frame index -> SMPTE label (and back for a label)
#   bin/tungsten media transcode IN OUT [--size WxH] [--fit stretch|contain|cover] [--filter lanczos3|bicubic|bilinear]
#                                       [--codec h264|hevc|hevc10] [--quality Q | --kbps N] [--level 4.1] [--gop N]
#                                       [--audio copy|aac|pcm|none] [--audio-kbps N] [--audio-src WAV|MOVIE]
#                                       [--rate N/D] [--start F] [--frames N] [--via yuv|rgb] [--backend auto|metal|vimage|cpu]
#                                       [--chapters FILE | --no-chapters] [--tc HH:MM:SS:FF | --no-tc] [--verify] [--quiet]
#   bin/tungsten media preset NAME IN OUT [the transcode options]   a preset, then verify (--no-verify skips)
#   bin/tungsten media presets         the presets
#
# IN is a movie, or a list of segment files (a text file of paths, or of
# ffmpeg concat lines "file '...'", as apps/studio writes segments.txt).
# --chapters FILE reads "HH:MM:SS:FF title" or "frame title" lines (or the
# engine's chapters.txt "MM:SS title" lines, whole seconds).
# verify, transcode --verify and preset exit 0 when every check passes, 1 otherwise.

-> usage
  << "usage: tungsten media verify FILE \[--rate N/D] \[--frames N] \[--tc HH:MM:SS:FF | --no-tc] \[--no-audio] \[--sync] \[--flashes a,b,...] \[--bars] \[--siting S] \[--no-faststart] \[--chapters FILE] \[--json]"
  << "       tungsten media sync-test OUT \[--rate N/D] \[--seconds S] \[--size WxH] \[--codec C] \[--tc HH:MM:SS:FF] \[--audio aac|pcm]"
  << "       tungsten media probe FILE"
  << "       tungsten media codecs"
  << "       tungsten media tc FRAME|HH:MM:SS:FF RATE"
  << "       tungsten media transcode IN OUT \[--size WxH] \[--fit F] \[--filter F] \[--codec C] \[--quality Q | --kbps N] \[--level L] \[--gop N]"
  << "                                \[--audio copy|aac|pcm|none] \[--audio-kbps N] \[--audio-src PATH] \[--rate N/D] \[--start F] \[--frames N]"
  << "                                \[--via yuv|rgb] \[--backend B] \[--chapters FILE | --no-chapters] \[--tc HH:MM:SS:FF | --no-tc] \[--verify]"
  << "       tungsten media preset NAME IN OUT \[transcode options] \[--no-verify]"
  << "       tungsten media presets"
  exit(2)

args = argv()
if args.size < 1
  usage()
cmd = args[0]

-> flag_value(args, i)
  if i + 1 >= args.size
    << "missing value after [args[i]]"
    exit(2)
  args[i + 1]

if cmd == "codecs"
  << VideoEncoder.codecs.join(" ")
  exit(0)

if cmd == "tc"
  if args.size < 3
    usage()
  rate = Timecode.rate(args[2])
  if args[1].include?(":") || args[1].include?(";")
    << Timecode.parse(args[1], rate)
  else
    << Timecode.to_smpte(args[1].to_i, rate)
  exit(0)

if cmd == "presets"
  ps = Transcode.presets
  ps.keys.each ->(k)
    p = ps[k]
    br = p[:bitrate] == nil ? "q" + p[:quality].to_s : (p[:bitrate] / 1000).to_s + " kb/s"
    au = p[:audio] == "copy" ? "audio copy" : "AAC [p[:audio_kbps]]k"
    fit = p[:fit] == nil ? "" : ", fit [p[:fit]]"
    << "[k]: [p[:width]]x[p[:height]] [p[:codec]] [br], [au][fit], level cap [p[:level_cap]]"
  exit(0)

# Segment list: a text file of paths or ffmpeg concat lines.
-> read_list(path)
  out = []
  File.read(path).split("\n").each ->(line)
    l = line.strip()
    if l.size > 0 && l[0] != "#"
      if l.size > 6 && l[0...5] == "file "
        l = l[5...l.size].strip()
        if l.size >= 2 && (l[0] == "'" || l[0] == "\"")
          l = l[1...(l.size - 1)]
      out << l
  out

# Chapters file: "HH:MM:SS:FF title", "frame title" or "MM:SS title" / "H:MM:SS title" (seconds).
-> read_chapters(path, rate)
  out = []
  File.read(path).split("\n").each ->(line)
    l = line.strip()
    if l.size > 0 && l[0] != "#" && l[0] != ";"
      sp = l.index(" ")
      if sp != nil
        stamp = l[0...sp]
        title = l[(sp + 1)...l.size].strip()
        parts = stamp.split(":")
        f = 0
        if parts.size == 4 || stamp.include?(";")
          f = Timecode.parse(stamp, rate)
        elsif parts.size == 1
          f = stamp.to_i
        else
          secs = 0
          parts.each ->(x)
            secs = secs * 60 + x.to_i
          f = (secs * rate[0] + rate[1] - 1) / rate[1]
        out << [title, f]
  out

if cmd == "transcode" || cmd == "preset"
  base = cmd == "preset" ? 2 : 1
  if args.size < base + 2
    usage()
  opts = {}
  if cmd == "preset"
    opts[:preset] = args[1]
  src_arg = args[base]
  dst = args[base + 1]
  src = src_arg
  if src_arg.size > 4 && src_arg[(src_arg.size - 4)...src_arg.size] == ".txt"
    src = read_list(src_arg)
  verify = cmd == "preset"
  quiet = false
  chapters_file = nil
  i = base + 2
  while i < args.size
    a = args[i]
    if a == "--size"
      wh = flag_value(args, i).split("x")
      opts[:width] = wh[0].to_i
      opts[:height] = wh[1].to_i
      i += 1
    elsif a == "--fit"
      opts[:fit] = flag_value(args, i)
      i += 1
    elsif a == "--filter"
      opts[:filter] = flag_value(args, i)
      i += 1
    elsif a == "--codec"
      opts[:codec] = flag_value(args, i)
      i += 1
    elsif a == "--quality"
      opts[:quality] = flag_value(args, i).to_f
      opts[:bitrate] = nil
      i += 1
    elsif a == "--kbps"
      opts[:bitrate] = flag_value(args, i).to_i * 1000
      i += 1
    elsif a == "--level"
      opts[:level] = flag_value(args, i)
      i += 1
    elsif a == "--gop"
      opts[:gop] = flag_value(args, i).to_i
      i += 1
    elsif a == "--audio"
      v = flag_value(args, i)
      opts[:audio] = v == "none" ? false : v
      i += 1
    elsif a == "--audio-kbps"
      opts[:audio_kbps] = flag_value(args, i).to_i
      i += 1
    elsif a == "--audio-src"
      opts[:audio_src] = flag_value(args, i)
      i += 1
    elsif a == "--rate"
      opts[:rate] = flag_value(args, i)
      i += 1
    elsif a == "--start"
      opts[:start] = flag_value(args, i).to_i
      i += 1
    elsif a == "--frames"
      opts[:frames] = flag_value(args, i).to_i
      i += 1
    elsif a == "--via"
      opts[:via] = flag_value(args, i)
      i += 1
    elsif a == "--backend"
      opts[:scale_backend] = flag_value(args, i)
      i += 1
    elsif a == "--chapters"
      chapters_file = flag_value(args, i)
      i += 1
    elsif a == "--no-chapters"
      opts[:chapters] = false
    elsif a == "--tc"
      opts[:tc] = flag_value(args, i)
      i += 1
    elsif a == "--no-tc"
      opts[:tc] = false
    elsif a == "--verify"
      verify = true
    elsif a == "--no-verify"
      verify = false
    elsif a == "--quiet"
      quiet = true
    else
      << "unknown option [a]"
      exit(2)
    i += 1
  if type(src) == "Array" && opts[:audio] == nil && opts[:audio_src] == nil
    opts[:audio] = false
  if chapters_file != nil
    rate = opts[:rate] != nil ? Timecode.rate(opts[:rate]) : Transcode.source_facts(src)[:rate]
    opts[:chapters] = read_chapters(chapters_file, rate)
  opts[:progress] = !quiet
  r = Transcode.run(src, dst, opts)
  << "wrote [dst]: [r[:frames]] frames [r[:width]]x[r[:height]] [r[:codec]] in [(r[:seconds] * ~100.0).round.to_f / ~100.0] s ([(r[:fps] * ~10.0).round.to_f / ~10.0] fps), [r[:file_bytes]] bytes; scale [r[:scale_backend]] via [r[:via]] [(r[:scale_s] * ~100.0).round.to_f / ~100.0] s, decode [(r[:decode_s] * ~100.0).round.to_f / ~100.0] s, mux [(r[:mux_s] * ~100.0).round.to_f / ~100.0] s; [r[:duplicated]] repeated, [r[:dropped]] dropped; chapters [r[:chapters].size], tc [r[:tc_start]], audio [r[:audio]]"
  if verify
    vo = {rate: r[:rate], frames: r[:frames], tc_start: r[:tc_start], audio: r[:audio] != nil}
    if r[:chapters].size > 0
      vo[:chapters] = r[:chapters]
    if opts[:preset] != nil
      vo[:preset] = opts[:preset]
    else
      vo[:codec] = r[:codec]
      vo[:width] = r[:width]
      vo[:height] = r[:height]
    v = Transcode.check(dst, vo)
    << MediaVerify.format(v)
    exit(v[:ok] ? 0 : 1)
  exit(0)

if args.size < 2
  usage()
path = args[1]

if cmd == "probe"
  f = MediaVerify.facts(path, true, true)
  f.keys.each ->(k)
    v = f[k]
    if k == :pts || k == :durations || k == :dts
      v = "[v.size] values, first [v[0...4]]"
    << "[k]: [v]"
  exit(0)

if cmd == "sync-test"
  opts = {}
  i = 2
  while i < args.size
    a = args[i]
    if a == "--rate"
      opts[:rate] = flag_value(args, i)
      i += 1
    elsif a == "--seconds"
      opts[:seconds] = flag_value(args, i).to_i
      i += 1
    elsif a == "--size"
      wh = flag_value(args, i).split("x")
      opts[:width] = wh[0].to_i
      opts[:height] = wh[1].to_i
      i += 1
    elsif a == "--codec"
      opts[:codec] = flag_value(args, i)
      i += 1
    elsif a == "--tc"
      opts[:tc_start] = flag_value(args, i)
      i += 1
    elsif a == "--audio"
      opts[:audio_codec] = flag_value(args, i)
      i += 1
    else
      << "unknown option [a]"
      exit(2)
    i += 1
  t = MediaVerify.sync_test(path, opts)
  << "wrote [t[:path]]: [t[:frames]] frames, flashes at [t[:flashes]], clicks at samples [t[:clicks]] ([t[:sample_rate]] Hz), audio [t[:wav]]"
  << "check it: bin/tungsten media verify [t[:path]] --sync --bars --flashes [t[:flashes].join(",")]" + (opts.has_key?(:rate) ? " --rate " + opts[:rate] : "") + (opts.has_key?(:tc_start) ? " --tc " + opts[:tc_start] : "")
  exit(0)

if cmd == "verify"
  opts = {}
  json = false
  i = 2
  while i < args.size
    a = args[i]
    if a == "--rate"
      opts[:rate] = flag_value(args, i)
      i += 1
    elsif a == "--frames"
      opts[:frames] = flag_value(args, i).to_i
      i += 1
    elsif a == "--tc"
      opts[:tc_start] = flag_value(args, i)
      i += 1
    elsif a == "--no-tc"
      opts[:tc_start] = nil
    elsif a == "--no-audio"
      opts[:audio] = false
    elsif a == "--sync"
      opts[:sync] = true
    elsif a == "--flashes"
      fl = []
      flag_value(args, i).split(",").each ->(x)
        fl << x.to_i
      opts[:flashes] = fl
      i += 1
    elsif a == "--bars"
      opts[:bars] = true
    elsif a == "--siting"
      opts[:siting] = flag_value(args, i)
      i += 1
    elsif a == "--no-faststart"
      opts[:faststart] = false
    elsif a == "--json"
      json = true
    elsif a == "--chapters"
      opts[:chapters_file] = flag_value(args, i)
      i += 1
    else
      << "unknown option [a]"
      exit(2)
    i += 1
  if opts[:chapters_file] != nil
    crate = opts[:rate] != nil ? Timecode.rate(opts[:rate]) : Transcode.source_facts(path)[:rate]
    opts[:chapters] = read_chapters(opts[:chapters_file], crate)
  r = MediaVerify.check(path, opts)
  if json
    checks = []
    r[:checks].each ->(c)
      checks << {name: c[:name], ok: c[:ok], detail: c[:detail]}
    << JSON.encode({path: path, ok: r[:ok], frames: r[:frames], checks: checks})
  else
    << MediaVerify.format(r)
  exit(r[:ok] ? 0 : 1)

usage()
