# Media helpers for spec/core/codec/*_spec.w: demux a whole fixture, decode a
# track, summarise the output. Needs core/codec/media, the demuxers and
# core/codec/video/yuv loaded by the spec.

use support

# "WxH chroma/depth frames=N fnv=H rgba0=H" for a list of VideoFrames.
-> frames_summary(frames)
  h = FNV0
  frames.each ->(f)
    f.planes.each ->(pl)
      h = fnv_plane(pl, h)
  return "frames=0" if frames.size == 0
  f = frames[0]
  rgba = yuv_to_rgba(f)
  f.width.to_s + "x" + f.height.to_s + " " + f.chroma + "/" + f.bit_depth.to_s + " frames=" + frames.size.to_s + " fnv=" + h.to_s + " rgba0=" + fnv8(rgba, rgba.size, FNV0).to_s

# Feed a whole file to its demuxer; returns [demuxer, {track_id => [MediaSample]}].
-> demux_all(a)
  d = demux_for(a)
  return [nil, {}] if d == nil
  samples = {}
  d.append(a)
  d.parse
  guard = 0
  while d.want_offset != nil && guard < 16
    wo = d.want_offset
    d.restart(wo)
    d.append(dm_slice(a, wo, a.size - wo))
    d.parse
    guard += 1
  d.finish
  d.take.each ->(ts)
    samples[ts[0]] = [] if samples[ts[0]] == nil
    samples[ts[0]].push(ts[1])
  [d, samples]

-> decode_video(cfg, samples)
  dec = Codec.video(cfg)
  frames = []
  samples.each ->(s)
    dec.decode(s).each ->(f)
      frames.push(f)
  dec.flush.each ->(f)
    frames.push(f)
  frames

# "frames=N fnv=H" over every AudioBlock the decoder returns.
-> decode_audio(cfg, samples)
  dec = Codec.audio(cfg)
  h = FNV0
  n = 0
  blocks = []
  samples.each ->(s)
    b = dec.decode(s)
    blocks.push(b) if b != nil
  b = dec.flush
  blocks.push(b) if b != nil
  blocks.each ->(b)
    h = fnvf(b.samples, b.frames * b.channels, h)
    n += b.frames
  "frames=" + n.to_s + " fnv=" + h.to_s
