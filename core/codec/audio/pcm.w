# core/codec/audio/pcm — the "pcm " audio codec: integer (8-bit unsigned, 16/24/32
# signed) and IEEE float (32/64) PCM, little- or big-endian, to Float32.
# cfg.extra = {bits:, float:, big_endian:} (see mediacore).

use core/codec/media

-> pcm_to_f32(src, n, bits, isf, be, out) (u8[] i64 i64 bool bool f32[]) i64
  bpsm = bits / 8
  i = 0 ## i64
  while i < n
    o = i * bpsm
    if isf
      if bits == 32
        v = be ? (src[o] << 24) | (src[o + 1] << 16) | (src[o + 2] << 8) | src[o + 3] : src[o] | (src[o + 1] << 8) | (src[o + 2] << 16) | (src[o + 3] << 24)
        out[i] = pcm_f32_from_bits(v)
      else
        hi = be ? (src[o] << 24) | (src[o + 1] << 16) | (src[o + 2] << 8) | src[o + 3] : src[o + 4] | (src[o + 5] << 8) | (src[o + 6] << 16) | (src[o + 7] << 24)
        out[i] = pcm_f32_from_f64_hi(hi)
    elsif bits == 16
      v = be ? (src[o] << 8) | src[o + 1] : src[o] | (src[o + 1] << 8)
      v = v - 65536 if v >= 32768
      out[i] = (v.to_f * ~0.000030517578125) ## f32
    elsif bits == 24
      v = be ? (src[o] << 16) | (src[o + 1] << 8) | src[o + 2] : src[o] | (src[o + 1] << 8) | (src[o + 2] << 16)
      v = v - 16777216 if v >= 8388608
      out[i] = (v.to_f / ~8388608.0) ## f32
    elsif bits == 32
      v = be ? (src[o] << 24) | (src[o + 1] << 16) | (src[o + 2] << 8) | src[o + 3] : src[o] | (src[o + 1] << 8) | (src[o + 2] << 16) | (src[o + 3] << 24)
      v = v - 4294967296 if v >= 2147483648
      out[i] = (v.to_f / ~2147483648.0) ## f32
    else
      out[i] = ((src[o] - 128).to_f / ~128.0) ## f32
    i += 1
  n

# binary32 bits → value (typed, no allocation).
-> pcm_f32_from_bits(v) (i64) f32
  e = (v >> 23) & 255
  m = v & 0x7FFFFF
  s = (v >> 31) == 1 ? ~-1.0 : ~1.0
  if e == 0
    return (s * m.to_f * ~1.401298464324817e-45) ## f32
  if e == 255
    return (~0.0) ## f32
  x = s * (~1.0 + m.to_f / ~8388608.0)
  # scale by 2^(e-127) with exact power-of-two multiplies
  k = e - 127
  while k > 0
    x = x * ~2.0
    k -= 1
  while k < 0
    x = x * ~0.5
    k += 1
  x ## f32

# binary64 from its high 32 bits (enough precision for audio).
-> pcm_f32_from_f64_hi(hi) (i64) f32
  e = (hi >> 20) & 2047
  m = hi & 0xFFFFF
  s = (hi >> 31) == 1 ? ~-1.0 : ~1.0
  if e == 0 || e == 2047
    return (~0.0) ## f32
  x = s * (~1.0 + m.to_f / ~1048576.0)
  k = e - 1023
  while k > 0
    x = x * ~2.0
    k -= 1
  while k < 0 && k > -200
    x = x * ~0.5
    k += 1
  x ## f32

+ PcmDec
  -> new(cfg)
    x = cfg.extra
    @bits = x == nil ? 16 : x[:bits]
    @isf = x == nil ? false : x[:float] == true
    @be = x == nil ? false : x[:big_endian] == true
    @ch = cfg.channels < 1 ? 1 : cfg.channels
    @rate = cfg.sample_rate

  -> decode(s)
    bps = @bits / 8
    n = s.data.size / bps
    n = n - n % @ch
    out = f32[n]
    pcm_to_f32(s.data, n, @bits, @isf, @be, out)
    AudioBlock.new(out, n / @ch, @ch, @rate, s.pts)

  -> flush
    nil

  -> reset
    nil

acodec_register("pcm ", ->(cfg) PcmDec.new(cfg))
