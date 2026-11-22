# core/codec/container/demux_aiff — AIFF / AIFF-C and Apple CAF audio containers.
#
# AIFF: COMM + SSND, big-endian PCM 8/16/24/32-bit; AIFF-C compression
# NONE/twos (big-endian), sowt (little-endian), fl32/FL32, fl64/FL64.
# Streams as it arrives (like WAV).
# CAF: desc / kuki / pakt / data chunks; formats lpcm (integer or float,
# either byte order), alac (ALACSpecificConfig cookie), aac (esds cookie),
# ac-3, ec-3, .mp3 and flac; packets from the packet table (variable-size)
# or fixed bytesPerPacket. Parsed once the whole file has arrived.

use core/codec/media
use demux

+ AiffDemuxer < Demuxer
  -> new(k)
    init_demuxer(k)
    @pos = 12
    @data_start = nil
    @data_end = nil
    @block = 0
    @rate = 0
    @emitted = 0
    @done = false

  -> parse
    return nil if @error != nil || @kind == :caf
    begin
      parse_aiff()
    rescue e
      fail("aiff: " + e.to_s)
    nil

  -> finish
    if @kind == :caf
      return nil if @done
      @done = true
      begin
        parse_caf()
      rescue e
        fail("caf: " + e.to_s)
      return nil
    parse

  -> parse_aiff
    if @data_start == nil
      return nil if !@buf.has?(0, 12)
      aifc = dm_fourcc(@buf.data, @buf.off(8)) == "AIFC"
      while @data_start == nil && @buf.has?(@pos, 8)
        id = dm_fourcc(@buf.data, @buf.off(@pos))
        sz = @buf.be32(@pos + 4)
        if id == "COMM"
          return nil if !@buf.has?(@pos + 8, sz)
          o = @pos + 8
          ch = @buf.be16(o)
          bits = @buf.be16(o + 6)
          @rate = aiff_ext80(@buf.data, @buf.off(o + 8)).to_i
          ct = "NONE"
          ct = dm_fourcc(@buf.data, @buf.off(o + 18)) if aifc && sz >= 22
          be = true
          fl = false
          if ct == "sowt"
            be = false
          elsif ct == "fl32" || ct == "FL32"
            fl = true
            bits = 32
          elsif ct == "fl64" || ct == "FL64"
            fl = true
            bits = 64
          elsif ct != "NONE" && ct != "twos" && ct != "raw "
            fail("unsupported AIFF-C compression " + ct)
            return nil
          bits = ((bits + 7) / 8) * 8
          cfg = CodecConfig.new("pcm ", pcm_extra(bits, fl, be))
          cfg.sample_rate = @rate
          cfg.channels = ch
          cfg.codec_string = "1"
          @tracks.push(MediaTrack.new(1, :audio, cfg))
          @block = ch * bits / 8
          # 8-bit AIFF is signed; PcmDec's 8-bit path is unsigned WAV
          @signed8 = bits == 8 && ct != "raw "
          @frames_total = @buf.be32(o + 2)
        elsif id == "SSND"
          return nil if !@buf.has?(@pos + 8, 8)
          off = @buf.be32(@pos + 8)
          @data_start = @pos + 16 + off
          @data_end = @pos + 8 + sz
          @duration = @rate > 0 ? @frames_total.to_f / @rate.to_f : nil
          @ready = @tracks.size > 0
          @pos = @data_start
          break
        @pos += 8 + sz + (sz & 1)
      return nil if @data_start == nil
    return nil if @block == 0
    chunk = 4096 * @block
    while true
      lim = @buf.limit
      lim = @data_end if @data_end != nil && @data_end < lim
      n = lim - @pos
      return nil if n < chunk && lim < @data_end
      n = chunk if n > chunk
      n = n - n % @block
      return nil if n <= 0
      frames = n / @block
      t = @emitted.to_f / @rate.to_f
      d = @buf.slice(@pos, n)
      aiff_flip8(d) if @signed8
      emit(1, MediaSample.new(d, t, t, frames.to_f / @rate.to_f, true))
      @emitted += frames
      @pos += n
      @buf.discard(@pos)
    nil

  -> seek_offset(t)
    return nil if @data_start == nil || @kind == :caf
    @data_start + (t * @rate.to_f).to_i * @block

  -> restart(off)
    @buf.reset(off)
    if @data_start != nil && @kind == :aiff
      @pos = off
      @emitted = (off - @data_start) / @block
    nil

  # ---- CAF ----

  -> parse_caf
    b = @buf.slice(@buf.base, @buf.len)
    n = b.size
    p = 8
    desc = nil
    kuki = nil
    pakt = nil
    data = nil
    while p + 12 <= n
      id = dm_fourcc(b, p)
      sz = dm_be64(b, p + 4)
      body = p + 12
      sz = n - body if sz < 0 || sz > n - body || (id == "data" && sz == -1)
      if id == "desc"
        desc = body
      elsif id == "kuki"
        kuki = [body, sz]
      elsif id == "pakt"
        pakt = [body, sz]
      elsif id == "data"
        data = [body + 4, sz - 4]
      p = body + sz
    raise "no desc/data chunk" if desc == nil || data == nil
    rate = dm_f64_bits(dm_be64(b, desc)).to_i
    fmt = dm_fourcc(b, desc + 8)
    flags = dm_be32(b, desc + 12)
    bpp = dm_be32(b, desc + 16)
    fpp = dm_be32(b, desc + 20)
    ch = dm_be32(b, desc + 24)
    bits = dm_be32(b, desc + 28)
    cfg = nil
    if fmt == "lpcm"
      cfg = CodecConfig.new("pcm ", pcm_extra(bits, (flags & 1) != 0, (flags & 2) == 0))
      cfg.codec_string = "1"
    elsif fmt == "alac"
      cfg = CodecConfig.new("alac", kuki == nil ? nil : caf_alac_cookie(b, kuki[0], kuki[1]))
      cfg.codec_string = "alac"
    elsif fmt == "aac "
      asc = kuki == nil ? nil : caf_esds_asc(b, kuki[0], kuki[1])
      cfg = CodecConfig.new("mp4a", asc)
      cfg.codec_string = mp4a_codec_string("mp4a", asc)
    elsif fmt == "ac-3" || fmt == "ec-3"
      cfg = CodecConfig.new(fmt)
      cfg.codec_string = fmt
    elsif fmt == ".mp3"
      cfg = CodecConfig.new("mp3 ")
      cfg.codec_string = "mp3"
    elsif fmt == "flac" && kuki != nil
      # the cookie holds the fLaC metadata blocks; STREAMINFO body follows its 4-byte header
      k = kuki[0]
      k += 4 if kuki[1] >= 42 && dm_fourcc(b, k) == "fLaC"
      cfg = CodecConfig.new("flac", dm_slice(b, k + 4, 34))
      cfg.codec_string = "flac"
    else
      raise "unsupported CAF format " + fmt
    cfg.sample_rate = rate
    cfg.channels = ch
    cfg.timescale = rate
    @tracks.push(MediaTrack.new(1, :audio, cfg))
    @rate = rate
    # packets
    t = ~0.0
    pos = data[0]
    dend = data[0] + data[1]
    dend = n if dend > n
    if bpp > 0 && fpp > 0
      # constant packet size (PCM: group into ~4096-frame samples)
      per = fpp
      group = 1
      group = (4096 / fpp) if fpp < 4096
      group = 1 if group < 1
      step = bpp * group
      while pos + bpp <= dend
        m = step
        m = dend - pos if pos + m > dend
        m = m - m % bpp
        frames = (m / bpp) * fpp
        emit(1, MediaSample.new(dm_slice(b, pos, m), t, t, frames.to_f / rate.to_f, true))
        t += frames.to_f / rate.to_f
        pos += m
    else
      raise "variable-size packets without a packet table" if pakt == nil
      np = dm_be64(b, pakt[0])
      prime = dm_be32(b, pakt[0] + 16)
      q = pakt[0] + 24
      qe = pakt[0] + pakt[1]
      t = ~0.0 - prime.to_f / rate.to_f
      i = 0
      while i < np && q < qe
        r = caf_varint(b, q)
        psz = bpp > 0 ? bpp : r[0]
        q = bpp > 0 ? q : r[1]
        fr = fpp
        if fpp == 0
          r2 = caf_varint(b, q)
          fr = r2[0]
          q = r2[1]
        break if pos + psz > dend
        d = fr.to_f / rate.to_f
        emit(1, MediaSample.new(dm_slice(b, pos, psz), t, t, d, true))
        t += d
        pos += psz
        i += 1
    @duration = t > ~0.0 ? t : nil
    @ready = true
    nil

