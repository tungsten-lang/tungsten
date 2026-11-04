# apps/studio/lib/flac.w: FLAC decoding and `studio flaccheck`.
# spec: compiled -- the decoder's bit reading, Rice, predictor, CRC and output loops are embedded-IR kernels
# The FLAC streams here are built by a small encoder in this spec (bit writer, CRC-8/CRC-16, Rice coder, predictors written from
# RFC 9639 independently of the decoder), so every subframe type (CONSTANT, VERBATIM, FIXED orders 0..4, LPC orders 1..32 with
# precisions and shifts), wasted bits, every channel assignment (1..8 independent channels, left/side, side/right, mid/side), both
# Rice methods, partition orders 0..8, escaped partitions (width 0 too), every block size, sample rate and sample size code, fixed
# and variable blocking with 1..7-byte coded numbers, an ID3v2 tag and extra metadata blocks are exercised without any sample
# data; then the planar reader, the MD5, `flaccheck` against WAVs, and every malformed-stream error.

use ../../apps/studio/lib/flac

-> fail_check(name, detail)
  << "FAIL: " + name + " " + detail
  exit(1)

-> check(name, got, want)
  if got != want
    fail_check(name, "got=" + got.to_s + " want=" + want.to_s)

# ---- a minimal encoder (test only) ----------------------------------------------------------------------------------------
-> bw_new
  {b: [], acc: 0, n: 0}

# v (unsigned, < 2^n) in n bits, most significant first
-> put(w, v, n)
  k = n - 1
  while k >= 0
    w[:acc] = w[:acc] * 2 + ((v >> k) & 1)
    w[:n] = w[:n] + 1
    if w[:n] == 8
      w[:b].push(w[:acc])
      w[:acc] = 0
      w[:n] = 0
    k -= 1
  w

# a signed value in n bits, two's complement
-> put_s(w, v, n)
  v = v + (1 << n) if v < 0
  put(w, v, n)

-> unary(w, q)
  i = 0
  while i < q
    put(w, 0, 1)
    i += 1
  put(w, 1, 1)

-> align(w)
  while w[:n] != 0
    put(w, 0, 1)
  w

# floor(v / 2^s)
-> fshr(v, s)
  return v >> s if v >= 0
  0 - ((0 - v - 1) >> s) - 1

-> crc8(bs, from, to)
  c = 0
  i = from
  while i < to
    c = c ^ bs[i]
    k = 0
    while k < 8
      if (c & 128) != 0
        c = ((c * 2) ^ 7) & 255
      else
        c = (c * 2) & 255
      k += 1
    i += 1
  c

-> crc16(bs, from, to)
  c = 0
  i = from
  while i < to
    c = c ^ (bs[i] * 256)
    k = 0
    while k < 8
      if (c & 32768) != 0
        c = ((c * 2) ^ 32773) & 65535
      else
        c = (c * 2) & 65535
      k += 1
    i += 1
  c

-> rice(w, v, k)
  u = v * 2
  u = 0 - v * 2 - 1 if v < 0
  unary(w, u >> k)
  put(w, u & ((1 << k) - 1), k)

# the width a signed escape needs for all of xs (0 when all are zero)
-> width_for(xs)
  n = 0
  i = 0
  while i < xs.size
    v = xs[i]
    while v < 0 - (1 << (n - 1)) || v >= (1 << (n - 1)) || (n == 0 && v != 0)
      n += 1
    i += 1
  n

-> auto_k(xs, cap)
  s = 0
  i = 0
  while i < xs.size
    u = xs[i] * 2
    u = 0 - xs[i] * 2 - 1 if xs[i] < 0
    s += u
    i += 1
  m = 0
  m = s / xs.size if xs.size > 0
  k = 0
  while k < cap && (1 << (k + 1)) <= m
    k += 1
  k

# residual r (bs − order values) with sp's method (0/1), partition order and parameters (ks cycled; −1 escape, −2 automatic)
-> enc_residual(w, r, bs, order, sp)
  m = sp[:method]
  po = sp[:porder]
  ks = sp[:ks]
  put(w, sp[:rawmethod] == nil ? m : sp[:rawmethod], 2)
  put(w, po, 4)
  np = 1 << po
  psz = bs >> po
  at = 0
  p = 0
  while p < np
    cnt = psz
    cnt = psz - order if p == 0
    part = r.slice(at, cnt)
    k = ks[p % ks.size]
    k = auto_k(part, m == 0 ? 14 : 30) if k == -2
    if k == -1
      put(w, m == 0 ? 15 : 31, 4 + m)
      wd = width_for(part)
      put(w, wd, 5)
      i = 0
      while i < cnt
        put_s(w, part[i], wd) if wd > 0
        i += 1
    else
      put(w, k, 4 + m)
      i = 0
      while i < cnt
        rice(w, part[i], k)
        i += 1
    at += cnt
    p += 1
  w

