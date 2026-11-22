# yuv_test — time and check core/codec/video/yuv on a raw I420 frame.
#   bin/tungsten -o /tmp/yt --release benchmarks/codec/yuv_test.w && /tmp/yt -- frame.yuv W H ref.rgba [threads]
use core/codec/media
use core/codec/cicp
use core/codec/video/yuv

a = ARGV
yuv = File.read_bytes(a[0])
w = a[1].to_i
h = a[2].to_i
ref = File.read_bytes(a[3])
YUV_THREADS[0] = a[4].to_i if a.size > 4
cw = (w + 1) / 2
chh = (h + 1) / 2
yp = ByteArray.new(w * h)
up = ByteArray.new(cw * chh)
vp = ByteArray.new(cw * chh)
dm = ->(dst, off, n) dst
i = 0
while i < w * h
  yp[i] = yuv[i]
  i += 1
i = 0
while i < cw * chh
  up[i] = yuv[w * h + i]
  vp[i] = yuv[w * h + cw * chh + i]
  i += 1
f = VideoFrame.new(w, h, [yp, up, vp], [w, cw, cw], "420", 8, ~0.0)
out = ByteArray.new(w * h * 4)
t0 = clock_ms()
k = 0
while k < 20
  yuv_to_rgba_into(f, out)
  k += 1
ms = (clock_ms() - t0).to_f / ~20.0
mx = 0
tot = 0
i = 0
while i < w * h * 4
  d = out[i] - ref[i]
  d = -d if d < 0
  mx = d if d > mx
  tot += d
  i += 1
<< "ms/frame=" + ms.to_s + " maxerr=" + mx.to_s + " meanerr=" + (tot.to_f / (w * h * 4).to_f).to_s
