# demux_test — feed media files to Blade's demuxers in chunks and summarise.
#
#   bin/tungsten benchmarks/codec/demux_test.w -- [-c chunk] [-v] file …
#
# Per track: codec, codec string, config size, sample count, keyframes, bytes,
# first/last pts and the summed durations. Compare with ffprobe -count_packets.

use core/codec/media
use core/codec/container/demux
use core/codec/container/demux_mp4
use core/codec/container/demux_webm
use core/codec/container/demux_ogg

args = ARGV
chunk = 65536
verbose = false
files = []
i = 0
while i < args.size
  a = args[i]
  if a == "-c"
    chunk = args[i + 1].to_i
    i += 1
  elsif a == "-v"
    verbose = true
  else
    files.push(a)
  i += 1

files.each ->(f)
  data = dm_bytes(File.read_bytes(f)) rescue data = dm_bytes(File.read(f))
  t0 = clock_ms()
  d = demux_for(data)
  if d == nil
    << f + ": not recognised"
  else
    stats = {}
    off = 0
    rounds = 0
    while off < data.size && rounds < 100000
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
        tid = ts[0]
        s = ts[1]
        st = stats[tid]
        if st == nil
          st = [0, 0, 0, s.pts, s.pts, ~0.0]
          stats[tid] = st
        st[0] += 1
        st[1] += 1 if s.key
        st[2] += s.data.size
        st[3] = s.pts if s.pts < st[3]
        st[4] = s.pts if s.pts > st[4]
        st[5] = st[5] + s.duration
        << "  " + tid.to_s + " pts=" + s.pts.to_s + " dts=" + s.dts.to_s + " size=" + s.data.size.to_s + (s.key ? " K" : "") if verbose
      rounds += 1
    d.finish
    d.take.each ->(ts)
      st = stats[ts[0]]
      if st == nil
        st = [0, 0, 0, ts[1].pts, ts[1].pts, ~0.0]
        stats[ts[0]] = st
      st[0] += 1
      st[1] += 1 if ts[1].key
      st[2] += ts[1].data.size
      st[4] = ts[1].pts if ts[1].pts > st[4]
      st[5] = st[5] + ts[1].duration
    << f + ": " + d.kind.to_s + " duration=" + d.duration.to_s + " ms=" + (clock_ms() - t0).to_s + (d.error == nil ? "" : " ERROR " + d.error)
    d.tracks.each ->(t)
      c = t.cfg
      st = stats[t.id]
      ex = c.extra
      exs = ex == nil ? "-" : (ex.is_a?(ByteArray) ? ex.size.to_s : nil)
      exs = (ex.is_a?(Array) ? "\[" + ex.map(->(x) x.size.to_s).join(",") + "]" : ex.to_s) if exs == nil
      line = "  track " + t.id.to_s + " " + t.kind.to_s + " " + c.codec + " (" + c.codec_string.to_s + ") extra=" + exs
      line = line + " " + c.width.to_s + "x" + c.height.to_s if t.kind == :video
      line = line + " " + c.sample_rate.to_s + "Hz " + c.channels.to_s + "ch" if t.kind == :audio
      if st != nil
        line = line + " samples=" + st[0].to_s + " keys=" + st[1].to_s + " bytes=" + st[2].to_s + " pts=" + st[3].to_s + ".." + st[4].to_s + " sumdur=" + st[5].to_s
      << line
