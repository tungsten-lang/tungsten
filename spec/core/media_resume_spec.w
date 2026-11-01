# spec: compiled -- real native GOP checkpoints and failure recovery
# spec: interpreter-rejects -- media is compiled-only
passed = Atomic.new(0)
-> check(name, ok)
  raise "FAIL [name]" if !ok
  passed.increment()
  << "PASS [name]"
if !VideoEncoder.available?
  << "SKIP media_resume_spec: needs macOS"
  exit(0)
TMP = "/tmp/tungsten_media_resume_" + OS.capture("echo $PPID").strip()
Dir.mkdir_p(TMP)
MediaVerify.sync_test(TMP + "/src.mov", width: 160, height: 90, rate: [30000, 1001], seconds: 3, codec: :hevc10, chapters: [["Opening", 0]], tc_start: "01:00:00;00")
opts = {codec: :hevc10, width: 320, height: 180, audio: :pcm, edit_lists: false, gop: 16, resume_dir: TMP + "/cache", retries: 0}
File.write(TMP + "/out.mov", "previous release")
Env.set("TUNGSTEN_MEDIA_TEST_FAIL_AFTER", "65")
msg = nil
begin
  Transcode.run(TMP + "/src.mov", TMP + "/out.mov", opts)
rescue e
  msg = e.to_s
Env.delete("TUNGSTEN_MEDIA_TEST_FAIL_AFTER")
check("injected interruption leaves the published destination intact", msg != nil && msg.include?("injected") && File.read(TMP + "/out.mov") == "previous release")
r = Transcode.run(TMP + "/src.mov", TMP + "/out.mov", opts)
check("resume reuses complete closed GOPs and finishes the exact frame count", r[:resumed_frames] >= 16 && r[:resumed_frames] < 90 && r[:frames] == 90)
v = Transcode.check(TMP + "/out.mov", codec: :hevc10, frames: 90, rate: [30000, 1001], tc_start: "01:00:00;00", chapters: [["Opening", 0]], edit_lists: false, sync: true, flashes: [15, 75])
<< MediaVerify.format(v) if !v[:ok]
check("resumed NTSC delivery retains sample-exact audio, chapters and drop-frame timecode", v[:ok])
r = Transcode.run(TMP + "/src.mov", TMP + "/other.mov", opts)
check("destination-independent checkpoint identity permits complete replay", r[:resumed_frames] == 90 && r[:frames] == 90)
File.write(TMP + "/full_cancel", "stop")
full_cancel = opts.dup
full_cancel[:cancel_file] = TMP + "/full_cancel"
msg = nil
begin
  Transcode.run(TMP + "/src.mov", TMP + "/out.mov", full_cancel)
rescue e
  msg = e.to_s
check("a fully cached run honors cancellation before publication", msg != nil && msg.include?("cancelled"))
namespace = nil
File.entries(TMP + "/cache").each ->(name)
  namespace = TMP + "/cache/" + name if name != "." && name != ".."
# Another writer must not race checkpoint replacement.
lock_code = "import fcntl,pathlib,sys,time; f=open(sys.argv\[1], 'a'); fcntl.flock(f, fcntl.LOCK_EX); pathlib.Path(sys.argv\[2]).touch(); time.sleep(10)"
p = Process.spawn(["/usr/bin/python3", "-c", lock_code, namespace + "/.lock", TMP + "/locked"])
limit = clock_ms() + 5000
while !File.exist?(TMP + "/locked") && clock_ms() < limit
  sleep(~0.01)
msg = nil
begin
  Transcode.run(TMP + "/src.mov", TMP + "/locked.mov", opts)
rescue e
  msg = e.to_s
p.kill
p.wait
check("concurrent checkpoint writers fail without touching the active cache", msg != nil && msg.include?("busy"))
File.write(namespace + "/00000001.sha256", "corrupt")
r = Transcode.run(TMP + "/src.mov", TMP + "/out.mov", opts)
check("corrupt checkpoint digest recomputes from the first invalid GOP", r[:resumed_frames] == 16)
changed = opts.dup
changed[:width] = 640
r = Transcode.run(TMP + "/src.mov", TMP + "/wide.mov", changed)
check("changed geometry cannot reuse stale checkpoints", r[:resumed_frames] == 0 && r[:width] == 640)
File.write(TMP + "/cancel", "stop")
changed[:cancel_file] = TMP + "/cancel"
changed[:height] = 360
msg = nil
begin
  Transcode.run(TMP + "/src.mov", TMP + "/out.mov", changed)
rescue e
  msg = e.to_s
check("cancellation leaves the previous complete output", msg != nil && msg.include?("cancelled") && MediaVerify.facts(TMP + "/out.mov", true, false)[:frames] == 90)
# Same source pathname and clock, different encoded bytes: no stale reuse.
MediaVerify.sync_test(TMP + "/src.mov", width: 160, height: 90, rate: [30000, 1001], seconds: 3, codec: :h264, chapters: [["Opening", 0]], tc_start: "01:00:00;00")
r = Transcode.run(TMP + "/src.mov", TMP + "/source_changed.mov", opts)
check("changed source bytes invalidate the cache at the same pathname", r[:resumed_frames] == 0)
check("no encoder, segment or mux handles remain", VideoEncoder.stats[:encoders] == 0 && VideoEncoder.stats[:segments] == 0 && VideoEncoder.stats[:muxes] == 0)
OS.system("rm -rf " + TMP)
<< "ALL PASS media_resume_spec ([passed.load()] checks)"