FIXED_C = [[], [1], [2, -1], [3, -3, 1], [4, -6, 4, -1]]

# one subframe: s (bs samples of bps bits), sp {t: "constant"|"verbatim"|"fixed"|"lpc", order, coefs, prec, shift, wasted,
# method, porder, ks; rawtype / rawprec / rawshift / rawmethod write invalid fields}
-> enc_sub(w, s, bps, sp)
  bs = s.size
  wb = 0
  wb = sp[:wasted] if sp[:wasted] != nil
  x = []
  i = 0
  while i < bs
    x.push(fshr(s[i], wb))
    i += 1
  eb = bps - wb
  t = sp[:t]
  order = 0
  order = sp[:order] if sp[:order] != nil
  code = 0
  code = 1 if t == "verbatim"
  code = 8 + order if t == "fixed"
  code = 32 + order - 1 if t == "lpc"
  code = sp[:rawtype] if sp[:rawtype] != nil
  put(w, 0, 1)
  put(w, code, 6)
  if wb > 0
    put(w, 1, 1)
    i = 0
    while i < wb - 1
      put(w, 0, 1)
      i += 1
    put(w, 1, 1)
  else
    put(w, 0, 1)
  if t == "constant"
    put_s(w, x[0], eb)
    return w
  if t == "verbatim"
    i = 0
    while i < bs
      put_s(w, x[i], eb)
      i += 1
    return w
  i = 0
  while i < order
    put_s(w, x[i], eb)
    i += 1
  cs = []
  sh = 0
  if t == "fixed"
    cs = FIXED_C[order]
  else
    cs = sp[:coefs]
    sh = sp[:shift]
    put(w, sp[:rawprec] == nil ? sp[:prec] - 1 : sp[:rawprec], 4)
    put_s(w, sp[:rawshift] == nil ? sh : sp[:rawshift], 5)
    j = 0
    while j < order
      put_s(w, cs[j], sp[:prec])
      j += 1
  r = []
  i = order
  while i < bs
    acc = 0
    j = 0
    while j < order
      acc += cs[j] * x[i - 1 - j]
      j += 1
    r.push(x[i] - fshr(acc, sh))
    i += 1
  enc_residual(w, r, bs, order, sp)

# the UTF-8-like coded number (up to 36 bits)
-> put_num(w, v)
  if v < 128
    put(w, v, 8)
    return w
  n = 2
  while n < 7 && v >= (1 << (5 * n + 1))
    n += 1
  if n == 7
    put(w, 254, 8)
  else
    put(w, ((255 << (8 - n)) & 255) | (v >> (6 * (n - 1))), 8)
  j = n - 2
  while j >= 0
    put(w, 128 | ((v >> (6 * j)) & 63), 8)
    j -= 1
  w

# one frame: f {strat, bsc, src, cha, ssc, num, bits (the frame's), rate (for the rate codes 12..14), chans (per channel, bs
# samples), subs (a subframe spec per coded channel); bad8 / bad16 corrupt the CRCs}; appended to out
-> enc_frame(out, f)
  w = bw_new()
  ch = f[:chans]
  bs = ch[0].size
  put(w, 16382, 14)
  put(w, 0, 1)
  put(w, f[:strat], 1)
  put(w, f[:bsc], 4)
  put(w, f[:src], 4)
  put(w, f[:cha], 4)
  put(w, f[:ssc], 3)
  put(w, 0, 1)
  put_num(w, f[:num])
  put(w, bs - 1, 8) if f[:bsc] == 6
  put(w, bs - 1, 16) if f[:bsc] == 7
  put(w, f[:rate] / 1000, 8) if f[:src] == 12
  put(w, f[:rate], 16) if f[:src] == 13
  put(w, f[:rate] / 10, 16) if f[:src] == 14
  c8 = crc8(w[:b], 0, w[:b].size)
  c8 = c8 ^ 1 if f[:bad8] != nil
  put(w, c8, 8)
  bits = f[:bits]
  coded = ch
  sb = []
  i = 0
  while i < ch.size
    sb.push(bits)
    i += 1
  if f[:cha] >= 8 && f[:cha] <= 10
    l = ch[0]
    r = ch[1]
    side = []
    mid = []
    i = 0
    while i < bs
      side.push(l[i] - r[i])
      mid.push(fshr(l[i] + r[i], 1))
      i += 1
    if f[:cha] == 8
      coded = [l, side]
      sb = [bits, bits + 1]
    elsif f[:cha] == 9
      coded = [side, r]
      sb = [bits + 1, bits]
    else
      coded = [mid, side]
      sb = [bits, bits + 1]
  c = 0
  while c < coded.size
    enc_sub(w, coded[c], sb[c], f[:subs][c % f[:subs].size])
    c += 1
  align(w)
  c16 = crc16(w[:b], 0, w[:b].size)
  c16 = c16 ^ 1 if f[:bad16] != nil
  put(w, c16, 16)
  i = 0
  while i < w[:b].size
    out.push(w[:b][i])
    i += 1
  out

