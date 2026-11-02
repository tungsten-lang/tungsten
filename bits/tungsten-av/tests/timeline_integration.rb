require "json"
require "tmpdir"
require "fileutils"
require "open3"
ROOT = File.realpath(File.join(__dir__, "../../.."))
Dir.mktmpdir("av-native-timeline-") do |dir|
  root = File.realpath(dir)
  run = lambda do |*args|
    out, err, status = Open3.capture3({"BASH_ENV" => nil, "TW_PYTHON" => "/no/python"}, *args.map(&:to_s), chdir: root)
    raise "#{args.join(' ')} failed: #{out}\n#{err}" unless status.success?
    out
  end
  run.call("ffmpeg", "-nostdin", "-v", "error", "-y", "-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo", "-t", "2", "-c:a", "pcm_s16le", File.join(root, "mix.wav"))
  cut = {w: 160, h: 90, rate: [24, 1], sr: 48000, tc_start: "01:00:00:00", colour: "bt709", end: {ref: "start", ms: 2000}, picture: {active: [0, 0, 160, 90]}}
  document = {schema: "studio.episode/2", id: "caption-test", root: ".", cuts: {preview: cut}, assets: {}, styles: {}, lines: [], cues: [], captions: [], markers: []}
  File.write(File.join(root, "scene.w"), <<~W)
    a = argv()
    raise "wrong clock" if env("TW_RATE_NUM") != "24" || env("TW_RATE_DEN") != "1"
    c = Canvas.new(160, 90)
    c.clear("#000000")
    i = a[0].to_i
    while i <= a[1].to_i
      c.write_png(a[2] + "/" + Motion.pad(i, 5) + ".png")
      i += 1
    c.close
  W
  document[:shots] = [{id: "program", kind: "program", at: {ref: "start", ms: 0}, trans_in: {kind: "cut", frames: 0}, program: {source: "scene.w", data: [], run: ["{first}", "{last}", "{dir}"], frames: "{dir}/%05d.png", count: "dur"}}, {id: "black", kind: "black", at: {ref: "start", ms: 1000}, trans_in: {kind: "cut", frames: 0}}]
  %w[edit short].each { |name| File.write(File.join(root, "#{name}.json"), JSON.generate(document)) }
  File.write(File.join(root, "captions.srt"), "1\n00:00:00,250 --> 00:00:01,750\nHello\n")
  File.write(File.join(root, "Bitfile"), <<~BIT)
    name "caption-test"
    av.project "caption-test", timeline: "edit.json", cut: "preview", mix: "mix.wav", toolchain: #{ROOT.to_json}
    av.output "master"
    av.output "short", timeline: "short.json", cut: "preview", mix: "mix.wav"
    av.video "all", codec: :prores422hq
    av.audio "all", codec: :pcm
    av.subtitles "captions.srt", mode: :timeline, language: "en"
    av.text "all", enabled: true, burned: true, font: "/System/Library/Fonts/Supplemental/Arial.ttf", size: 12, minimum_size: 10, box: [0.05,0.6,0.9,0.35]
    av.anomalies "all", enabled: true, black_min: 0.5, freeze_min: 0.5, allow_black: [[0,1]], allow_freeze: [[0,1]]
    av.resources memory_mb: 1024, jobs: 1, disk_reserve_mb: 0, timeout: 300
  BIT
  # Run the package from a registry install outside the toolchain source tree.
  package = File.join(root, "installed-av")
  FileUtils.mkdir_p(package)
  %w[Bitfile lib commands native].each { |name| FileUtils.cp_r(File.join(ROOT, "bits/tungsten-av", name), package) }
  registry = File.join(root, "registry")
  FileUtils.mkdir_p(File.join(registry, "av"))
  File.symlink(package, File.join(registry, "av/current"))
  ENV["BIT_HOME"] = registry
  cli = lambda do |command|
    JSON.parse(run.call(File.join(ROOT, "bin/bit"), "av", command, "--project", root, "--json").lines.reverse.find { |l| l.start_with?("{") })
  end
  file_list = JSON.parse(run.call(File.join(ROOT, "bin/bit"), "av", "files", "--json").lines.last)
  library_entry = file_list.find { |item| item["purpose"] == "Native library entry point" }
  raise "files reports a different package" unless library_entry["path"] == File.join(package, "lib/av.w")
  plan = cli.call("plan")
  raise "alternate plan missing" unless plan["profiles"]["short"]["timeline"]["frames"] == 48
  raise "plan generated project artifacts" if File.exist?(File.join(root, ".av"))
  state = cli.call("render")
  %w[master short].each do |name|
    checks = state["outputs"][name]["verification"]["checks"]
    raise "caption/anomaly QC failed" unless checks["encoded_text"]["ok"] && checks["anomalies"]["ok"]
    raise "subtitle sidecar absent" unless File.symlink?(File.join(root, "render/#{name}.en.srt"))
  end
  puts "PASS native frozen program timelines, alternate Short, exact-font burn and encoded ROI/anomaly QC"
  previous_path = File.realpath(File.join(root, "render/master.mov"))
  previous = File.binread(previous_path)
  repeat = cli.call("render")
  raise "resume missed verified frames" unless repeat["outputs"].values.all? { |o| o["result"]["resumed_frames"] == 48 }
  raise "resume changed the immutable previous release" unless previous == File.binread(previous_path)
  raise "frozen verify failed" unless cli.call("verify")["ok"]
  puts "PASS native resume and frozen verification"
end
