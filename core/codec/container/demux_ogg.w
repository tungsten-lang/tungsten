# core/codec/container/demux_ogg — Ogg (RFC 3533) with the Opus (RFC 7845), Vorbis, Theora
# and FLAC mappings.
#
# Pages are checked (capture pattern and CRC-32), packets reassembled per
# logical stream (continued packets across pages). The first packets of each
# stream identify the codec and become CodecConfig.extra; later packets are
# samples. Timestamps come from granule positions: a page's last completed
# packet ends at its granule, earlier ones are counted back by their durations
# (Opus TOC; Theora one frame each; Vorbis/FLAC spread over the page).
# Seeking is by bisection over byte offsets (seek_offset gives a guess the
# loader refines by restarting and looking at the first granule).

use core/codec/media
use demux

OGG_CRC = []

-> ogg_crc_table
  if OGG_CRC.size == 0
    i = 0
    while i < 256
      r = i << 24
      k = 0
      while k < 8
        r = (r & 0x80000000) != 0 ? ((r << 1) ^ 0x04C11DB7) & 0xFFFFFFFF : (r << 1) & 0xFFFFFFFF
        k += 1
      OGG_CRC.push(r)
      i += 1
  OGG_CRC

-> ogg_crc_run(b, s, n, tab) (u8[] i64 i64 i64[]) i64
  crc = 0 ## i64
  i = 0 ## i64
  while i < n
    v = b[s + i]
    # bytes 22..25 (the CRC field) count as zero
    v = 0 if i >= 22 && i < 26
    crc = ((crc << 8) & 0xFFFFFFFF) ^ tab[((crc >> 24) ^ v) & 255]
    i += 1
  crc

OGG_TAB = [nil]

-> ogg_tab
  if OGG_TAB[0] == nil
    t = i64[256]
    ogg_crc_table().each_with_index ->(v, i) t[i] = v
    OGG_TAB[0] = t
  OGG_TAB[0]

# Samples (48 kHz) in an Opus packet, from its TOC (RFC 6716 §3.1).
-> opus_packet_samples(b)
  return 0 if b == nil || b.size < 1
  toc = b[0]
  cfg = toc >> 3
  fs = 0
  if cfg < 12
    fs = [480, 960, 1920, 2880][cfg & 3]
  elsif cfg < 16
    fs = (cfg & 1) == 0 ? 480 : 960
  else
    fs = [120, 240, 480, 960][cfg & 3]
  c = toc & 3
  n = 1
  n = 2 if c == 1 || c == 2
  if c == 3
    return 0 if b.size < 2
    n = b[1] & 63
  fs * n

+ OggStream
  rw :serial, :codec, :headers, :need, :track, :rate, :partial, :queue, :granule, :shift, :fps, :last_end, :pre_skip

  -> new(@serial)
    @codec = nil
    @headers = []
    @need = 1
    @track = nil
    @rate = 48000
    @partial = nil
    @queue = []
    @granule = -1
    @shift = 0
    @fps = ~25.0
    @last_end = nil
    @pre_skip = 0