-> put_bytes(out, v, n)
  k = n - 1
  while k >= 0
    out.push((v >> (8 * k)) & 255)
    k -= 1
  out

# the PCM's MD5 as FLAC defines it, computed here: interleaved, little-endian, ceil(bits/8) bytes
-> md5_of(chans, bits)
  bps = (bits + 7) / 8
  n = chans[0].size
  b = u8[n * chans.size * bps]
  o = 0
  i = 0
  while i < n
    c = 0
    while c < chans.size
      v = chans[c][i]
      v = v + 4294967296 if v < 0
      k = 0
      while k < bps
        b[o] = (v >> (8 * k)) & 255
        o += 1
        k += 1
      c += 1
    i += 1
  Digest.md5_bytes(b)

# a stream: STREAMINFO (+ extra blocks) then the frames; opts {minbs, maxbs, rate, bits, total, id3, extra, noinfo, infolen}
-> enc_stream(chans, frames_bytes, o)
  out = []
  if o[:id3] != nil
    out = out + [73, 68, 51, 3, 0, 0, 0, 0, 0, 5, 1, 2, 3, 4, 5]
  out = out + [102, 76, 97, 67]
  md = md5_of(chans, o[:bits])
  extra = []
  extra = o[:extra] if o[:extra] != nil
  if o[:noinfo] == nil
    out.push(extra.size == 0 ? 128 : 0)
    ln = 34
    ln = o[:infolen] if o[:infolen] != nil
    put_bytes(out, ln, 3)
    w = bw_new()
    put(w, o[:minbs], 16)
    put(w, o[:maxbs], 16)
    put(w, 0, 24)
    put(w, 0, 24)
    put(w, o[:rate], 20)
    put(w, chans.size - 1, 3)
    put(w, o[:bits] - 1, 5)
    tot = chans[0].size
    tot = o[:total] if o[:total] != nil
    put(w, tot >> 32, 4)
    put(w, tot & 4294967295, 32)
    out = out + w[:b]
    i = 0
    while i < 16
      out.push(md[i])
      i += 1
    while ln > 34
      out.push(0)
      ln -= 1
  i = 0
  while i < extra.size
    out.push((i == extra.size - 1 ? 128 : 0) | extra[i][0])
    put_bytes(out, extra[i][1].size, 3)
    out = out + extra[i][1]
    i += 1
  out = out + frames_bytes
  b = u8[out.size]
  i = 0
  while i < out.size
    b[i] = out[i]
    i += 1
  b

# a deterministic test signal: a sine of amplitude amp plus noise of amplitude na, clipped to bits
-> sig(n, amp, per, ph, na, seed, bits)
  out = []
  x = seed
  hi = (1 << (bits - 1)) - 1
  lo = 0 - (1 << (bits - 1))
  i = 0
  while i < n
    x = (x * 1103515245 + 12345) % 2147483648
    v = (amp * Math.sin(~6.283185307179586 * i.to_f / per + ph)).round.to_i
    v += (x % (2 * na + 1)) - na if na > 0
    v = hi if v > hi
    v = lo if v < lo
    out.push(v)
    i += 1
  out

-> cut(xs, at, n)
  xs.slice(at, n)

-> same_pcm(name, d, chans)
  ch = chans.size
  n = chans[0].size
  check(name + " frames", d[:frames], n)
  check(name + " channels", d[:ch], ch)
  i = 0
  while i < n
    c = 0
    while c < ch
      if d[:pcm][i * ch + c] != chans[c][i]
        fail_check(name, "frame " + i.to_s + " channel " + c.to_s + ": got " + d[:pcm][i * ch + c].to_s + " want " + chans[c][i].to_s)
      c += 1
    i += 1

-> expect_raise(name, b, text)
  got = ""
  begin
    flac_decode(b)
  rescue e
    got = e.to_s
  if !got.include?(text)
    fail_check(name, "expected an error with '" + text + "', got '" + got + "'")

-> md5_hex(bytes)
  hx = "0123456789abcdef"
  s = ""
  i = 0
  while i < bytes.size
    s = s + hx.slice(bytes[i] >> 4, 1) + hx.slice(bytes[i] & 15, 1)
    i += 1
  s

LPC = {t: "lpc", order: 2, coefs: [1800, -790], prec: 12, shift: 10, method: 0, porder: 2, ks: [-2]}

# ---- 1. mono 16-bit: every subframe type, predictor order, Rice method, partition order, escapes, wasted bits ------------------
bs1 = 4096
m1 = sig(bs1 * 12 + 1000, ~12000.0, ~180.0, ~0.0, 40, 7, 16)
# frame 0 constant, frame 1 verbatim: overwrite with a constant and keep the noise
i = 0
while i < bs1
  m1[i] = -1234
  i += 1
