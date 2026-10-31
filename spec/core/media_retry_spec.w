# spec: compiled -- delivery uses the compiled OS/clock/file intrinsics
# spec: interpreter-rejects -- media delivery is compiled-only
# Delivery transaction: the native encoder is replaced by a deterministic
# writer to exercise retry, cleanup and publication failure paths.
TMP = "/tmp/tungsten_delivery_contract_" + OS.capture("echo $PPID").strip()
Dir.mkdir_p(TMP)
out = TMP + "/published.mp4"
File.write(out, "previous")
attempts = [0]
encode = ->(src, dst, opts)
  attempts[0] = attempts[0] + 1
  File.write(dst, "partial")
  raise "VideoToolbox dropped a frame" if attempts[0] < 3
  File.write(dst, "complete")
  {frames: 1}
r = Transcode.deliver("source.mp4", out, {retries: 2, retry_delay: 0}, encode)
raise "wrong attempts" if attempts[0] != 3 || r[:attempts] != 3
raise "partial publication" if File.read(out) != "complete"

fail = ->(src, dst, opts)
  File.write(dst, "incomplete")
  raise "VideoToolbox dropped a frame"
msg = nil
begin
  Transcode.deliver("source.mp4", out, {retries: 1, retry_delay: 0}, fail)
rescue e
  msg = e.to_s
raise "retry exhaustion" if msg == nil || !msg.include?("dropped a frame") || File.read(out) != "complete"
File.entries(TMP).each ->(name)
  raise "temporary file leaked" if name.include?(".transcode-")
raise "HEVC level contract" if !Transcode.level_pinnable?(:hevc10) || !Transcode.level_pinnable?(:h264)
raise "HEVC level 2" if Transcode.min_level(:hevc10, 320, 180, [24, 1])[1] != 60
raise "retry classification" if Transcode.retryable?("missing input")
OS.system("rm -rf " + TMP)
<< "PASS media delivery transaction"
