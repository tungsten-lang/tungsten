require "json"
require "tmpdir"
require "open3"
ROOT = File.realpath(File.join(__dir__, "../../.."))
Dir.mktmpdir("av-native-formats-") do |root|
  run = lambda do |*args|
    out, err, status = Open3.capture3({"BASH_ENV" => nil, "TW_PYTHON" => "/no/python"}, *args.map(&:to_s), chdir: ROOT)
    raise "#{args.join(' ')}: #{out}\n#{err}" unless status.success?
    out
  end
  run.call("ffmpeg", "-nostdin", "-v", "error", "-y", "-f", "lavfi", "-i", "testsrc2=size=160x90:rate=24:duration=2", "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000:duration=2", "-c:v", "prores_ks", "-profile:v", "3", "-pix_fmt", "yuv422p10le", "-color_primaries", "bt709", "-color_trc", "bt709", "-colorspace", "bt709", "-c:a", "pcm_s24le", "-ac", "2", File.join(root, "source.mov"))
  content = "av.project \"formats\", source: \"source.mov\", toolchain: #{ROOT.to_json}\nav.colour \"all\", untagged: :bt709\nav.resources memory_mb: 1024, jobs: 1, disk_reserve_mb: 0, timeout: 300\n"
  %w[s16le s24le s32le f32le].each do |format|
    content += "av.output #{format.to_json}\nav.video #{format.to_json}, codec: :prores422lt\nav.audio #{format.to_json}, codec: :pcm, sample_format: :#{format}, sample_rate: 44100, channels: 1\n"
  end
  File.write(File.join(root, "Bitfile"), content)
  result = JSON.parse(run.call(File.join(ROOT, "bin/bit"), "av", "render", "--project", root, "--json").lines.reverse.find { |l| l.start_with?("{") })
  raise "render formats" unless result["status"] == "complete"
  %w[s16le s24le s32le f32le].each do |format|
    probe = JSON.parse(run.call("ffprobe", "-v", "error", "-show_streams", "-of", "json", File.join(root, "render/#{format}.mov")))
    audio = probe["streams"].find { |s| s["codec_type"] == "audio" }
    raise "wrong audio contract" unless [audio["codec_name"], Integer(audio["sample_rate"]), audio["channels"]] == ["pcm_#{format}", 44100, 1]
  end
  puts "PASS native PCM16/24/32/float delivery, 44.1kHz mono conversion and independent verification"
end
