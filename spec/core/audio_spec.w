# spec: compiled -- the player is the media bridge's AVAudioPlayer, linked only into compiled programs
# spec: interpreter-rejects -- audio is compiled-only
# core/audio: a WAV is written (2 s, 48 kHz stereo 24-bit, two clicks),
# opened, its facts read back, played at volume 0 (nothing is heard) from
# 0.5 s: the player's clock advances while it plays and holds while paused;
# play resumes, stop rewinds, a bad path raises, a closed handle raises and a
# second close is harmless.
#
# Run:
#   bin/tungsten spec/core/audio_spec.w

use core/audio

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

path = "/tmp/tungsten-audio-spec-" + clock_ms().to_s + ".wav"
# 2 s of 48 kHz stereo 24-bit (MediaVerify's click track: silent but two clicks)
MediaVerify.write_click_wav(path, 96000, 48000, [24000, 72000])

p = audio_open(path)
info = audio_info(p)
check("duration read back", (info[:duration] - 2.0).abs < 0.01)
check("rate and channels", info[:rate] == 48000.0 && info[:channels] == 2)
check("not playing before play", !info[:playing])
audio_volume(p, 0)
check("play from 0.5 s", audio_play(p, 0.5))
wait_ms(300)
t1 = audio_time(p)
check("the clock runs while playing (" + t1.to_s + " s)", t1 > 0.6 && t1 < 1.2)
check("playing", audio_info(p)[:playing])
audio_pause(p)
ta = audio_time(p)
wait_ms(200)
tb = audio_time(p)
check("the clock holds while paused", (tb - ta).abs < 0.02 && !audio_info(p)[:playing])
audio_play(p, -1)
wait_ms(150)
check("resume carries on from the pause", audio_time(p) > tb + 0.05)
audio_stop(p)
check("stop rewinds", audio_time(p) < 0.01 && !audio_info(p)[:playing])
check("close", audio_close(p))
check("second close is harmless", !audio_close(p))
bad = 0
begin
  audio_time(p)
rescue error
  bad = 1
check("a closed handle raises", bad == 1)
bad = 0
begin
  audio_open("/tmp/no-such-file-" + clock_ms().to_s + ".wav")
rescue error
  bad = 1
check("a missing file raises", bad == 1)
File.delete(path)
<< "audio: " + passed.get.to_s + " passed"
