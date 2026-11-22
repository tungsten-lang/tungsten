# vtest — conformance / speed harness for Blade's video decoders.
#
#   bin/tungsten benchmarks/codec/vtest.w -- [-r ref.yuv] [-n maxframes] [-q] file
#
# file: .264/.h264/.jsv/.26l/.avc (Annex B H.264), .ivf (VP8/VP9), .ogv/.ogg
# (Theora). Each output frame is compared with the next frame of the raw
# reference (planar 8-bit, cropped size — e.g. ffmpeg -f rawvideo); prints the
# first mismatch per frame, the totals and the decode speed. ffmpeg is only
# used offline to make the references.

use core/codec/media
use core/codec/video/h264
use core/codec/video/vp9
use core/codec/video/vp8
use core/codec/video/theora

-> vt_u8(s)
  ccall("w_string_bytes_view", s) ## u8[]

# Split an Annex B stream into access units (7.4.1.2.3).
-> vt_annexb_aus(d)
  spans = h264_annexb_spans(d, d.size)
  aus = []
  cur_s = -1
  cur_e = -1
  have_slice = false
  i = 0
  while i < spans.size
    s = spans[i]
    e = spans[i + 1]
    t = d[s] & 31
    boundary = false
    if have_slice
      boundary = true if t == 9 || t == 7 || t == 8 || t == 6 || (t >= 14 && t <= 18)
      boundary = true if (t == 1 || t == 5) && e > s + 1 && (d[s + 1] & 0x80) != 0
    if boundary
      aus.push([cur_s, cur_e])
      cur_s = -1
      have_slice = false
    # include the start code so the decoder sees Annex B
    st = s - 3
    st -= 1 if st > 0 && d[st - 1] == 0
    cur_s = st if cur_s < 0
    cur_e = e
    have_slice = true if t == 1 || t == 5
    i += 2
  aus.push([cur_s, cur_e]) if cur_s >= 0
  aus

# Packets of the first Theora stream in an Ogg file.
-> vt_ogg_theora(d)
  pkts = []
  serial = -1
  cur = []
  p = 0
  while p + 27 <= d.size
    break if d[p] != 0x4f || d[p + 1] != 0x67
    sn = d[p + 14] | (d[p + 15] << 8) | (d[p + 16] << 16) | (d[p + 17] << 24)
    ns = d[p + 26]
    q = p + 27 + ns
    k = 0
    while k < ns
      l = d[p + 27 + k]
      if serial < 0 && (d[p + 5] & 2) != 0 && l > 7 && d[q] == 0x80 && d[q + 1] == 0x74
        serial = sn
      if sn == serial
        j = 0
        while j < l
          cur.push(d[q + j])
          j += 1
        if l < 255
          b = u8[cur.size]
          j = 0
          while j < cur.size
            b[j] = cur[j]
            j += 1
          pkts.push(b)
          cur = []
      q += l
      k += 1
    p = q
  pkts

-> vt_cmp_plane(a, astride, b, boff, w, h) (u8[] i64 u8[] i64 i64 i64) i64
  y = 0 ## i64
  while y < h
    x = 0 ## i64
    while x < w
      if a[y * astride + x] != b[boff + y * w + x]
        return y * 65536 + x
      x += 1
    y += 1
  -1

ref = nil
md5f = nil
maxf = 1000000
quiet = false
dump = false
file = nil
args = ARGV
i = 0
while i < args.size
  a = args[i]
  if a == "-r"
    ref = args[i + 1]
    i += 2
  elsif a == "-m"
    md5f = args[i + 1]
    i += 2
  elsif a == "-n"
    maxf = args[i + 1].to_i
    i += 2
  elsif a == "-q"
    quiet = true
    i += 1
  elsif a == "-d"
    dump = true
    i += 1
  else
    file = a
    i += 1

data = vt_u8(File.read(file))
refd = nil
refd = vt_u8(File.read(ref)) if ref != nil
md5s = []
if md5f != nil
  File.read(md5f).split("\n").each ->(ln)
    md5s.push(ln.slice(0, 32)) if ln.size >= 32

lower = file.downcase
dec = nil
samples = []
if lower.ends_with?(".ivf")
  fourcc = data.slice(8, 4).to_a.map(->(c) c.chr).join
  codec = fourcc == "VP90" ? "vp09" : "vp08"
  dec = vcodec_new(CodecConfig.new(codec))
  p = 32
  while p + 12 <= data.size
    sz = data[p] | (data[p + 1] << 8) | (data[p + 2] << 16) | (data[p + 3] << 24)
    p += 12
    break if p + sz > data.size
    samples.push(data.slice(p, sz))
    p += sz
