# fmt_media_test — headless demux + decode check for the containers and audio
# codecs added with the TS / HLS / AIFF / CAF / ALAC / AC-3 work. No sound is
# played: audio is decoded to memory (and optionally written as raw float32).
#
#   tungsten benchmarks/codec/fmt_media_test.w -- [--pcm out.f32] [--video N] file …
#
# Per file: container, tracks (codec, rate, channels), samples, keyframes,
# first/last pts; decoded audio frames and peak; --pcm writes the first audio
# track's samples interleaved little-endian float32; --video N decodes the
# first N video samples and reports the frames produced.

use core/codec/media
use core/codec/container/demux
use core/codec/container/demux_mp4
use core/codec/container/demux_webm
use core/codec/container/demux_ogg
use core/codec/container/demux_ts
use core/codec/container/demux_aiff
use core/codec/audio/pcm
use core/codec/audio/aac
use core/codec/audio/mp3
use core/codec/audio/flac
use core/codec/audio/opus
use core/codec/audio/vorbis
use core/codec/audio/alac
use core/codec/audio/ac3
use core/codec/video/h264

-> f32_le_bytes(s, n) (f32[] i64) u8[]
  out = u8[n * 4]
  i = 0 ## i64
  while i < n
    v = s[i] ## f64
    # encode binary32 (enough for test output)
    bits = 0 ## i64
    if v != ~0.0
      sg = 0 ## i64
      if v < ~0.0
        sg = 1
        v = ~0.0 - v
      e = 127 ## i64
      while v >= ~2.0
        v = v * ~0.5
        e += 1
      while v < ~1.0 && e > 0
        v = v * ~2.0
        e -= 1
      m = ((v - ~1.0) * ~8388608.0 + ~0.5).to_i
      if m >= 8388608
        m = 0
        e += 1
      bits = (sg << 31) | (e << 23) | m
    out[i * 4] = bits & 255
    out[i * 4 + 1] = (bits >> 8) & 255
    out[i * 4 + 2] = (bits >> 16) & 255
    out[i * 4 + 3] = (bits >> 24) & 255
    i += 1
  out

-> peak_of(s, n) (f32[] i64) f64
  p = ~0.0
  i = 0 ## i64
  while i < n
    v = s[i] ## f64
    v = ~0.0 - v if v < ~0.0
    p = v if v > p
    i += 1
  p

args = argv()
pcm_out = nil
nvideo = 0
chunk = 65536
files = []
i = 0
while i < args.size
  a = args[i]
  if a == "--pcm"
    i += 1
    pcm_out = args[i]
  elsif a == "--video"
    i += 1
    nvideo = args[i].to_i
  elsif a == "-c"
    i += 1
    chunk = args[i].to_i
  else
    files.push(a)
  i += 1

files.each ->(f)
  data = dm_bytes(File.read_bytes(f))
  d = demux_for(data)
  if d == nil
    << f + ": not recognised"
  else
    samples = {}
    off = 0
    while off < data.size
      n = chunk
      n = data.size - off if off + n > data.size
      d.append(dm_slice(data, off, n))
      off += n
      d.parse
      if d.want_offset != nil
        wo = d.want_offset
        d.restart(wo) if wo != off
        off = wo
      d.take.each ->(ts)
        samples[ts[0]] = [] if !samples.has_key?(ts[0])
        samples[ts[0]].push(ts[1])
    d.finish
    d.take.each ->(ts)
      samples[ts[0]] = [] if !samples.has_key?(ts[0])
      samples[ts[0]].push(ts[1])
    << f + ": " + d.kind.to_s + (d.error != nil ? " ERROR " + d.error : "") + " duration=" + d.duration.to_s
    pcm_done = false
    d.tracks.each ->(t)
      c = t.cfg
      ss = samples[t.id]
      ss = [] if ss == nil
      keys = ss.select(->(s) s.key).size
      first = ss.size > 0 ? ss[0].pts : nil
      last = ss.size > 0 ? ss[ss.size - 1].pts : nil
      << "  track " + t.id.to_s + " " + t.kind.to_s + " " + c.codec + " (" + c.codec_string.to_s + ") rate=" + c.sample_rate.to_s + " ch=" + c.channels.to_s + " samples=" + ss.size.to_s + " keys=" + keys.to_s + " pts " + first.to_s + " .. " + last.to_s
      if t.kind == :audio && acodec_supported?(c.codec)
        t0 = clock()
        dec = acodec_new(c)
        frames = 0
        peak = ~0.0
        ch = 0
        rate = 0
        chunks = []
        err = nil
        ss.each ->(s)
          if err == nil
            begin
              blk = dec.decode(s)
              if blk != nil
                frames += blk.frames
                ch = blk.channels
                rate = blk.sample_rate
                p = peak_of(blk.samples, blk.frames * blk.channels)
                peak = p if p > peak
                chunks.push(blk) if pcm_out != nil && !pcm_done
            rescue e
              err = e.to_s
        el = ((clock() - t0) * ~1000.0).round
        << "    decoded " + frames.to_s + " frames " + ch.to_s + "ch @" + rate.to_s + " peak=" + ((peak * ~1000.0).round / ~1000.0).to_s + " in " + el.to_s + " ms" + (err != nil ? " ERROR " + err : "")
        if pcm_out != nil && !pcm_done
          sb = []
          tot = 0
          chunks.each ->(b) tot += b.frames * b.channels
          out = u8[tot * 4]
          o = 0
          chunks.each ->(b)
            bb = f32_le_bytes(b.samples, b.frames * b.channels)
            k = 0
            while k < bb.size
              out[o + k] = bb[k]
              k += 1
            o += bb.size
          File.write(pcm_out, out)
          pcm_done = true
      elsif t.kind == :video && nvideo > 0 && vcodec_supported?(c.codec)
        dec = vcodec_new(c)
        nf = 0
        w = 0
        h = 0
        k = 0
        err = nil
        while k < nvideo && k < ss.size && err == nil
          begin
            fr = dec.decode(ss[k])
            fr.each ->(x)
              nf += 1
              w = x.width
              h = x.height
          rescue e
            err = e.to_s
          k += 1
        << "    video decoded " + nf.to_s + " frames " + w.to_s + "x" + h.to_s + (err != nil ? " ERROR " + err : "")