# frame 11: wasted bits (every sample a multiple of 8)
i = bs1 * 11
while i < bs1 * 12
  m1[i] = fshr(m1[i], 3) * 8
  i += 1
subs1 = [{t: "constant"}, {t: "verbatim"},
  {t: "fixed", order: 0, method: 0, porder: 0, ks: [-2]},
  {t: "fixed", order: 1, method: 1, porder: 3, ks: [-2]},
  {t: "fixed", order: 2, method: 0, porder: 8, ks: [-2, -1]},
  {t: "fixed", order: 3, method: 1, porder: 4, ks: [-2, 0, -1, 30]},
  {t: "fixed", order: 4, method: 0, porder: 5, ks: [-2]},
  {t: "lpc", order: 1, coefs: [31], prec: 6, shift: 5, method: 0, porder: 0, ks: [-2]},
  {t: "lpc", order: 8, coefs: [900, -300, 120, -60, 30, -15, 7, -3], prec: 12, shift: 9, method: 1, porder: 6, ks: [-2]},
  {t: "lpc", order: 12, coefs: [3000, -2000, 1500, -1000, 700, -500, 300, -200, 100, -50, 25, -10], prec: 15, shift: 12, method: 0, porder: 4, ks: [-2, -1]},
  {t: "lpc", order: 32, coefs: [16383, -16384, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30], prec: 15, shift: 15, method: 1, porder: 3, ks: [-2]},
  {t: "fixed", order: 2, wasted: 3, method: 0, porder: 2, ks: [-2]}]
fb = []
k = 0
while k < 12
  enc_frame(fb, {strat: 0, bsc: 12, src: 0, cha: 0, ssc: 0, num: k, bits: 16, chans: [cut(m1, k * bs1, bs1)], subs: [subs1[k]]})
  k += 1
# a short last block: 16-bit block size extension, escapes of width 0 (an all-zero tail)
i = bs1 * 12 + 600
while i < m1.size
  m1[i] = 0
  i += 1
enc_frame(fb, {strat: 0, bsc: 7, src: 9, cha: 0, ssc: 4, num: 12, bits: 16, chans: [cut(m1, bs1 * 12, 1000)], subs: [{t: "fixed", order: 1, method: 0, porder: 3, ks: [-2, -2, -2, -2, -2, -1, -1, -1]}]})
s1 = enc_stream([m1], fb, {minbs: 1000, maxbs: 4096, rate: 44100, bits: 16})
h1 = flac_header_into(s1, i64[16])
check("mono header", [h1[0], h1[1], h1[2], h1[3], h1[5], h1[6]], [1, 16, 44100, m1.size, 1000, 4096])
d1 = flac_decode(s1)
same_pcm("mono 16-bit", d1, [m1])
check("mono md5 field", d1[:md5], md5_hex(md5_of([m1], 16)))
check("mono decoded md5", flac_pcm_md5(d1[:pcm], d1[:frames], 1, 16), d1[:md5])

# ---- 2. stereo 24-bit: independent, left/side, side/right, mid/side; 8-bit block size, explicit rate and size codes ------------
bs2 = 1152
lt = sig(bs2 * 5, ~6000000.0, ~97.0, ~0.0, 900, 11, 24)
rt = sig(bs2 * 5, ~5500000.0, ~101.0, ~1.3, 700, 13, 24)
# full scale in the last frame (the side channel needs 25 bits)
i = bs2 * 4
while i < bs2 * 5
  v = 8388607
  v = -8388608 if (i / 5) % 2 == 1
  lt[i] = v
  rt[i] = 0 - v - 1
  i += 1
fb2 = []
chas = [1, 8, 9, 10, 10]
k = 0
while k < 5
  enc_frame(fb2, {strat: 0, bsc: 3, src: (k % 2 == 0 ? 10 : 0), cha: chas[k], ssc: (k % 2 == 0 ? 6 : 0), num: k, bits: 24,
    chans: [cut(lt, k * bs2, bs2), cut(rt, k * bs2, bs2)],
    subs: [LPC, {t: "fixed", order: 2, method: 1, porder: 4, ks: [-2]}]})
  k += 1
lt2 = lt + sig(200, ~1000.0, ~20.0, ~0.0, 3, 17, 24)
rt2 = rt + sig(200, ~900.0, ~21.0, ~0.0, 3, 19, 24)
enc_frame(fb2, {strat: 0, bsc: 6, src: 10, cha: 10, ssc: 6, num: 5, bits: 24, chans: [cut(lt2, bs2 * 5, 200), cut(rt2, bs2 * 5, 200)],
  subs: [{t: "verbatim"}, {t: "fixed", order: 4, method: 0, porder: 0, ks: [-1]}]})
