# core/codec/audio/opus — Opus audio decoder (RFC 6716 with the RFC 8251 updates) in
# pure Tungsten: TOC / frame packing (codes 0-3, padding), SILK, CELT and
# hybrid modes, mode transitions with CELT redundancy frames, packet-loss
# concealment, and multistream (channel mapping families 0, 1 and 255).
# Output is always 48 kHz float, channels in WAVE order.
#
#   acodec_register("opus", ->(cfg) OpusDec.new(cfg))
#
# cfg.extra is the OpusHead packet ("OpusHead", version, channel count,
# pre-skip, input rate, output gain Q7.8 dB, mapping family [, stream count,
# coupled count, mapping table]). The decoder applies the output gain and
# libopus' soft clipping; it does not trim pre-skip (the pipeline does).
#
# Layers: opus_rangedec (entropy decoder), opus_silk (SILK, bit-exact fixed
# point), opus_celt (CELT, float), opus_tables (constant tables).

use core/codec/media
use opus_rangedec
use opus_tables
use opus_silk
use opus_celt

OPUS_MODE_SILK = 1000
OPUS_MODE_HYBRID = 1001
OPUS_MODE_CELT = 1002

-> opus_bytes(x)
  return x if x.is_a?(ByteArray)
  return ccall("w_string_bytes_view", x) ## u8[] if x.is_a?(String)
  r = u8[x.size]
  i = 0
  while i < x.size
    r[i] = x[i]
    i += 1
  r

-> opus_sub(data, off, len)
  r = u8[len < 1 ? 1 : len]
  i = 0
  while i < len
    r[i] = data[off + i]
    i += 1
  r

-> opus_toc_mode(toc)
  return OPUS_MODE_CELT if (toc & 128) != 0
  return OPUS_MODE_HYBRID if (toc & 96) == 96
  OPUS_MODE_SILK

# 1 NB, 2 MB, 3 WB, 4 SWB, 5 FB
-> opus_toc_bandwidth(toc)
  if (toc & 128) != 0
    bw = 2 + ((toc >> 5) & 3)
    bw = 1 if bw == 2
    return bw
  if (toc & 96) == 96
    return ((toc & 16) != 0) ? 5 : 4
  1 + ((toc >> 5) & 3)

# samples per frame at 48 kHz
-> opus_toc_frame_size(toc)
  if (toc & 128) != 0
    return (48000 << ((toc >> 3) & 3)) / 400
  if (toc & 96) == 96
    return ((toc & 8) != 0) ? 960 : 480
  a = (toc >> 3) & 3
  return 2880 if a == 3
  (48000 << a) / 100