+ OggDemuxer < Demuxer
  -> new
    init_demuxer(:ogg)
    @pos = 0
    @streams = {}
    @order = []
    @total = nil

  -> restart(off)
    @buf.reset(off)
    @pos = off
    @streams.each ->(k, st)
      st.partial = nil
      st.queue = []
      st.last_end = nil
    @resync = true
    nil

  -> parse
    return nil if @error != nil
    begin
      parse_pages()
    rescue e
      fail("ogg: " + e.to_s)
    @buf.discard(@pos)
    nil

  -> parse_pages
    tab = ogg_tab()
    while @buf.has?(@pos, 27)
      if @buf.be32(@pos) != 0x4F676753
        # lost sync (or after a seek): scan for the next capture pattern
        p = @pos + 1
        found = false
        while !found && @buf.has?(p, 4)
          if @buf.u8(p) == 0x4F && @buf.be32(p) == 0x4F676753
            found = true
          else
            p += 1
        @pos = found ? p : (@buf.limit - 3 > @pos ? @buf.limit - 3 : @pos)
        return nil if !found
      nseg = @buf.u8(@pos + 26)
      return nil if !@buf.has?(@pos, 27 + nseg)
      plen = 0
      i = 0
      while i < nseg
        plen += @buf.u8(@pos + 27 + i)
        i += 1
      total = 27 + nseg + plen
      return nil if !@buf.has?(@pos, total)
      crc = dm_le32(@buf.data, @buf.off(@pos) + 22)
      if ogg_crc_run(@buf.data, @buf.off(@pos), total, tab) != crc
        @pos += 1
        next
      page(@pos, nseg)
      @pos += total
    nil

  -> page(p, nseg)
    htype = @buf.u8(p + 5)
    gran = dm_le64(@buf.data, @buf.off(p) + 6)
    gran = -1 if gran == 0xFFFFFFFFFFFFFFFF || gran < -1
    serial = dm_le32(@buf.data, @buf.off(p) + 14)
    st = @streams[serial]
    if st == nil
      return nil if (htype & 2) == 0 && @ready
      st = OggStream.new(serial)
      @streams[serial] = st
      @order.push(serial)
    if (htype & 1) == 0 && st.partial != nil && @resync == true
      st.partial = nil
    data = p + 27 + nseg
    completed = []
    i = 0
    cur = nil
    cur = st.partial if (htype & 1) != 0
    st.partial = nil
    while i < nseg
      l = @buf.u8(p + 27 + i)
      piece = @buf.slice(data, l)
      data += l
      if cur == nil
        cur = piece
      else
        nb = ByteArray.new(cur.size + l)
        dm_copy(nb, 0, cur, 0, cur.size)
        dm_copy(nb, cur.size, piece, 0, l)
        cur = nb
      if l < 255
        completed.push(cur)
        cur = nil
      i += 1
    st.partial = cur
    @resync = false
    completed.each ->(pk) packet(st, pk)
    page_end(st, gran) if gran >= 0
    nil

  -> packet(st, pk)
    if st.codec == nil
      ident(st, pk)
      return nil
    if st.headers.size < st.need
      st.headers.push(pk)
      finish_headers(st) if st.headers.size == st.need
      return nil
    return nil if st.track == nil
    st.queue.push(pk)
    nil

  -> ident(st, pk)
    n = pk.size
    if n >= 19 && dm_ascii(pk, 0, 8) == "OpusHead"
      st.codec = "opus"
      st.rate = 48000
      st.pre_skip = dm_le16(pk, 10)
      st.headers = [pk]
      st.need = 2
    elsif n >= 30 && pk[0] == 1 && dm_ascii(pk, 1, 6) == "vorbis"
      st.codec = "vorb"
      st.rate = dm_le32(pk, 12)
      st.headers = [pk]
      st.need = 3
    elsif n >= 42 && pk[0] == 0x80 && dm_ascii(pk, 1, 6) == "theora"
      st.codec = "theo"
      fnum = dm_be32(pk, 22)
      fd = dm_be32(pk, 26)
      st.fps = fd > 0 ? fnum.to_f / fd.to_f : ~25.0
      st.shift = ((pk[40] & 3) << 3) | (pk[41] >> 5)
      st.headers = [pk]
      st.need = 3
    elsif n >= 51 && pk[0] == 0x7F && dm_ascii(pk, 1, 4) == "FLAC"
      st.codec = "flac"
      nh = dm_be16(pk, 7)
      st.headers = [pk]
      st.need = 1 + nh
      st.rate = (dm_be24(pk, 27) >> 4)
    else
      st.codec = "?"
      st.need = 1 << 40
    finish_headers(st) if st.headers.size >= st.need
    nil

  -> finish_headers(st)
    cfg = nil
    h = st.headers
    if st.codec == "opus"
      cfg = CodecConfig.new("opus", h[0])
      cfg.sample_rate = 48000
      cfg.channels = h[0][9]
    elsif st.codec == "vorb"
      cfg = CodecConfig.new("vorb", [h[0], h[1], h[2]])
      cfg.sample_rate = st.rate
      cfg.channels = h[0][11]
    elsif st.codec == "theo"
      cfg = CodecConfig.new("theo", [h[0], h[1], h[2]])
      cfg.width = dm_be24(h[0], 14)
      cfg.height = dm_be24(h[0], 17)
    elsif st.codec == "flac"
      cfg = CodecConfig.new("flac", dm_slice(h[0], 17, 34))
      cfg.sample_rate = st.rate
      cfg.channels = ((h[0][29] >> 1) & 7) + 1
    return nil if cfg == nil
    cfg.codec_string = st.codec == "vorb" ? "vorbis" : (st.codec == "theo" ? "theora" : st.codec)
    t = MediaTrack.new(st.serial, st.codec == "theo" ? :video : :audio, cfg)
    st.track = t
    st.last_end = ~0.0 if st.codec == "vorb" || st.codec == "flac"
    @tracks.push(t)
    # ready once every stream that began on the first pages has its headers
    all = true
    @order.each ->(sr)
      s2 = @streams[sr]
      all = false if s2.codec != "?" && s2.track == nil
    @ready = true if all
    nil

  -> to_time(st, g)
    if st.codec == "theo"
      fr = (g >> st.shift) + (g & ((1 << st.shift) - 1))
      return fr.to_f / st.fps
    if st.codec == "opus"
      return (g - st.pre_skip).to_f / ~48000.0
    g.to_f / st.rate.to_f

  # Every queued packet of this page ends by granule g: assign timestamps.
  -> page_end(st, g)
    q = st.queue
    st.queue = []
    return nil if q.size == 0 || st.track == nil
    t_end = to_time(st, g)
    durs = []
    if st.codec == "opus"
      q.each ->(pk) durs.push(opus_packet_samples(pk).to_f / ~48000.0)
    elsif st.codec == "theo"
      q.each ->(pk) durs.push(~1.0 / st.fps)
    else
      span = st.last_end == nil ? ~0.0 : t_end - st.last_end
      span = ~0.0 if span < ~0.0
      q.each ->(pk) durs.push(span / q.size.to_f)
    tot = ~0.0
    durs.each ->(d) tot = tot + d
    t = t_end - tot
    # the first audio page: a short first page ends early (start trimming): keep pts from the end
    q.each_with_index ->(pk, i)
      key = true
      key = (pk.size > 0 && (pk[0] & 0x40) == 0) if st.codec == "theo"
      emit(st.serial, MediaSample.new(pk, t, t, durs[i], key))
      t = t + durs[i]
    st.last_end = t_end
    nil

  -> finish
    parse
    best = nil
    @streams.each ->(k, st)
      best = st.last_end if st.last_end != nil && (best == nil || st.last_end > best)
    @duration = best if @duration == nil && best != nil
    nil

  # Ogg has no index: estimate by bitrate; the loader bisects with restart().
  -> seek_offset(t)
    return nil if @duration == nil || @total == nil
    off = (t / @duration * @total.to_f).to_i - 65536
    off < 0 ? 0 : off

  -> total=(n)
    @total = n