elsif lower.ends_with?(".ogv") || lower.ends_with?(".ogg")
  pk = vt_ogg_theora(data)
  dec = vcodec_new(CodecConfig.new("theo", [pk[0], pk[1], pk[2]]))
  k = 3
  while k < pk.size
    samples.push(pk[k])
    k += 1
else
  dec = vcodec_new(CodecConfig.new("h264"))
  dec.au_complete = false
  vt_annexb_aus(data).each ->(au)
    samples.push(data.slice(au[0], au[1] - au[0]))

nframes = 0
bad = 0
roff = 0
t0 = clock()
check = ->(f)
  if nframes < maxf && md5f != nil
    w = f.width
    h = f.height
    cw = (w + 1) / 2
    ch = (h + 1) / 2
    buf = u8[w * h + 2 * cw * ch]
    o = 0
    pl = 0
    while pl < 3
      pw = pl == 0 ? w : cw
      ph = pl == 0 ? h : ch
      src = f.planes[pl]
      st = f.strides[pl]
      yy = 0
      while yy < ph
        xx = 0
        while xx < pw
          buf[o] = src[yy * st + xx]
          o += 1
          xx += 1
        yy += 1
      pl += 1
    dg = Digest.md5(buf)
    if nframes >= md5s.size || dg != md5s[nframes]
      bad += 1
      << "frame [nframes]: md5 mismatch" if !quiet
  if nframes < maxf
    if refd != nil
      w = f.width
      h = f.height
      cw = (w + 1) / 2
      ch = f.chroma == "422" ? h : (h + 1) / 2
      fsize = w * h + 2 * cw * ch
      if roff + fsize <= refd.size
        r0 = vt_cmp_plane(f.planes[0], f.strides[0], refd, roff, w, h)
        r1 = vt_cmp_plane(f.planes[1], f.strides[1], refd, roff + w * h, cw, ch)
        r2 = vt_cmp_plane(f.planes[2], f.strides[2], refd, roff + w * h + cw * ch, cw, ch)
        if r0 >= 0 || r1 >= 0 || r2 >= 0
          bad += 1
          if !quiet
            pl = r0 >= 0 ? 0 : (r1 >= 0 ? 1 : 2)
            rr = r0 >= 0 ? r0 : (r1 >= 0 ? r1 : r2)
            << "frame [nframes]: mismatch plane [pl] at x=[rr % 65536] y=[rr / 65536]"
            if dump && nframes == 0
              pw = pl == 0 ? w : cw
              pofs = pl == 0 ? 0 : (pl == 1 ? w * h : w * h + cw * ch)
              mx0 = ((rr % 65536) / 16) * 16
              my0 = ((rr / 65536) / 16) * 16
              yy = 0
              while yy < 16
                l1 = ""
                l2 = ""
                xx = 0
                while xx < 16
                  l1 = l1 + " " + f.planes[pl][(my0 + yy) * f.strides[pl] + mx0 + xx].to_s
                  l2 = l2 + " " + refd[roff + pofs + (my0 + yy) * pw + mx0 + xx].to_s
                  xx += 1
                << "mine[l1]   ref[l2]"
                yy += 1
      else
        << "frame [nframes]: beyond reference" if !quiet
        bad += 1
      roff += fsize
  nframes += 1
k = 0
while k < samples.size
  s = MediaSample.new(samples[k], k * ~0.04, k * ~0.04, ~0.04, false)
  if env("VT_NORESCUE") != nil
    fr = dec.decode(s)
    fr.each ->(f)
      check.call(f)
  else
    begin
      fr = dec.decode(s)
      fr.each ->(f)
        check.call(f)
    rescue e
      << "sample [k]: error [e]"
  k += 1
dec.flush.each ->(f)
  check.call(f)
dt = clock() - t0
extra = ""
extra = " (reference has [(refd.size - roff)] bytes more)" if refd != nil && roff < refd.size
fps = nframes / (dt > ~0.0 ? dt : ~1.0)
<< "[file]: [nframes] frames, [bad] mismatched, [dt.round(3)]s, [fps.round(1)] fps[extra]"