# Splits an Opus packet (data[off, off+len)) into frames.
# Returns [toc, [[offset, size], ...], bytes_consumed] or raises MediaError.
# self_delimited: the multistream framing for all but the last stream.
-> opus_parse_packet(data, off0, len0, self_delimited)
  raise MediaError.new("opus: empty packet") if len0 < 1
  off = off0
  len = len0
  toc = data[off]
  off += 1
  len -= 1
  fs = opus_toc_frame_size(toc)
  sizes = []
  last_size = len
  count = 0
  cbr = false
  pad = 0
  code = toc & 3
  if code == 0
    count = 1
  elsif code == 1
    count = 2
    cbr = true
    if !self_delimited
      raise MediaError.new("opus: bad code 1 packet") if (len & 1) != 0
      last_size = len / 2
      sizes.push(last_size)
  elsif code == 2
    count = 2
    r = opus_parse_size(data, off, len)
    raise MediaError.new("opus: bad frame size") if r[0] < 0 || r[0] > len - r[1]
    len -= r[1]
    off += r[1]
    sizes.push(r[0])
    last_size = len - r[0]
  else
    raise MediaError.new("opus: bad code 3 packet") if len < 1
    ch = data[off]
    off += 1
    len -= 1
    count = ch & 63
    raise MediaError.new("opus: bad frame count") if count <= 0 || fs * count > 5760
    if (ch & 64) != 0
      while true
        raise MediaError.new("opus: bad padding") if len <= 0
        p = data[off]
        off += 1
        len -= 1
        tmp = (p == 255) ? 254 : p
        len -= tmp
        pad += tmp
        break if p != 255
    raise MediaError.new("opus: bad padding") if len < 0
    cbr = (ch & 128) == 0
    if !cbr
      last_size = len
      i = 0
      while i < count - 1
        r = opus_parse_size(data, off, len)
        len -= r[1]
        raise MediaError.new("opus: bad frame size") if r[0] < 0 || r[0] > len
        off += r[1]
        sizes.push(r[0])
        last_size -= r[1] + r[0]
        i += 1
      raise MediaError.new("opus: bad frame sizes") if last_size < 0
    elsif !self_delimited
      last_size = len / count
      raise MediaError.new("opus: bad CBR packet") if last_size * count != len
      i = 0
      while i < count - 1
        sizes.push(last_size)
        i += 1
  if self_delimited
    r = opus_parse_size(data, off, len)
    len -= r[1]
    raise MediaError.new("opus: bad frame size") if r[0] < 0 || r[0] > len
    off += r[1]
    if cbr
      raise MediaError.new("opus: bad CBR packet") if r[0] * count > len
      sizes = []
      i = 0
      while i < count
        sizes.push(r[0])
        i += 1
    else
      raise MediaError.new("opus: bad frame size") if r[1] + r[0] > last_size
      sizes.push(r[0])
  else
    raise MediaError.new("opus: frame too large") if last_size > 1275
    sizes.push(last_size)
  frames = []
  sizes.each ->(s)
    frames.push([off, s])
    off += s
  [toc, frames, off + pad - off0]

-> opus_parse_size(data, off, len)
  return [-1, -1] if len < 1
  b = data[off]
  return [b, 1] if b < 252
  return [-1, -1] if len < 2
  [4 * data[off + 1] + b, 2]