s2 = enc_stream([lt2, rt2], fb2, {minbs: 200, maxbs: 1152, rate: 48000, bits: 24})
d2 = flac_decode(s2)
same_pcm("stereo 24-bit", d2, [lt2, rt2])
check("stereo rate", d2[:rate], 48000)
check("stereo decoded md5", flac_pcm_md5(d2[:pcm], d2[:frames], 2, 24), d2[:md5])

# ---- 3. eight 8-bit channels; block size codes 1, 2, 4, 5, 8 and 15; rate code 12 ----------------------------------------------
sizes = [192, 576, 2304, 4608, 256, 32768]
codes = [1, 2, 4, 5, 8, 15]
tot3 = 0
k = 0
while k < sizes.size
  tot3 += sizes[k]
  k += 1
ch3 = []
c = 0
while c < 8
  ch3.push(sig(tot3, ~100.0, (30 + 7 * c) * ~1.0, c * ~0.4, 10, 23 + c, 8))
  c += 1
fb3 = []
at = 0
k = 0
while k < sizes.size
  parts = []
  c = 0
  while c < 8
    parts.push(cut(ch3[c], at, sizes[k]))
    c += 1
  enc_frame(fb3, {strat: 0, bsc: codes[k], src: 12, rate: 22000, cha: 7, ssc: 1, num: k, bits: 8, chans: parts,
    subs: [{t: "fixed", order: 2, method: 0, porder: 1, ks: [-2]}, {t: "verbatim"}, LPC, {t: "constant", wasted: 0}]})
  at += sizes[k]
  k += 1
# the constant subframes (channels 3 and 7) need constant channels
i = 0
while i < tot3
  ch3[3][i] = 0
  ch3[7][i] = 0
  i += 1
fb3 = []
at = 0
k = 0
while k < sizes.size
  parts = []
  c = 0
  while c < 8
    parts.push(cut(ch3[c], at, sizes[k]))
    c += 1
  enc_frame(fb3, {strat: 0, bsc: codes[k], src: 12, rate: 22000, cha: 7, ssc: 1, num: k, bits: 8, chans: parts,
    subs: [{t: "fixed", order: 2, method: 0, porder: 1, ks: [-2]}, {t: "verbatim"}, LPC, {t: "constant"}]})
  at += sizes[k]
  k += 1
s3 = enc_stream(ch3, fb3, {minbs: 192, maxbs: 32768, rate: 22000, bits: 8})
d3 = flac_decode(s3)
same_pcm("eight 8-bit channels", d3, ch3)
check("eight-channel decoded md5", flac_pcm_md5(d3[:pcm], d3[:frames], 8, 8), d3[:md5])

# ---- 4. 32-bit mid/side (a 33-bit side channel), 12- and 20-bit streams, rate codes 13 and 14 -------------------------------
l4 = sig(2048, ~2000000000.0, ~50.0, ~0.0, 1000000, 29, 32)
r4 = sig(2048, ~2100000000.0, ~45.0, ~2.0, 1000000, 31, 32)
l4[5] = 2147483647
r4[5] = -2147483648
l4[6] = -2147483648
r4[6] = 2147483647
fb4 = []
enc_frame(fb4, {strat: 0, bsc: 9, src: 0, cha: 10, ssc: 7, num: 0, bits: 32, chans: [cut(l4, 0, 512), cut(r4, 0, 512)], subs: [{t: "verbatim"}, {t: "fixed", order: 1, method: 1, porder: 0, ks: [-2]}]})
enc_frame(fb4, {strat: 0, bsc: 9, src: 0, cha: 8, ssc: 7, num: 1, bits: 32, chans: [cut(l4, 512, 512), cut(r4, 512, 512)], subs: [{t: "fixed", order: 3, method: 1, porder: 2, ks: [-2]}]})
enc_frame(fb4, {strat: 0, bsc: 10, src: 0, cha: 9, ssc: 7, num: 2, bits: 32, chans: [cut(l4, 1024, 1024), cut(r4, 1024, 1024)], subs: [{t: "lpc", order: 3, coefs: [2, -1, 0], prec: 3, shift: 0, method: 1, porder: 1, ks: [-2]}]})
s4 = enc_stream([l4, r4], fb4, {minbs: 512, maxbs: 1024, rate: 96000, bits: 32})
same_pcm("32-bit stereo", flac_decode(s4), [l4, r4])
m5 = sig(3000, ~1500.0, ~33.0, ~0.0, 20, 37, 12)
fb5 = []
enc_frame(fb5, {strat: 0, bsc: 7, src: 13, rate: 11025, cha: 0, ssc: 2, num: 0, bits: 12, chans: [cut(m5, 0, 3000)], subs: [LPC]})
same_pcm("12-bit, rate code 13", flac_decode(enc_stream([m5], fb5, {minbs: 3000, maxbs: 3000, rate: 11025, bits: 12})), [m5])
m6 = sig(3000, ~400000.0, ~33.0, ~0.0, 200, 41, 20)
fb6 = []
enc_frame(fb6, {strat: 0, bsc: 7, src: 14, rate: 88200, cha: 0, ssc: 5, num: 0, bits: 20, chans: [cut(m6, 0, 3000)], subs: [{t: "fixed", order: 2, wasted: 0, method: 0, porder: 0, ks: [-2]}]})
same_pcm("20-bit, rate code 14", flac_decode(enc_stream([m6], fb6, {minbs: 3000, maxbs: 3000, rate: 88200, bits: 20})), [m6])
# the fixed rate codes
rates = [88200, 176400, 192000, 8000, 16000, 22050, 24000, 32000, 44100, 48000, 96000]
k = 0
while k < rates.size
  fr = []
  enc_frame(fr, {strat: 0, bsc: 6, src: k + 1, cha: 0, ssc: 4, num: 0, bits: 16, chans: [cut(m1, 4096, 64)], subs: [{t: "verbatim"}]})
  d = flac_decode(enc_stream([cut(m1, 4096, 64)], fr, {minbs: 64, maxbs: 64, rate: rates[k], bits: 16}))
  check("rate code " + (k + 1).to_s, d[:rate], rates[k])
  k += 1

