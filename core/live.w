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

-> live_info(sampler)
  a = ccall("w_media_live_info", sampler)
  {voices: a[0], zones: a[1], rate: a[2], rendered: a[3]}

-> live_close(sampler)
  ccall("w_media_live_close", sampler)