-> opus_smooth_fade(in1, o1, in2, o2, out, oo, overlap, cc, win) (f64[] i64 f64[] i64 f64[] i64 i64 i64 f64[]) i64
  c = 0 ## i64
  while c < cc
    i = 0 ## i64
    while i < overlap
      w = win[i] * win[i]
      out[oo + i * cc + c] = w * in2[o2 + i * cc + c] + ((~1.0 ## f64) - w) * in1[o1 + i * cc + c]
      i += 1
    c += 1
  0

-> opus_add_silk(pcm, po, silk, n) (f64[] i64 i64[] i64) i64
  s = ~0.000030517578125 ## f64
  i = 0 ## i64
  while i < n
    pcm[po + i] = pcm[po + i] + s * (silk[i] ## f64)
    i += 1
  0

-> opus_fill(a, off, n, v) (f64[] i64 i64 f64) i64
  i = 0 ## i64
  while i < n
    a[off + i] = v
    i += 1
  0

-> opus_copy(dst, doff, src, soff, n) (f64[] i64 f64[] i64 i64) i64
  i = 0 ## i64
  while i < n
    dst[doff + i] = src[soff + i]
    i += 1
  0

-> opus_scale(a, off, n, g) (f64[] i64 i64 f64) i64
  i = 0 ## i64
  while i < n
    a[off + i] = a[off + i] * g
    i += 1
  0

# opus_pcm_soft_clip (libopus float decoder); mem f64[channels]
-> opus_soft_clip(x, n, cc, mem) (f64[] i64 i64 f64[]) i64
  return 0 if cc < 1 || n < 1
  i = 0 ## i64
  while i < n * cc
    v = (x[i]) ## f64
    if v > (~2.0 ## f64)
      v = ~2.0 ## f64
    if v < (~-2.0 ## f64)
      v = ~-2.0 ## f64
    x[i] = v
    i += 1
  c = 0 ## i64
  while c < cc
    a = (mem[c]) ## f64
    i = 0
    while i < n
      v = (x[i * cc + c]) ## f64
      break if v * a >= (~0.0 ## f64)
      x[i * cc + c] = v + a * v * v
      i += 1
    curr = 0 ## i64
    x0 = x[c]
    while true
      i = curr
      while i < n
        v = (x[i * cc + c]) ## f64
        break if v > (~1.0 ## f64) || v < (~-1.0 ## f64)
        i += 1
      if i == n
        a = ~0.0 ## f64
        break
      peak_pos = i
      start = i
      iend = i
      maxval = (x[i * cc + c]) ## f64
      if maxval < (~0.0 ## f64)
        maxval = ((~0.0 ## f64) - maxval) ## f64
      while start > 0 && x[c + (start - 1) * cc] * x[c + i * cc] >= (~0.0 ## f64)
        start -= 1
      while iend < n && x[c + iend * cc] * x[c + i * cc] >= (~0.0 ## f64)
        cv = (x[c + iend * cc]) ## f64
        if cv < (~0.0 ## f64)
          cv = ((~0.0 ## f64) - cv) ## f64
        if cv > maxval
          maxval = (cv) ## f64
          peak_pos = iend
        iend += 1
      special = 0 ## i64
      special = 1 if start == 0 && x[i * cc + c] * x[c] >= (~0.0 ## f64)
      a = ((maxval - (~1.0 ## f64)) / (maxval * maxval)) ## f64
      a = (a + a * (~2.4e-7 ## f64)) ## f64
      if x[i * cc + c] > (~0.0 ## f64)
        a = ((~0.0 ## f64) - a) ## f64
      j = start
      while j < iend
        v = (x[j * cc + c]) ## f64
        x[j * cc + c] = v + a * v * v
        j += 1
      if special != 0 && peak_pos >= 2
        delta = ~0.0 ## f64
        offset = (x0 - x[c]) ## f64
        delta = (offset / (peak_pos ## f64)) ## f64
        j = curr
        while j < peak_pos
          offset = (offset - delta) ## f64
          v = (x[j * cc + c] + offset) ## f64
          if v > (~1.0 ## f64)
            v = ~1.0 ## f64
          if v < (~-1.0 ## f64)
            v = ~-1.0 ## f64
          x[j * cc + c] = v
          j += 1
      curr = iend
      break if curr == n
    mem[c] = a
    c += 1
  0

# One elementary Opus stream (1 or 2 channels): opus_decoder.c.
+ OpusStreamDec
  rw :channels, :range_final, :last_duration

  -> new(@channels)
    @celt = OpusCeltDec.new(@channels)
    @silk = OpusSilkDec.new(@channels)
    @softclip = f64[2]
    # range-decoder state of a frame with data (decode_frame only re-enters itself for lost
    # frames, which get their own)
    @st_main = i64[EC_N]
    reset()

  -> reset
    @celt.reset()
    @silk.reset()
    @prev_mode = 0
    @prev_redundancy = 0
    @mode = 0
    @bandwidth = 0
    @frame_size = 960
    @stream_channels = @channels
    @range_final = 0
    @last_duration = 960
    @softclip[0] = ~0.0 ## f64
    @softclip[1] = ~0.0 ## f64

  # opus_decode_frame. data: u8[] holding just this frame (or nil for loss).
  -> decode_frame(data, len0, pcm, po, frame_size0, decode_fec)
    cc = @channels
    len = len0
    frame_size = frame_size0 < 2880 ? frame_size0 : 2880
    if len <= 1
      data = nil
      frame_size = @frame_size if @frame_size < frame_size
    audiosize = 0
    mode = 0
    bandwidth = 0
    st = data != nil && len > 1 ? @st_main : i64[EC_N]
    if data != nil
      audiosize = @frame_size
      mode = @mode
      bandwidth = @bandwidth
      ec_dec_init(st, data, len)
    else
      audiosize = frame_size
      mode = (@prev_redundancy != 0) ? OPUS_MODE_CELT : @prev_mode
      bandwidth = 0
      if mode == 0
        opus_fill(pcm, po * cc, audiosize * cc, ~0.0 ## f64)
        return audiosize
      if audiosize > 960
        rem = audiosize
        p = po
        while rem > 0
          ret = decode_frame(nil, 0, pcm, p, [rem, 960].min, 0)
          p += ret
          rem -= ret
        return frame_size
      elsif audiosize < 960
        if audiosize > 480
          audiosize = 480
        elsif mode != OPUS_MODE_SILK && audiosize > 240 && audiosize < 480
          audiosize = 240
    transition = 0
    pcm_transition = nil
    if data != nil && @prev_mode > 0 && ((mode == OPUS_MODE_CELT && @prev_mode != OPUS_MODE_CELT && @prev_redundancy == 0) || (mode != OPUS_MODE_CELT && @prev_mode == OPUS_MODE_CELT))
      transition = 1
    if transition != 0 && mode == OPUS_MODE_CELT
      pcm_transition = f64[240 * cc]
      decode_frame(nil, 0, pcm_transition, 0, [240, audiosize].min, 0)
    raise MediaError.new("opus: frame too large") if audiosize > frame_size
    frame_size = audiosize
    pcm_silk = nil
    if mode != OPUS_MODE_CELT
      pcm_silk = i64[[480, frame_size].max * cc]
      @silk.reset() if @prev_mode == OPUS_MODE_CELT
      payload_ms = [10, 1000 * audiosize / 48000].max
      internal_rate = 16000
      if data != nil && mode == OPUS_MODE_SILK
        internal_rate = 8000 if bandwidth == 1
        internal_rate = 12000 if bandwidth == 2
      if data != nil
        @silk_rate = internal_rate
        @silk_channels = @stream_channels
      lost_flag = (data == nil) ? 1 : 2 * decode_fec
      decoded = 0
      while decoded < frame_size
        first = (decoded == 0) ? 1 : 0
        nsamp = 0
        begin
          nsamp = @silk.decode(st, data, lost_flag, first, payload_ms, @silk_channels, @silk_rate, pcm_silk, decoded)
        rescue e
          raise e if lost_flag == 0
          nsamp = frame_size - decoded
          i = decoded * cc
          while i < frame_size * cc
            pcm_silk[i] = 0
            i += 1
        decoded += nsamp
    start_band = 0
    redundancy = 0
    redundancy_bytes = 0
    celt_to_silk = 0
    if decode_fec == 0 && mode != OPUS_MODE_CELT && data != nil && ec_tell(st) + 17 + ((mode == OPUS_MODE_HYBRID) ? 20 : 0) <= 8 * len
      if mode == OPUS_MODE_HYBRID
        redundancy = ec_dec_bit_logp(st, data, 12)
      else
        redundancy = 1
      if redundancy != 0
        celt_to_silk = ec_dec_bit_logp(st, data, 1)
        if mode == OPUS_MODE_HYBRID
          redundancy_bytes = ec_dec_uint(st, data, 256) + 2
        else
          redundancy_bytes = len - ((ec_tell(st) + 7) >> 3)
        len -= redundancy_bytes
        if len * 8 < ec_tell(st)
          len = 0
          redundancy_bytes = 0
          redundancy = 0
        st[9] = st[9] - redundancy_bytes
    start_band = 17 if mode != OPUS_MODE_CELT
    transition = 0 if redundancy != 0
    if transition != 0 && mode != OPUS_MODE_CELT
      pcm_transition = f64[240 * cc]
      decode_frame(nil, 0, pcm_transition, 0, [240, audiosize].min, 0)
    if bandwidth != 0
      endband = 21
      endband = 13 if bandwidth == 1
      endband = 17 if bandwidth == 2 || bandwidth == 3
      endband = 19 if bandwidth == 4
      @celt.iend = endband
    @celt.stream_channels = @stream_channels
    redundant_audio = nil
    redundant_rng = 0
    red_data = nil
    if redundancy != 0
      redundant_audio = f64[240 * cc]
      red_data = opus_sub(data, len, redundancy_bytes)
    if redundancy != 0 && celt_to_silk != 0
      @celt.start = 0
      @celt.decode(red_data, redundancy_bytes, redundant_audio, 0, 240, nil)
      redundant_rng = @celt.rng
    @celt.start = start_band
    if mode != OPUS_MODE_SILK
      celt_frame_size = [960, frame_size].min
      @celt.reset() if mode != @prev_mode && @prev_mode > 0 && @prev_redundancy == 0
      @celt.decode((decode_fec != 0) ? nil : data, len, pcm, po, celt_frame_size, st)
    else
      opus_fill(pcm, po * cc, frame_size * cc, ~0.0 ## f64)
      if @prev_mode == OPUS_MODE_HYBRID && !(redundancy != 0 && celt_to_silk != 0 && @prev_redundancy != 0)
        @celt.start = 0
        sil = u8[2]
        sil[0] = 255
        sil[1] = 255
        @celt.decode(sil, 2, pcm, po, 120, nil)
    if mode != OPUS_MODE_CELT
      opus_add_silk(pcm, po * cc, pcm_silk, frame_size * cc)
    if redundancy != 0 && celt_to_silk == 0
      @celt.reset()
      @celt.start = 0
      @celt.decode(red_data, redundancy_bytes, redundant_audio, 0, 240, nil)
      redundant_rng = @celt.rng
      o = (po + frame_size - 120) * cc
      opus_smooth_fade(pcm, o, redundant_audio, 120 * cc, pcm, o, 120, cc, CELT_WINDOW)
    if redundancy != 0 && celt_to_silk != 0 && (@prev_mode != OPUS_MODE_SILK || @prev_redundancy != 0)
      opus_copy(pcm, po * cc, redundant_audio, 0, 120 * cc)
      o = (po + 120) * cc
      opus_smooth_fade(redundant_audio, 120 * cc, pcm, o, pcm, o, 120, cc, CELT_WINDOW)
    if transition != 0
      if audiosize >= 240
        opus_copy(pcm, po * cc, pcm_transition, 0, 120 * cc)
        o = (po + 120) * cc
        opus_smooth_fade(pcm_transition, 120 * cc, pcm, o, pcm, o, 120, cc, CELT_WINDOW)
      else
        opus_smooth_fade(pcm_transition, 0, pcm, po * cc, pcm, po * cc, 120, cc, CELT_WINDOW)
    if len <= 1
      @range_final = 0
    else
      @range_final = st[0] ^ redundant_rng
    @prev_mode = mode
    @prev_redundancy = (redundancy != 0 && celt_to_silk == 0) ? 1 : 0
    audiosize

  # opus_decode_native over packet bytes data[off, off+len). Returns
  # [samples_per_channel, bytes_consumed]. Writes into pcm at frame po.
  -> decode_packet(data, off, len, pcm, po, max_frames, self_delimited)
    if data == nil || len == 0
      n = 0
      while n < max_frames
        n += decode_frame(nil, 0, pcm, po + n, max_frames - n, 0)
      @last_duration = n
      return [n, 0]
    parsed = opus_parse_packet(data, off, len, self_delimited)
    toc = parsed[0]
    frames = parsed[1]
    fsz = opus_toc_frame_size(toc)
    raise MediaError.new("opus: packet too long") if frames.size * fsz > max_frames
    @mode = opus_toc_mode(toc)
    @bandwidth = opus_toc_bandwidth(toc)
    @frame_size = fsz
    @stream_channels = ((toc & 4) != 0) ? 2 : 1
    n = 0
    frames.each ->(f)
      fd = opus_sub(data, f[0], f[1])
      n += decode_frame(fd, f[1], pcm, po + n, max_frames - n, 0)
    @last_duration = n
    [n, parsed[2]]

  -> soft_clip(pcm, n)
    opus_soft_clip(pcm, n, @channels, @softclip)

# The codec object registered with mediacore.
+ OpusDec
  rw :channels, :sample_rate, :pre_skip, :gain_db, :soft_clip_on
  ro :streams, :last_ranges, :errors, :last_error

  -> new(cfg)
    @reuse = cfg.is_a?(CodecConfig) && cfg.reuse_output == true
    @obuf = nil
    @sample_rate = 48000
    @errors = 0
    @last_error = nil
    @soft_clip_on = true
    @gain_db = ~0.0
    @pre_skip = 0
    extra = cfg == nil ? nil : cfg.extra
    ch = 0
    ch = cfg.channels if cfg != nil && cfg.channels != nil
    family = 0
    nstreams = 1
    ncoupled = 0
    mapping = nil
    if extra != nil
      h = opus_bytes(extra)
      raise MediaError.new("opus: bad OpusHead") if h.size < 19 || h[0] != 79 || h[1] != 112 || h[4] != 72
      raise MediaError.new("opus: unsupported OpusHead version") if (h[8] >> 4) != 0
      ch = h[9]
      @pre_skip = h[10] | (h[11] << 8)
      g = h[16] | (h[17] << 8)
      g -= 65536 if g >= 32768
      @gain_db = (g ## f64) / ~256.0
      family = h[18]
      raise MediaError.new("opus: unsupported channel mapping family 3") if family == 3
      if family != 0
        raise MediaError.new("opus: bad OpusHead mapping") if h.size < 21 + ch
        nstreams = h[19]
        ncoupled = h[20]
        mapping = []
        i = 0
        while i < ch
          mapping.push(h[21 + i])
          i += 1
    ch = 2 if ch <= 0
    ch = 2 if extra == nil && ch > 2
    if family == 0
      raise MediaError.new("opus: bad channel count") if ch > 2
      nstreams = 1
      ncoupled = ch - 1
      mapping = (ch == 2) ? [0, 1] : [0]
    raise MediaError.new("opus: bad stream counts") if nstreams < 1 || ncoupled > nstreams || nstreams + ncoupled > 255
    @channels = ch
    @family = family
    @nstreams = nstreams
    @ncoupled = ncoupled
    @mapping = mapping
    @streams = []
    i = 0
    while i < nstreams
      @streams.push(OpusStreamDec.new((i < ncoupled) ? 2 : 1))
      i += 1
    @order = opus_wave_order(ch, family)
    @last_ranges = []
    @pcm64 = nil
    @last_duration = 960
    @softclip = f64[[ch, 1].max]

  -> reset
    @streams.each ->(s)
      s.reset()
    i = 0
    while i < @softclip.size
      @softclip[i] = ~0.0 ## f64
      i += 1

  -> flush
    nil

  # Decodes one packet into interleaved f64 (frames x channels) and returns
  # [samples, frames]. data nil / empty = packet loss (frames_hint samples).
  -> decode_bytes(data, frames_hint)
    if data == nil || data.size == 0
      return decode_lost(frames_hint)
    toc = data[0]
    fsz = opus_toc_frame_size(toc)
    count = opus_frame_count(data)
    total = fsz * count
    raise MediaError.new("opus: bad packet") if total <= 0 || total > 5760
    cc = @channels
    if @nstreams == 1 && @family == 0
      # one stream: into the reused PCM buffer (decode copies it out before the next packet)
      @pcm64 = f64[5760 * cc] if @pcm64 == nil
      out = @pcm64 ## f64[]
      opus_fill(out, 0, total * cc, ~0.0 ## f64)
      s = @streams[0]
      r = s.decode_packet(data, 0, data.size, out, 0, total, false)
      n = r[0]
      @last_ranges = [s.range_final] if @last_ranges.size != 1
      @last_ranges[0] = s.range_final
      finish(out, n, s)
      @last_duration = n
      return [out, n]
    out = f64[total * cc]
    off = 0
    sbufs = []
    @last_ranges = []
    si = 0
    while si < @nstreams
      s = @streams[si]
      sb = f64[total * s.channels]
      last = si == @nstreams - 1
      raise MediaError.new("opus: truncated multistream packet") if off >= data.size
      r = s.decode_packet(data, off, data.size - off, sb, 0, total, !last)
      raise MediaError.new("opus: stream duration mismatch") if r[0] != total
      off += r[1]
      sbufs.push(sb)
      @last_ranges.push(s.range_final)
      si += 1
    mix_streams(out, sbufs, total)
    finish(out, total, nil)
    @last_duration = total
    [out, total]

  -> decode_lost(frames_hint)
    total = frames_hint
    total = @last_duration if total <= 0
    total = 5760 if total > 5760
    total = (total / 120) * 120
    total = 120 if total <= 0
    cc = @channels
    out = f64[total * cc]
    sbufs = []
    @streams.each ->(s)
      sb = f64[total * s.channels]
      s.decode_packet(nil, 0, 0, sb, 0, total, false)
      sbufs.push(sb)
    mix_streams(out, sbufs, total)
    finish(out, total, nil)
    [out, total]

  -> mix_streams(out, sbufs, total)
    cc = @channels
    o = 0
    while o < cc
      src = @order[o]
      m = @mapping[src]
      if m == 255
        opus_set_chan(out, o, cc, total, nil, 0, 1)
      elsif m < 2 * @ncoupled
        opus_set_chan(out, o, cc, total, sbufs[m >> 1], m & 1, 2)
      else
        opus_set_chan(out, o, cc, total, sbufs[m - @ncoupled], 0, 1)
      o += 1

  -> finish(out, n, s)
    if @gain_db != ~0.0
      g = Math.exp(~0.11512925464970229 * @gain_db) ## f64
      opus_scale(out, 0, n * @channels, g)
    if @soft_clip_on
      opus_soft_clip(out, n, @channels, @softclip)

  -> decode(sample)
    data = sample == nil ? nil : sample.data
    hint = 0
    if sample != nil && sample.duration != nil
      hint = (sample.duration * ~48000.0 + ~0.5).to_i
    data = opus_bytes(data) if data != nil
    r = nil
    begin
      r = decode_bytes(data, hint)
    rescue e
      # Corrupt packet: conceal it (PLC) instead of failing the stream.
      @errors += 1
      @last_error = e.to_s
      begin
        r = decode_lost(hint)
      rescue e2
        n0 = (hint > 0 && hint <= 5760) ? hint : 960
        r = [f64[n0 * @channels], n0]
    pts = sample == nil ? ~0.0 : sample.pts
    n = r[1] * @channels
    @obuf = audio_out(@obuf, @reuse, n)
    out = @obuf ## f32[]
    opus_to_f32(r[0], out, n)
    blk = AudioBlock.new(out, r[1], @channels, 48000, pts)
    blk.owned = !@reuse
    blk

-> opus_to_f32(a, b, n) (f64[] f32[] i64) i64
  i = 0 ## i64
  while i < n
    b[i] = a[i] ## f32
    i += 1
  0

-> opus_set_chan(out, o, cc, n, src, sc, scc)
  if src == nil
    opus_zero_chan(out, o, cc, n)
  else
    opus_copy_chan(out, o, cc, n, src, sc, scc)

-> opus_zero_chan(out, o, cc, n) (f64[] i64 i64 i64) i64
  i = 0 ## i64
  while i < n
    out[i * cc + o] = ~0.0 ## f64
    i += 1
  0

-> opus_copy_chan(out, o, cc, n, src, sc, scc) (f64[] i64 i64 i64 f64[] i64 i64) i64
  i = 0 ## i64
  while i < n
    out[i * cc + o] = src[i * scc + sc]
    i += 1
  0

# Number of frames in a packet (from the TOC / code-3 count byte).
-> opus_frame_count(data)
  code = data[0] & 3
  return 1 if code == 0
  return 2 if code == 1 || code == 2
  return 0 if data.size < 2
  data[1] & 63

# For output channel o (WAVE order), the index into the Opus/Vorbis order.
-> opus_wave_order(ch, family)
  if family == 1
    return [0, 2, 1] if ch == 3
    return [0, 2, 1, 3, 4] if ch == 5
    return [0, 2, 1, 5, 3, 4] if ch == 6
    return [0, 2, 1, 6, 5, 3, 4] if ch == 7
    return [0, 2, 1, 7, 5, 6, 3, 4] if ch == 8
  r = []
  i = 0
  while i < ch
    r.push(i)
    i += 1
  r

acodec_register("opus", ->(cfg) OpusDec.new(cfg))