# ---- 5. variable blocking, coded numbers of 1..7 bytes, an ID3v2 tag, PADDING and APPLICATION blocks --------------------------
nums = [0, 200, 3000, 70000, 3000000, 100000000, 40000000000]
m7 = sig(64 * nums.size, ~3000.0, ~17.0, ~0.0, 5, 43, 16)
fb7 = []
k = 0
while k < nums.size
  enc_frame(fb7, {strat: 1, bsc: 6, src: 0, cha: 0, ssc: 0, num: nums[k], bits: 16, chans: [cut(m7, 64 * k, 64)], subs: [{t: "fixed", order: 1, method: 0, porder: 0, ks: [-2]}]})
  k += 1
s7 = enc_stream([m7], fb7, {minbs: 64, maxbs: 64, rate: 44100, bits: 16, id3: 1, extra: [[1, [0, 0, 0, 0, 0, 0, 0, 0]], [2, [114, 105, 102, 102, 1, 2, 3]], [4, [0, 0, 0, 0]]]})
same_pcm("variable blocking, ID3, extra blocks", flac_decode(s7), [m7])

# ---- 6. the planar reader: floats / 2^(bits − 1), mono into both channels, a prefix decoded ---------------------------------
st = flac_state_new()
p1 = flac_read_planar_with(st, s1, 5000)
check("planar rate", p1[0], 44100)
check("planar frames", p1[1], 5000)
ok = 1
i = 0
while i < 5000
  ok = 0 if p1[2][i] != (m1[i] * ~1.0) / ~32768.0 || p1[3][i] != p1[2][i]
  i += 1
check("planar mono samples", ok, 1)
p2 = flac_read_planar_with(st, s2, 0)
check("planar all frames", p2[1], lt2.size)
ok = 1
i = 0
while i < lt2.size
  ok = 0 if p2[2][i] != (lt2[i] * ~1.0) / ~8388608.0 || p2[3][i] != (rt2[i] * ~1.0) / ~8388608.0
  i += 1
check("planar stereo samples", ok, 1)
p1b = flac_read_planar(s1, 5000)
check("planar (one-file buffers) equals the batch reader", [p1b[0], p1b[1], p1b[2][4999] == p1[2][4999], p1b[3][17] == p1[3][17]], [44100, 5000, true, true])
p2b = flac_read_planar(s2, 0)
ok = 1
i = 0
while i < lt2.size
  ok = 0 if p2b[2][i] != p2[2][i] || p2b[3][i] != p2[3][i]
  i += 1
check("planar stereo (one-file buffers)", ok, 1)
p3 = flac_read_planar_with(st, s3, 100)
check("planar eight channels: the first two", [p3[2][7] == (ch3[0][7] * ~1.0) / ~128.0, p3[3][7] == (ch3[1][7] * ~1.0) / ~128.0], [true, true])

# ---- 6b. the streaming MD5 against Digest.md5: every length 0..200 (block edges), fed whole and in pieces; a long buffer -------
k = 0
x = 5
while k <= 200
  bb = u8[k]
  i = 0
  while i < k
    x = (x * 1103515245 + 12345) % 2147483648
    bb[i] = x % 256
    i += 1
  m1d = flac_md5_new()
  flac_md5_feed(m1d, bb, 0, k)
  m2d = flac_md5_new()
  i = 0
  while i < k
    step = 1 + (i * 7) % 70
    step = k - i if i + step > k
    flac_md5_feed(m2d, bb, i, step)
    i += step
  want = Digest.md5(bb)
  check("md5 of " + k.to_s + " bytes", flac_md5_hex(m1d), want)
  check("md5 of " + k.to_s + " bytes in pieces", flac_md5_hex(m2d), want)
  k += 1
