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
      next if name =~ /python|pyenv/i
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
  raise "Python visible in test PATH" if Dir.children(tools).any? { |n| n =~ /python|pyenv/i }
  source = File.join(root, "source.mov")
  run.call("ffmpeg", "-nostdin", "-v", "error", "-y", "-f", "lavfi", "-i", "testsrc2=size=160x90:rate=24:duration=2", "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000:duration=2", "-c:v", "prores_ks", "-profile:v", "3", "-pix_fmt", "yuv422p10le", "-color_primaries", "bt709", "-color_trc", "bt709", "-colorspace", "bt709", "-color_range", "tv", "-movflags", "+write_colr", "-c:a", "pcm_s24le", "-ac", "2", source)
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
