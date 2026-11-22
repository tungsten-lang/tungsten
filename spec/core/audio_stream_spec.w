# spec: compiled -- the stream is the media bridge's AVAudioEngine source node, linked only into compiled programs
# spec: interpreter-rejects -- audio streams are compiled-only
# core/audio_stream: a 48 kHz stereo stream at volume 0 (nothing is heard)
# takes 1 s of float PCM; the clock (the frame being heard) advances in real
# time while it plays, holds while paused, never passes the frames written,
# restarts at 0 after a flush; a full ring accepts only what fits; ByteArrays
# of float32 are accepted too; bad arguments and closed handles raise.
#
# Run:
#   bin/tungsten spec/core/audio_stream_spec.w

use core/audio_stream

passed = Atomic.new(0)

-> check(name, condition)
  raise "FAIL " + name if !condition
  passed.increment()
  << "PASS " + name

-> wait_ms(ms)
  t0 = clock_ms()
  while clock_ms() - t0 < ms
    sleep(0.01)
  0

s = audio_stream_open(48000, 2)
audio_stream_volume(s, 0)
info = audio_stream_info(s)
check("rate and channels", info[:rate] == 48000.0 && info[:channels] == 2)
check("nothing queued", info[:queued] == 0)
pcm = f32[96000]
check("1 s accepted", audio_stream_write(s, pcm, 0, 48000) == 48000)
check("queued", audio_stream_info(s)[:queued] <= 48000)
wait_ms(400)
t1 = audio_stream_time(s)
check("the clock runs (" + t1.to_s + " s)", t1 > 0.2 && t1 < 0.6)
audio_stream_pause(s, true)
tp = audio_stream_time(s)
wait_ms(200)
check("the clock holds while paused", audio_stream_time(s) == tp)
audio_stream_pause(s, false)
wait_ms(900)
te = audio_stream_time(s)
check("the clock stops at the frames written (" + te.to_s + " s)", te > 0.95 && te <= 1.0)
check("an underrun leaves the clock where it is", audio_stream_time(s) == te)
audio_stream_flush(s)
check("flush restarts the clock", audio_stream_time(s) == 0.0)
big = f32[2 * 48000 * 5]
n = audio_stream_write(s, big, 0, -1)
check("a full ring takes only what fits (" + n.to_s + ")", n >= 4 * 48000 - 4096 && n <= 4 * 48000)
check("then nothing more", audio_stream_write(s, big, 0, -1) == 0)
audio_stream_flush(s)
check("ByteArray float32 accepted", audio_stream_write(s, ByteArray.new(800), 0, -1) == 100)
check("first/frames window", audio_stream_write(s, pcm, 47990, 100) == 10)
audio_stream_close(s)
check("second close is harmless", audio_stream_close(s) == nil)
bad = 0
begin
  audio_stream_time(s)
rescue error
  bad = 1
check("a closed handle raises", bad == 1)
bad = 0
begin
  audio_stream_open(48000, 0)
rescue error
  bad = 1
check("0 channels raises", bad == 1)
<< "audio_stream: " + passed.get.to_s + " passed"
