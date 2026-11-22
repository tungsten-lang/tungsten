# core/codec/audio/latm — LOAS / LATM framing (ISO/IEC 14496-3 1.7) for AAC and
# USAC (xHE-AAC) elementary streams: AudioSyncStream (0x2B7 sync, 13-bit
# length) carrying AudioMuxElement(1) with StreamMuxConfig.
#
#   latm_es_parse(bytes) -> {cfg:, samples:, duration:}   (es parser :loas)
#
# One program, one layer, frameLengthType 0 (PayloadLengthInfo in bytes) —
# what encoders write for broadcast and for .loas / .xhe files. The
# AudioSpecificConfig is re-emitted byte aligned as cfg.extra ("mp4a"), so
# the AAC / USAC decoders see the same config as from MP4.

use core/codec/media

-> latm_bits(b, st, n)
  v = 0
  i = 0
  while i < n
    p = st[0]
    bit = 0
    bit = (b[p >> 3] >> (7 - (p & 7))) & 1 if (p >> 3) < b.size
    v = (v << 1) | bit
    st[0] = p + 1
    i += 1
  v

-> latm_value(b, st)
  nb = latm_bits(b, st, 2)
  v = 0
  k = 0
  while k <= nb
    v = (v << 8) | latm_bits(b, st, 8)
    k += 1
  v

# Bit length of an AudioSpecificConfig starting at bit pos (enough for AAC
# LC / HE / HEv2 with GASpecificConfig and for USAC, AOT 42).
-> latm_asc_bits(b, pos)
  st = [pos]
  aot = latm_bits(b, st, 5)
  aot = 32 + latm_bits(b, st, 6) if aot == 31
  fi = latm_bits(b, st, 4)
  latm_bits(b, st, 24) if fi == 15
  cc = latm_bits(b, st, 4)
  if aot == 42
    tmp = latm_copy_bits(b, pos, b.size * 8 - pos)
    return UsacDec.new(CodecConfig.new("mp4a", tmp)).asc_bits
  if aot == 5 || aot == 29
    fi = latm_bits(b, st, 4)
    latm_bits(b, st, 24) if fi == 15
    aot = latm_bits(b, st, 5)
    aot = 32 + latm_bits(b, st, 6) if aot == 31
  # GASpecificConfig: frameLengthFlag, dependsOnCoreCoder (+14), extensionFlag
  latm_bits(b, st, 1)
  latm_bits(b, st, 14) if latm_bits(b, st, 1) == 1
  latm_bits(b, st, 1)
  st[0] - pos

-> latm_copy_bits(b, pos, n)
  nbytes = (n + 7) / 8
  out = u8[nbytes]
  st = [pos]
  i = 0
  while i < nbytes
    k = n - i * 8
    k = 8 if k > 8
    out[i] = latm_bits(b, st, k) << (8 - k)
    i += 1
  out

-> latm_es_parse(bytes)
  b = bytes
  if b.is_a?(String)
    b = ccall("w_string_bytes_view", b) ## u8[]
  pos = 0
  asc = nil
  samples = []
  rate = 0
  frame = 1024
  while pos + 3 <= b.size
    if b[pos] != 0x56 || (b[pos + 1] & 0xE0) != 0xE0
      pos += 1
    else
      len = ((b[pos + 1] & 0x1F) << 8) | b[pos + 2]
      start = pos + 3
      break if start + len > b.size
      st = [start * 8]
      ok = true
      if latm_bits(b, st, 1) == 0                       # !useSameStreamMux
        ver = latm_bits(b, st, 1)
        vera = ver == 1 ? latm_bits(b, st, 1) : 0
        ok = false if vera == 1
        if ok
          latm_value(b, st) if ver == 1                 # taraBufferFullness
          latm_bits(b, st, 1)                           # allStreamsSameTimeFraming
          latm_bits(b, st, 6)                           # numSubFrames
          latm_bits(b, st, 4)                           # numProgram
          latm_bits(b, st, 3)                           # numLayer
          alen = 0
          alen = latm_value(b, st) if ver == 1
          ap = st[0]
          n = latm_asc_bits(b, ap)
          asc = latm_copy_bits(b, ap, n) if asc == nil
          st[0] = ap + (ver == 1 ? alen : n)
          flt = latm_bits(b, st, 3)
          ok = false if flt != 0
          if ok
            latm_bits(b, st, 8)                         # latmBufferFullness
            if latm_bits(b, st, 1) == 1                 # otherDataPresent
              if ver == 1
                latm_value(b, st)
              else
                more = 1
                while more == 1
                  more = latm_bits(b, st, 1)
                  latm_bits(b, st, 8)
            latm_bits(b, st, 8) if latm_bits(b, st, 1) == 1   # crc
      if ok && asc != nil
        plen = 0
        t = 255
        while t == 255
          t = latm_bits(b, st, 8)
          plen += t
        payload = u8[plen]
        i = 0
        while i < plen
          payload[i] = latm_bits(b, st, 8)
          i += 1
        samples.push(payload)
      pos = start + len
  raise MediaError.new("latm: no StreamMuxConfig") if asc == nil
  cfg = CodecConfig.new("mp4a", asc)
  dec = aac_make_decoder(cfg)
  rate = dec.sample_rate
  frame = dec.is_a?(UsacDec) ? dec.out_frame : 1024
  cfg.sample_rate = rate
  cfg.channels = dec.channels
  out = []
  dt = frame / (rate * 1.0)
  k = 0
  while k < samples.size
    out.push(MediaSample.new(samples[k], k * dt, k * dt, dt, true))
    k += 1
  {cfg: cfg, samples: out, duration: samples.size * dt}

es_parser_register(:loas, ->(b) latm_es_parse(b))
