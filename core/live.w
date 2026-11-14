# core/live.w — a sampler that plays now (AVAudioEngine), for playing an instrument live.
#
#   s = live_new(48000)
#   live_zone(s, [lo, hi, vlo, vhi, root, frames, rate, loop_start, loop_end, gain], left, right)   # f64[] or f32[] PCM
#   live_note(s, 60, 100)        # start middle C at velocity 100 (the zone for that key and velocity)
#   live_note(s, 60, 0)          # release it (a short fade)
#   live_volume(s, 0.8)
#   live_info(s)                 # {voices:, zones:, rate:, rendered:}
#   live_close(s)
#
# Zones hold their PCM in the bridge (copied as 32-bit floats); voices are resampled to their key from the zone's root and
# sample rate, loop when the zone has a loop, and fade out over 0.25 s when released. The render thread is AVAudioEngine's;
# notes start and stop from the program's thread. macOS only (the media bridge, runtime/media/media_avf.m). `use core/live`.

-> live_new(rate = 48000)
  ccall("w_media_live_new", rate)

-> live_zone(sampler, keys, left, right)
  ccall("w_media_live_zone", sampler, keys, left, right)

-> live_note(sampler, key, velocity)
  ccall("w_media_live_note", sampler, key, velocity)

-> live_volume(sampler, v)
  ccall("w_media_live_volume", sampler, v)

# version 2: a sample file as a zone (its first head_frames decoded now, the rest streamed while it plays; a ".twpcm" PCM
# cache is memory-mapped) → [zone, rate, frames, first sound frame]
-> live_zone_file(sampler, path, head_frames = 16384)
  ccall("w_media_live_zone_file", sampler, path, head_frames)

# batch parallel loader for sample files → [[zone, rate, frames, first sound frame], ...]
-> live_zone_files(sampler, paths, head_frames = 16384)
  ccall("w_media_live_zone_files", sampler, paths, head_frames)

# the 64-tap sinc table to interpolate with (sampler.w sinc_get: 513 × 64 coefficients), else linear
-> live_sinc(sampler, table)
  ccall("w_media_live_sinc", sampler, table)

# a note scheduled: [zone, key, pitch ratio, gain, start frame, release time constant s] at host time `when` (midi_now's clock;
# 0 now), `origin` the host time of its cause (the latency is measured from it) → its tag
-> live_play(sampler, note, at = 0, origin = 0)
  ccall("w_media_live_play", sampler, note, at, origin)

# release a note by tag (0: all) at a host time (0: now), its release time constant s (0: its own)
-> live_release(sampler, tag, at = 0, rel = 0)
  ccall("w_media_live_release", sampler, tag, at, rel)

# a transport's stop: every scheduled note, release and bend dropped, what sounds released now (rel s; 0: each voice's own)
-> live_flush(sampler, rel = 0)
  ccall("w_media_live_flush", sampler, rel)

# pitch bend in cents for every voice from a host time (0: now)
-> live_bend(sampler, cents, at = 0)
  ccall("w_media_live_bend", sampler, cents, at)

# a vibrato on every voice: depth cents (0 none), rate Hz
-> live_vibrato(sampler, depth, rate = 5.5)
  ccall("w_media_live_vibrato", sampler, depth, rate)

# {voices:, zones:, rate:, rendered:, head_bytes:, mapped_bytes:, ring_bytes:, underruns:, latency_n:, latency:, latency_max:,
#  latency_last:, output_latency:, buffer_frames:, now:, cb_s:, audio_s: (cb_s / audio_s is the render callback's mean load),
#  load_max: (the worst buffer's), voices_max: (the most sounding at once), voice_cap: (256)}
-> live_info(sampler)
  a = ccall("w_media_live_info", sampler)
  {voices: a[0], zones: a[1], rate: a[2], rendered: a[3], head_bytes: a[4], mapped_bytes: a[5], ring_bytes: a[6], underruns: a[7], latency_n: a[8], latency: a[9], latency_max: a[10], latency_last: a[11], output_latency: a[12], buffer_frames: a[13], now: a[14], cb_s: a[15], audio_s: a[16], load_max: a[17], voices_max: a[18], voice_cap: a[19]}

-> live_close(sampler)
  ccall("w_media_live_close", sampler)
