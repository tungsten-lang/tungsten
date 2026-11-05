# spec: compiled -- CoreMIDI and AVAudioEngine through the media bridge, linked only into compiled programs
# spec: interpreter-rejects -- the media bridge is compiled-only
# core/midi and core/live: a virtual MIDI destination is made, found among the destinations, sent a note on and off by an
# output to it, and the input reads both back in order with their bytes; a virtual source appears among the sources. The live
# sampler gets a zone (a 440 Hz sine, 1 s, its root A4), plays a note at volume 0 (nothing is heard): a voice sounds and the
# engine renders frames; the release ends the voice; a key outside every zone starts nothing; a sample file streams past its
# head with no underrun when scheduled ahead, its latency is measured, it bends and releases; a closed sampler raises.
#
# Run:
#   bin/tungsten spec/core/midi_live_spec.w

use core/midi
use core/live

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

nm = "Tungsten Spec In " + clock_ms().to_s
inp = midi_in(-1, nm)
ds = midi_destinations()
k = ds.index(nm)
check("a virtual destination is listed (" + ds.size.to_s + " destinations)", k != nil)
out = midi_out(k)
check("note on sent", midi_send(out, 144, 60, 100))
check("note off sent", midi_send(out, 128, 60, 0))
es = []
t0 = clock_ms()
while es.size < 2 && clock_ms() - t0 < 2000
  es = es + midi_read(inp)
  sleep(0.01)
check("both messages arrive in order", es.size == 2 && es[0][0] == 144 && es[0][1] == 60 && es[0][2] == 100 && es[1][0] == 128)
check("with arrival times", es.size == 2 && es[1][3] >= es[0][3] && es[0][3] > 0.0)
check("nothing more", midi_read(inp).size == 0)
check("a program change (two bytes)", midi_send(out, 192, 5))
wait_ms(100)
pc = midi_read(inp)
check("a two-byte message arrives", pc.size == 1 && pc[0][0] == 192 && pc[0][1] == 5)
sn = "Tungsten Spec Out " + clock_ms().to_s
vo = midi_out(-1, sn)
check("a virtual source is listed", midi_sources().include?(sn))
check("closing", midi_close(out) && midi_close(inp) && midi_close(vo))

s = live_new(48000)
rate = live_info(s)[:rate]
n = 48000
l = f64[n]
r = f64[n]
i = 0
while i < n
  l[i] = Math.sin(~6.283185307179586 * ~440.0 * (i ## f64) / ~48000.0) * ~0.5
  r[i] = l[i]
  i += 1
check("a zone", live_zone(s, [48, 72, 1, 127, 69, n, 48000, 0, 0, 1.0], l, r) == 0)
live_volume(s, 0)
check("a note starts", live_note(s, 69, 100))
wait_ms(200)
inf = live_info(s)
check("a voice sounds and frames are rendered (" + inf[:rendered].to_s + " at " + rate.to_s + " Hz)", inf[:voices] == 1 && inf[:rendered] > 0)
live_note(s, 69, 0)
wait_ms(500)
check("the release ends it", live_info(s)[:voices] == 0)
check("a key outside every zone starts nothing", !live_note(s, 100, 100) && live_info(s)[:voices] == 0)
# version 2: a sample file streamed (its head in memory), scheduled at a host time, released, bent; the latency measured
wav = "/tmp/tungsten-live-spec-" + clock_ms().to_s + ".wav"
MediaVerify.write_click_wav(wav, 96000 * 3, 48000, [100, 60000, 120000])
zf = live_zone_file(s, wav, 4096)
check("a file zone: its head in memory, the rest streamed (" + zf[2].to_s + " frames, first sound at " + zf[3].to_s + ")", zf[1] == 48000.0 && zf[2] == 288000 && zf[3] >= 0)
t0 = midi_now()
tag = live_play(s, [zf[0], 60, 1.0, 0.5, 0, 0.05], t0 + 0.05, t0)
check("a scheduled note has a tag", tag > 0)
wait_ms(400)
inf = live_info(s)
check("it sounds past its head (streamed: " + inf[:underruns].to_s + " underruns)", inf[:voices] >= 1 && inf[:underruns] == 0)
check("its latency is measured (" + (inf[:latency] * 1000.0).round.to_s + " ms from its cause, scheduled 50 ms ahead)", inf[:latency_n] >= 1 && inf[:latency] > 0.03 && inf[:latency] < 0.2)
live_bend(s, 200, 0)
live_release(s, tag, 0, 0.02)
wait_ms(500)
check("released", live_info(s)[:voices] == 0)
check("memory: heads " + live_info(s)[:head_bytes].to_s + " bytes", live_info(s)[:head_bytes] > 0)
# the render callback's load and the voices it ran (2026-11-04 night): measured, a fraction of each buffer, 256 voices
inf = live_info(s)
check("the callback's load is measured (mean " + ((inf[:cb_s] / inf[:audio_s]) * 100.0).round.to_s + " %, worst buffer " + (inf[:load_max] * 100.0).round.to_s + " %)", inf[:audio_s] > 0.5 && inf[:cb_s] > 0.0 && inf[:cb_s] < inf[:audio_s] && inf[:load_max] > 0.0)
check("the most voices at once (" + inf[:voices_max].to_s + " of " + inf[:voice_cap].to_s + ")", inf[:voices_max] >= 1 && inf[:voice_cap] == 256)
# many voices at once: 200 notes started together all sound, the oldest stolen only past 256
t1 = midi_now()
k = 0
while k < 200
  live_play(s, [zf[0], 60, 1.0, 0.002, 0, 0.05], t1 + 0.05, t1)
  k += 1
wait_ms(250)
check("200 notes at once sound together (" + live_info(s)[:voices].to_s + " voices)", live_info(s)[:voices] == 200)
live_release(s, 0, 0, 0.01)
wait_ms(300)
check("all released", live_info(s)[:voices] == 0)
# flush: notes scheduled ahead never start, what sounds stops
t2 = midi_now()
live_play(s, [zf[0], 60, 1.0, 0.01, 0, 0.05], t2, t2)
live_play(s, [zf[0], 64, 1.0, 0.01, 0, 0.05], t2 + 0.3, t2)
wait_ms(100)
check("flush: one sounds, one is scheduled", live_info(s)[:voices] == 1)
live_flush(s, 0.01)
wait_ms(400)
check("flush: nothing sounds and the scheduled note never started", live_info(s)[:voices] == 0)
File.delete(wav)
check("close", live_close(s))
bad = 0
begin
  live_info(s)
rescue error
  bad = 1
check("a closed sampler raises", bad == 1)
<< "midi and live: " + passed.get.to_s + " passed"
