# Small native bridge shared by package commands; one cached compiled program.
a = argv()
command = a[0]
if command == "capabilities"
  available = VideoEncoder.available?
  codecs = []
  backends = []
  identity = nil
  if available
    codecs = VideoEncoder.codecs
    backends = Scaler.backends
    identity = ccall("w_media_runtime_identity")
  << JSON.encode({available: available, codecs: codecs, backends: backends, implementation: identity})
  exit(0)
if command == "facts"
  f = Transcode.source_facts(a[1])
  info = f[:facts]
  << JSON.encode({width: info[:width], height: info[:height], rate: f[:rate], frames: f[:frames], tc: f[:tc], tc_label: f[:tc] == nil ? nil : Timecode.to_smpte(f[:tc], f[:rate], f[:drop]), drop: f[:drop], chapters: f[:chapters], codec: info[:codec], bit_depth: info[:bit_depth], audio_rate: info[:audio_rate], audio_channels: info[:audio_channels]})
  exit(0)
if command == "encoder"
  options = JSON.parse(a[3])
  spec = {}
  options.keys.each ->(key)
    spec[key.to_sym] = options[key]
  encoder = VideoEncoder.new(a[1].to_i, a[2].to_i, spec)
  encoder.close
  << JSON.encode({ok: true})
  exit(0)
if command == "timecode"
  r = JSON.parse(a[2])
  frame = Timecode.parse(a[1], r) + a[3].to_i
  << JSON.encode(Timecode.to_smpte(frame, r, a[1].include?(";")))
  exit(0)
if command == "segment"
  segment = VideoSegment.load(a[1])
  << JSON.encode({frames: segment.frames, width: segment.width, height: segment.height})
  segment.release
  exit(0)
request = JSON.parse(File.read(a[1]))
opts = {}
request["options"].keys.each ->(key)
  opts[key.to_sym] = request["options"][key]
if command == "transcode"
  result = Transcode.run(request["source"], request["destination"], opts)
  << JSON.encode(result)
  exit(0)
if command == "verify"
  result = Transcode.check(request["source"], opts)
  << JSON.encode({ok: result[:ok], checks: result[:checks]})
  exit(result[:ok] ? 0 : 1)
raise "unknown native AV command"