big = u8[1000003]
i = 0
while i < big.size
  big[i] = (i * 31 + i / 977) % 256
  i += 1
mb = flac_md5_new()
flac_md5_feed(mb, big, 0, big.size)
check("md5 of a megabyte", flac_md5_hex(mb), Digest.md5(big))
check("md5 of nothing", flac_md5_hex(flac_md5_feed(flac_md5_new(), u8[0], 0, 0)), "d41d8cd98f00b204e9800998ecf8427e")

# ---- 7. flaccheck against WAVs: identical, one sample different -------------------------------------------------------------
-> le_put(out, v, n)
  i = 0
  while i < n
    out.push((v >> (8 * i)) & 255)
    i += 1
  out

-> wav_bytes(chans, bits, rate)
  bps = bits / 8
  n = chans[0].size
  ch = chans.size
  data = n * ch * bps
  h = [82, 73, 70, 70]
  le_put(h, 36 + data + data % 2, 4)
  h = h + [87, 65, 86, 69, 102, 109, 116, 32]
  le_put(h, 16, 4)
  le_put(h, 1, 2)
  le_put(h, ch, 2)
  le_put(h, rate, 4)
  le_put(h, rate * ch * bps, 4)
  le_put(h, ch * bps, 2)
  le_put(h, bits, 2)
  h = h + [100, 97, 116, 97]
  le_put(h, data, 4)
  b = u8[h.size + data + data % 2]
  i = 0
  while i < h.size
    b[i] = h[i]
    i += 1
  o = h.size
  i = 0
  while i < n
    c = 0
    while c < ch
      v = chans[c][i]
      v = v + (1 << bits) if v < 0
      k = 0
      while k < bps
        b[o] = (v >> (8 * k)) & 255
        o += 1
        k += 1
      c += 1
    i += 1
  b

tmp = Tempfile.new("tungsten-flac-spec")
base = tmp.path
tmp.close!()
File.mkdir_p(base + "/f/a")
File.mkdir_p(base + "/w/a")
File.write_bytes(base + "/f/a/one.flac", s1)
File.write_bytes(base + "/w/a/one.wav", wav_bytes([m1], 16, 44100))
File.write_bytes(base + "/f/two.flac", s2)
wrong = wav_bytes([lt2, rt2], 24, 48000)
wrong[44 + 6 * 100 + 2] = wrong[44 + 6 * 100 + 2] ^ 1
File.write_bytes(base + "/w/two.wav", wrong)
rc = flaccheck_cli(["flaccheck", base + "/f", "--wav", base + "/w", "--out", base + "/out.tsv"])
check("flaccheck exit code (one file differs)", rc, 1)
rows = File.read(base + "/out.tsv").split("\n").select(->(x) x.size > 0).sort
check("flaccheck rows", rows.size, 2)
r0 = rows[0].split("\t")
check("flaccheck identical file", [r0[0], r0[1], r0[2], r0[6], r0[7]], ["a/one.flac", "OK", m1.size.to_s, d1[:md5], Digest.md5(File.read_bytes(base + "/w/a/one.wav"))])
r1 = rows[1].split("\t")
check("flaccheck differing file", [r1[0], r1[1]], ["two.flac", "FAIL"])
check("flaccheck names the first differing frame", r1[8].include?("frame 100"), true)
check("flaccheck: the decoded MD5 still matches STREAMINFO", r1[6], d2[:md5])
# resumable: nothing left to check
rc2 = flaccheck_cli(["flaccheck", base + "/f", "--wav", base + "/w", "--out", base + "/out.tsv"])
check("flaccheck resume rows", File.read(base + "/out.tsv").split("\n").select(->(x) x.size > 0).size, 2)
check("flaccheck resume exit code", rc2, 0)
File.delete(base + "/f/a/one.flac")
File.delete(base + "/f/two.flac")
File.delete(base + "/w/a/one.wav")
File.delete(base + "/w/two.wav")
File.delete(base + "/out.tsv")

# ---- 8. malformed streams ----------------------------------------------------------------------------------------------------
-> frame1(f)
  fb = []
  enc_frame(fb, f)
  enc_stream([cut(m1, 4096, 256)], fb, {minbs: 256, maxbs: 256, rate: 44100, bits: 16})

-> good_frame
  {strat: 0, bsc: 8, src: 0, cha: 0, ssc: 0, num: 0, bits: 16, chans: [cut(m1, 4096, 256)], subs: [LPC]}