# ---- WAV (RIFF/WAVE, RF64): PCM integer and float, WAVE_FORMAT_EXTENSIBLE ----

+ WavDemuxer < Demuxer
  -> new
    init_demuxer(:wav)
    @pos = 0
    @data_start = nil
    @data_end = nil
    @block = 0
    @rate = 0
    @emitted = 0

  -> parse
    return nil if @error != nil
    begin
      parse_wav()
    rescue e
      fail("wav: " + e.to_s)
    nil

  -> parse_wav
    if @data_start == nil
      return nil if !@buf.has?(0, 12)
      @pos = 12 if @pos == 0
      fmt = nil
      while @data_start == nil && @buf.has?(@pos, 8)
        id = dm_fourcc(@buf.data, @buf.off(@pos))
        sz = dm_le32(@buf.data, @buf.off(@pos) + 4)
        if id == "fmt "
          return nil if !@buf.has?(@pos + 8, sz)
          o = @buf.off(@pos + 8)
          b = @buf.data
          tag = dm_le16(b, o)
          ch = dm_le16(b, o + 2)
          @rate = dm_le32(b, o + 4)
          @block = dm_le16(b, o + 12)
          bits = dm_le16(b, o + 14)
          if tag == 0xFFFE && sz >= 40
            tag = dm_le16(b, o + 24)
          if tag != 1 && tag != 3
            fail("unsupported WAV format tag " + tag.to_s)
            return nil
          cfg = CodecConfig.new("pcm ", {bits: bits, float: tag == 3, big_endian: false})
          cfg.sample_rate = @rate
          cfg.channels = ch
          cfg.codec_string = "1"
          @tracks.push(MediaTrack.new(1, :audio, cfg))
        elsif id == "data"
          @data_start = @pos + 8
          @data_end = sz == 0xFFFFFFFF || sz == 0 ? nil : @pos + 8 + sz
          @duration = @data_end == nil || @block == 0 ? nil : (sz / @block).to_f / @rate.to_f
          @ready = true
          @pos = @data_start
          break
        @pos += 8 + sz + (sz & 1)
      return nil if @data_start == nil
    return nil if @block == 0
    # ~4096-frame samples
    chunk = 4096 * @block
    while true
      lim = @buf.limit
      lim = @data_end if @data_end != nil && @data_end < lim
      n = lim - @pos
      if n < chunk && (@data_end == nil || lim < @data_end)
        return nil
      n = chunk if n > chunk
      n = n - n % @block
      return nil if n <= 0
      frames = n / @block
      t = @emitted.to_f / @rate.to_f
      emit(1, MediaSample.new(@buf.slice(@pos, n), t, t, frames.to_f / @rate.to_f, true))
      @emitted += frames
      @pos += n
      @buf.discard(@pos)
    nil

  -> seek_offset(t)
    return nil if @data_start == nil
    f = (t * @rate.to_f).to_i
    @data_start + f * @block

  -> restart(off)
    @buf.reset(off)
    if @data_start != nil
      @pos = off
      @emitted = (off - @data_start) / @block
    nil

# ---- elementary streams parsed by their codec (MP3, ADTS AAC, native FLAC) ----

ES_PARSERS = {}

# parse: ->(bytes) {cfg:, samples:, duration:} (the codec file's *_es_parse).
-> es_parser_register(kind, parse)
  ES_PARSERS[kind] = parse

+ EsDemuxer < Demuxer
  -> new(k)
    init_demuxer(k)
    @done = false
    @final = false

  # The whole stream is parsed once it has fully arrived (finish).
  -> finish
    @final = true
    parse

  -> parse
    return nil if @done || !@final || @error != nil
    p = ES_PARSERS[@kind]
    if p == nil
      fail("no parser for " + @kind.to_s)
      return nil
    begin
      r = p.call(@buf.slice(@buf.base, @buf.len))
      t = MediaTrack.new(1, :audio, r[:cfg])
      @tracks.push(t)
      @duration = r[:duration]
      r[:samples].each ->(s) emit(1, s)
      @ready = true
    rescue e
      fail(@kind.to_s + ": " + e.to_s)
    @done = true
    nil
