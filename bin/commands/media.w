# tungsten media — check and probe video masters (core/media).
#
#   bin/tungsten media verify FILE [--rate 24/1] [--frames N] [--tc HH:MM:SS:FF | --no-tc]
#                                  [--no-audio] [--sync] [--flashes 12,60,...] [--bars]
#                                  [--siting left] [--no-faststart] [--json]
#   bin/tungsten media sync-test OUT [--rate 24/1] [--seconds 10] [--size 1280x720]
#                                    [--codec h264] [--tc HH:MM:SS:FF] [--audio aac|pcm]
#   bin/tungsten media probe FILE      raw AVFoundation facts
#   bin/tungsten media codecs          codecs VideoToolbox opens here
#   bin/tungsten media tc FRAME RATE   frame index -> SMPTE label (and back for a label)
#
# verify exits 0 when every check passes, 1 otherwise.

-> usage
  << "usage: tungsten media verify FILE \[--rate N/D] \[--frames N] \[--tc HH:MM:SS:FF | --no-tc] \[--no-audio] \[--sync] \[--flashes a,b,...] \[--bars] \[--siting S] \[--no-faststart] \[--json]"
  << "       tungsten media sync-test OUT \[--rate N/D] \[--seconds S] \[--size WxH] \[--codec C] \[--tc HH:MM:SS:FF] \[--audio aac|pcm]"
  << "       tungsten media probe FILE"
  << "       tungsten media codecs"
  << "       tungsten media tc FRAME|HH:MM:SS:FF RATE"
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
    else
      << "unknown option [a]"
      exit(2)
    i += 1
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