check("a good one-frame stream decodes", flac_decode(frame1(good_frame()))[:frames], 256)
expect_raise("too short", u8[6], "too short")
nm = frame1(good_frame())
nm[0] = 0
expect_raise("not FLAC", nm, "not a FLAC stream")
expect_raise("no STREAMINFO first", enc_stream([m7], [], {noinfo: 1, bits: 16, extra: [[1, [0, 0, 0, 0]]]}), "the first metadata block is not STREAMINFO")
expect_raise("STREAMINFO length", enc_stream([m7], [], {minbs: 64, maxbs: 64, rate: 44100, bits: 16, infolen: 40}), "STREAMINFO is 40 bytes")
expect_raise("no total", enc_stream([m7], [], {minbs: 64, maxbs: 64, rate: 44100, bits: 16, total: 0}), "no total sample count")
expect_raise("block sizes", enc_stream([m7], [], {minbs: 8, maxbs: 64, rate: 44100, bits: 16}), "block sizes")
expect_raise("bits", enc_stream([cut(m7, 0, 64)], [], {minbs: 64, maxbs: 64, rate: 44100, bits: 3}), "bits per sample")
-> head_of(b, n)
  out = u8[n]
  i = 0
  while i < n
    out[i] = b[i]
    i += 1
  out

mc = frame1(good_frame())
expect_raise("metadata past the end", head_of(mc, 20), "metadata block of type 0 runs past the end")
g = good_frame()
g[:bad8] = 1
expect_raise("header CRC-8", frame1(g), "frame header CRC-8 mismatch")
g = good_frame()
g[:bad16] = 1
expect_raise("frame CRC-16", frame1(g), "frame CRC-16 mismatch")
g = good_frame()
g[:cha] = 11
expect_raise("reserved channel assignment", frame1(g), "bad frame header")
g = good_frame()
g[:ssc] = 3
expect_raise("reserved sample size", frame1(g), "bad frame header")
g = good_frame()
g[:bsc] = 0
expect_raise("reserved block size", frame1(g), "bad frame header")
g = good_frame()
g[:src] = 15
expect_raise("invalid rate code", frame1(g), "bad frame header")
g = good_frame()
g[:subs] = [{t: "verbatim", rawtype: 2}]
expect_raise("reserved subframe type", frame1(g), "bad subframe header")
g = good_frame()
g[:subs] = [{t: "lpc", order: 2, coefs: [1, 1], prec: 11, shift: 10, method: 0, porder: 2, ks: [-2], rawprec: 15}]
expect_raise("LPC precision 15", frame1(g), "bad LPC precision or shift")
g = good_frame()
g[:subs] = [{t: "lpc", order: 2, coefs: [1, 1], prec: 11, shift: 10, method: 0, porder: 2, ks: [-2], rawshift: -2}]
expect_raise("negative LPC shift", frame1(g), "bad LPC precision or shift")
g = good_frame()
g[:subs] = [{t: "fixed", order: 1, method: 0, porder: 2, ks: [-2], rawmethod: 2}]
expect_raise("reserved residual method", frame1(g), "bad residual coding")
g = good_frame()
g[:subs] = [{t: "verbatim", wasted: 16}]
expect_raise("wasted bits >= bits", frame1(g), "bad subframe header")
g = good_frame()
g[:cha] = 1
g[:chans] = [cut(m1, 4096, 256), cut(m1, 4096, 256)]
expect_raise("channels unlike STREAMINFO", frame1(g), "frame does not match STREAMINFO")
# a block size the partition order does not divide (bs 250, order 1 at 2 partitions of 125: fine; order 2: 62.5)
fb = []
enc_frame(fb, {strat: 0, bsc: 6, src: 0, cha: 0, ssc: 0, num: 0, bits: 16, chans: [cut(m1, 4096, 250)], subs: [{t: "fixed", order: 1, method: 0, porder: 2, ks: [-2]}]})
expect_raise("partition order", enc_stream([cut(m1, 4096, 250)], fb, {minbs: 250, maxbs: 250, rate: 44100, bits: 16}), "bad residual coding")
# lost sync: a garbage byte before the frame
gs = frame1(good_frame())
lost = u8[gs.size + 1]
i = 0
while i < gs.size
  lost[i + (i >= 42 ? 1 : 0)] = gs[i]
  i += 1
lost[42] = 0x55
expect_raise("lost sync", lost, "lost frame sync (frame at byte 42")
# truncated: the stream cut inside the frame
expect_raise("truncated", head_of(gs, gs.size - 30), "truncated frame")
# no frames at all where STREAMINFO promises samples
expect_raise("no frames", head_of(gs, 42), "truncated frame")

# ---- 9. corrupted streams raise (or, where a flip hits padding, decode): never a crash --------------------------------------
x = 99
raised = 0
k = 0
while k < 400
  bad = head_of(s2, s2.size)
  x = (x * 1103515245 + 12345) % 2147483648
  at = 42 + x % (s2.size - 42)
  x = (x * 1103515245 + 12345) % 2147483648
  bad[at] = bad[at] ^ (1 + x % 255)
  begin
    flac_decode(bad)
  rescue e
    raised += 1 if e.to_s.starts_with?("flac: ")
  k += 1
check("every corrupted stream is caught (CRC or structure)", raised, 400)

<< "flac spec: all checks passed"