-> caf_varint(b, q)
  v = 0
  while q < b.size
    c = b[q]
    q += 1
    v = (v << 7) | (c & 127)
    break if (c & 128) == 0
  [v, q]

# ALAC cookie: the 24-byte ALACSpecificConfig, possibly inside 'frma' + 'alac' atoms.
-> caf_alac_cookie(b, off, len)
  p = off
  e = off + len
  while p + 8 <= e
    sz = dm_be32(b, p)
    ty = dm_fourcc(b, p + 4)
    if ty == "alac" && sz >= 36
      return dm_slice(b, p + 12, 24)
    if ty == "frma"
      p += sz
      next
    break
  dm_slice(b, off, len < 24 ? len : 24)

# AAC cookie: an esds-style descriptor chain; return the DecoderSpecificInfo.
-> caf_esds_asc(b, off, len)
  p = off
  e = off + len
  while p < e
    tag = b[p]
    p += 1
    l = 0
    k = 0
    more = true
    while more && k < 4 && p < e
      c = b[p]
      p += 1
      l = (l << 7) | (c & 127)
      more = (c & 128) != 0
      k += 1
    if tag == 3
      fl = b[p + 2]
      p += 3
      p += 2 if (fl & 0x80) != 0
      p += 1 + b[p] if (fl & 0x40) != 0
      p += 2 if (fl & 0x20) != 0
    elsif tag == 4
      p += 13
    elsif tag == 5
      return dm_slice(b, p, l)
    else
      p += l
  nil

# IEEE 754 80-bit extended (AIFF sample rate).
-> aiff_ext80(b, o)
  e = ((b[o] & 127) << 8) | b[o + 1]
  m = dm_be64(b, o + 2)
  return ~0.0 if e == 0 && m == 0
  # use the top 53 bits of the mantissa
  hi = (m >> 11) & 0x1FFFFFFFFFFFFF
  v = hi.to_f * (~2.0 ** (e - 16383 - 52))
  (b[o] & 128) != 0 ? ~0.0 - v : v

-> aiff_flip8(d) (u8[]) i64
  i = 0 ## i64
  while i < d.size
    d[i] = d[i] ^ 128
    i += 1
  0
