require "json"
require "tmpdir"
require "open3"
ROOT = File.realpath(File.join(__dir__, "../../.."))
Dir.mktmpdir("av-native-formats-") do |root|
  tools = File.join(root, "tools")
  Dir.mkdir(tools)
  ENV.fetch("PATH").split(":").concat(["/usr/bin", "/bin"]).uniq.each do |dir|
    next unless File.directory?(dir)
    Dir.children(dir).each do |name|
      next if name =~ /python|pyenv|ffmpeg|ffprobe/i
      path = File.join(dir, name)
      link = File.join(tools, name)
      File.symlink(path, link) if File.file?(path) && File.executable?(path) && !File.exist?(link)
    end
  end
  raise "Python or FFmpeg visible in test PATH" if Dir.children(tools).any? { |n| n =~ /python|pyenv|ffmpeg|ffprobe/i }
  run = lambda do |*args|
    out, err, status = Open3.capture3({"PATH" => tools, "BASH_ENV" => nil, "TW_PYTHON" => "/no/python"}, *args.map(&:to_s), chdir: ROOT)
    raise "#{args.join(' ')}: #{out}\n#{err}" unless status.success?
    out
  end
  source = File.join(root, "source.mov")
  tone_wav = File.join(root, "tone.wav")
  samples = 48_000 * 2
  pcm = Array.new(samples * 2) { |i| (Math.sin(2.0 * Math::PI * 440.0 * (i / 2) / 48_000.0) * 8000).round }.pack("s<*")
  File.binwrite(tone_wav, "RIFF" + [36 + pcm.bytesize].pack("V") + "WAVEfmt " + [16, 1, 2, 48_000, 48_000 * 4, 4, 16].pack("VvvVVvv") + "data" + [pcm.bytesize].pack("V") + pcm)
  fixture_w = File.join(root, "make_source.w")
  File.write(fixture_w, <<~W)
    a = argv()
    enc = VideoEncoder.new(160, 90, {codec: :prores422hq, rate: [24, 1], quality: ~1.0, input: :rgb24})
    rgb = u8[160 * 90 * 3]
    f = 0
    while f < 48
      enc.encode(rgb, 160 * 3)
      f += 1
    seg = enc.segment
    enc.close
    seg_path = a[0] + ".seg"
    seg.save(seg_path)
    seg.release
    mux = Mux.new(a[0], {rate: [24, 1], frames: 48, tc_start: "00:00:00:00", audio: a[1], audio_codec: :pcm, edit_lists: false})
    mux.append_file(seg_path)
    mux.close
    File.delete(seg_path)
  W
  run.call(File.join(ROOT, "bin/tungsten"), fixture_w, "--", source, tone_wav)
  content = "av.project \"formats\", source: \"source.mov\", toolchain: #{ROOT.to_json}\nav.colour \"all\", untagged: :bt709\nav.resources memory_mb: 1024, jobs: 1, disk_reserve_mb: 0, timeout: 300\n"
  %w[s16le s24le s32le f32le].each do |format|
    content += "av.output #{format.to_json}\nav.video #{format.to_json}, codec: :prores422lt\nav.audio #{format.to_json}, codec: :pcm, sample_format: :#{format}, sample_rate: 44100, channels: 1\n"
  end
  File.write(File.join(root, "Bitfile"), content)
  result = JSON.parse(run.call(File.join(ROOT, "bin/bit"), "av", "render", "--project", root, "--json").lines.reverse.find { |l| l.start_with?("{") })
  raise "render formats" unless result["status"] == "complete"
  %w[s16le s24le s32le f32le].each do |format|
    probe = JSON.parse(run.call(File.join(ROOT, "bin/tungsten"), "-e", "<< JSON.encode(MediaVerify.probe_streams(argv()[0]))", "--", File.join(root, "render/#{format}.mov")).lines.last)
    audio = probe["streams"].find { |s| s["codec_type"] == "audio" }
    raise "wrong audio contract" unless [audio["codec_name"], Integer(audio["sample_rate"]), audio["channels"]] == ["pcm_#{format}", 44100, 1]
  end
  puts "PASS native PCM16/24/32/float delivery, 44.1kHz mono conversion and independent verification"
end
