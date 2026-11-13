# Native command acceptance tests. Ruby is the test harness, never an AV runtime.
require "json"
require "tmpdir"
require "fileutils"
require "open3"
require "timeout"
ROOT = File.realpath(File.join(__dir__, "../../.."))
Dir.mktmpdir("av-native-integration-") do |root|
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
  env = {"PATH" => tools, "BASH_ENV" => nil, "TW_PYTHON" => "/missing/python", "BIT_HOME" => File.join(root, "bits")}
  run = lambda do |*args|
    stdout, stderr, status = Open3.capture3(env, *args.map(&:to_s), chdir: ROOT)
    raise "#{args.join(' ')} failed:\n#{stdout}\n#{stderr}" unless status.success?
    stdout
  end
  cli = lambda do |command, *args|
    text = run.call(File.join(ROOT, "bin/bit"), "av", command, "--project", root, "--json", *args)
    JSON.parse(text.lines.reverse.find { |line| line.start_with?("{") })
  end
  raise "Python or FFmpeg visible in test PATH" if Dir.children(tools).any? { |n| n =~ /python|pyenv|ffmpeg|ffprobe/i }
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
      y = 0
      while y < 90
        x = 0
        while x < 160
          i = (y * 160 + x) * 3
          rgb[i] = ((x * 3 + f * 5) % 220) + 16
          rgb[i + 1] = ((y * 2 + f * 3) % 220) + 16
          rgb[i + 2] = (((x + y + f * 7)) % 220) + 16
          x += 1
        y += 1
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
  FileUtils.rm_f([tone_wav, fixture_w])
  base = "name \"fixture\"\nav.project \"fixture\", source: \"source.mov\", toolchain: #{ROOT.to_json}\nav.colour \"all\", untagged: :bt709\nav.resources memory_mb: 1024, jobs: 1, disk_reserve_mb: 0, timeout: 300\n"
  declarations = "av.output \"master\"\nav.video \"master\", codec: :prores422hq\nav.output \"share\", from: \"master\", format: :mp4\nav.video \"share\", codec: :h264, bitrate: \"1000k\"\nav.audio \"share\", codec: :aac, bitrate: \"192k\"\nav.publish \"upload\", root: \"upload\", profiles: [\"master\", \"share\"]\n"
  File.write(File.join(root, "Bitfile"), base + declarations)
  raise "doctor failed" unless cli.call("doctor")["ok"]
  puts "PASS native doctor without Python"
  raise "plan failed" unless cli.call("plan", "--profile", "share")["profiles"].keys == ["master", "share"]
  raise "plan wrote project artifacts" if File.exist?(File.join(root, ".av"))
  puts "PASS read-only plan and dependencies"
  state = cli.call("render")
  raise "render failed" unless state["status"] == "complete" && state["outputs"].size == 2
  master = File.join(root, "render/master.mov")
  raise "delivery alias missing" unless File.symlink?(master)
  raise "verification failed" unless cli.call("verify")["ok"]
  puts "PASS native source render, AAC share and exact-byte verify"
  raise "stage failed" unless cli.call("stage")["ok"] && File.symlink?(File.join(root, "upload/master.mov"))
  puts "PASS verified atomic stage"
  old = File.binread(master)
  File.write(File.join(root, "Bitfile"), base + declarations + "av.loudness \"master\", enabled: true, target: -1, tolerance: 0.01\n")
  stdout, stderr, status = Open3.capture3(env, File.join(ROOT, "bin/bit"), "av", "render", "--project", root, "--json", chdir: ROOT)
  raise "failed QC activated output" if status.success? || File.binread(master) != old
  puts "PASS failed QC preserves prior release"
  quality = "av.output \"share\", format: :mp4\nav.video \"share\", codec: :h264\nav.audio \"share\", codec: :none\nav.quality \"share\", mode: :search, minimum_bitrate: \"400k\", maximum_bitrate: \"1500k\", max_probes: 3, probe_frames: 12, sample_frames: [0,24,36], minimum_ssim: 0.90\n"
  File.write(File.join(root, "Bitfile"), base + quality)
  probes = cli.call("quality", "--profile", "share")
  raise "bitrate probe failed" unless probes["quality"]["share"]["ok"] && !probes.key?("release")
  puts "PASS bounded native bitrate probes without activation"
  puts "Native acceptance fixtures: #{root}" if ENV["KEEP_AV_FIXTURES"]
end
