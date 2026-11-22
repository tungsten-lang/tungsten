# core/codec/container/mux_webm — write a WebM (Matroska) file from
# compressed samples, without re-encoding.
#
#   m = WebmMuxer.new("out.webm")
#   v = m.add_track(:video, vp9_cfg)
#   a = m.add_track(:audio, opus_cfg)
#   m.write(v, sample) / m.write(a, sample)    # MediaSamples, interleaved by time
#   info = m.finish                            # {bytes:, duration:, tracks:}
#
# Streams to disk: EBML header, a Segment whose size is patched at finish, a
# SeekHead (Info, Tracks, Cues), Info (1 ms timestamps; Duration patched),
# Tracks, then Clusters of SimpleBlocks (a new cluster at each video keyframe
# after 1 s, or every 5 s, or when the 16-bit block offset would overflow),
# and Cues (one per cluster that starts with a video keyframe) at the end.
# Codecs: V_VP9, V_VP8, V_AV1 (av1C as CodecPrivate), V_MPEG4/ISO/AVC (avcC),
# V_MPEGH/ISO/HEVC (hvcC), A_OPUS (OpusHead, CodecDelay from the pre-skip,
# SeekPreRoll 80 ms), A_VORBIS (Xiph-laced headers), A_AAC (ASC), A_FLAC.
# Block timestamps are presentation times (Matroska's model); samples should
# come in decode order per track.

WEBM_MUX_CODECS = {"vp09" => "V_VP9", "vp08" => "V_VP8", "av01" => "V_AV1", "avc1" => "V_MPEG4/ISO/AVC", "avc3" => "V_MPEG4/ISO/AVC", "hvc1" => "V_MPEGH/ISO/HEVC", "hev1" => "V_MPEGH/ISO/HEVC", "opus" => "A_OPUS", "vorb" => "A_VORBIS", "mp4a" => "A_AAC", "flac" => "A_FLAC", "mp3 " => "A_MPEG/L3"}

+ WebmMuxTrack
  rw :num, :kind, :cfg, :last_ms

  -> new(@num, @kind, @cfg)
    @last_ms = 0

+ WebmMuxer
  ro :path, :tracks, :bytes

  -> .supports?(codec)
    WEBM_MUX_CODECS.has_key?(codec)

  -> new(@path)
    @f = File.open(@path, "w+b")
    @tracks = []
    @bytes = 0
    @started = false
    @cluster_ms = nil
    @cues = []
    @max_ms = 0
    @t0 = nil

  -> put(b)
    @f.write(b)
    @bytes += b.size
    nil

  -> add_track(kind, cfg)
    raise MediaError.new("webm mux: cannot write codec " + cfg.codec) if !WebmMuxer.supports?(cfg.codec)
    t = WebmMuxTrack.new(@tracks.size + 1, kind, cfg)
    @tracks.push(t)
    @tracks.size - 1

  -> has_video?
    @tracks.any?(->(t) t.kind == :video)

  # Header, SeekHead, Info and Tracks (once, before the first block).
  -> start
    @started = true
    put(ebml_el(0x1A45DFA3, mux_cat([ebml_uint(0x4286, 1), ebml_uint(0x42F7, 1), ebml_uint(0x42F2, 4), ebml_uint(0x42F3, 8), ebml_str(0x4282, "webm"), ebml_uint(0x4287, 4), ebml_uint(0x4285, 2)])))
    # Segment with an 8-byte size, patched at finish
    put(mux_cat([ebml_id(0x18538067), mux_u8(0x01), mux_zero(7)]))
    @seg_size_at = @bytes - 7
    @seg_data = @bytes
    # SeekHead with fixed-size positions (patched at finish)
    @seek_at = @bytes
    put(seekhead(0, 0, 0))
    @info_at = @bytes
    tracks = []
    @tracks.each ->(t) tracks.push(track_entry(t))
    info = ebml_el(0x1549A966, mux_cat([ebml_uint(0x2AD7B1, 1000000), ebml_str(0x4D80, "Blade"), ebml_str(0x5741, "Blade"), ebml_el(0x4489, mux_u64(0))]))
    put(info)
    # Duration (8-byte float, last in Info) is patched at finish
    @dur_at = @bytes - 8
    @tracks_at = @bytes
    put(ebml_el(0x1654AE6B, mux_cat(tracks)))
    nil

  -> track_entry(t)
    c = t.cfg
    kids = [ebml_uint(0xD7, t.num), ebml_uint(0x73C5, t.num), ebml_uint(0x83, t.kind == :video ? 1 : 2), ebml_uint(0x9C, 0), ebml_str(0x86, WEBM_MUX_CODECS[c.codec])]
    priv = nil
    x = c.extra
    if c.codec == "vorb" && x.is_a?(Array)
      priv = webm_xiph_lace(x)
    elsif x != nil && x.is_a?(ByteArray) && x.size > 0 && c.codec != "vp09" && c.codec != "vp08"
      priv = x
      if c.codec == "flac"
        # "fLaC" + a last-block STREAMINFO header + the 34 bytes
        priv = mux_cat([mux_ascii("fLaC"), mux_u8(0x80), mux_u24(34), x])
    kids.push(ebml_bin(0x63A2, priv)) if priv != nil
    if t.kind == :video
      vk = [ebml_uint(0xB0, c.width), ebml_uint(0xBA, c.height)]
      if c.primaries != 2 || c.transfer != 2 || c.matrix != 2
        col = [ebml_uint(0x55B1, c.matrix), ebml_uint(0x55BA, c.transfer), ebml_uint(0x55BB, c.primaries)]
        col.push(ebml_uint(0x55B9, c.full_range ? 2 : 1)) if c.full_range != nil
        vk.push(ebml_el(0x55B0, mux_cat(col)))
      kids.push(ebml_el(0xE0, mux_cat(vk)))
    else
      rate = c.codec == "opus" ? 48000 : (c.sample_rate > 0 ? c.sample_rate : 48000)
      ch = c.channels > 0 ? c.channels : 2
      if c.codec == "opus"
        pre = x != nil && x.size >= 12 ? (x[10] | (x[11] << 8)) : 312
        kids.push(ebml_uint(0x56AA, pre * 1000000000 / 48000))
        kids.push(ebml_uint(0x56BB, 80000000))
      kids.push(ebml_el(0xE1, mux_cat([ebml_float(0xB5, rate.to_f), ebml_uint(0x9F, ch)])))
    ebml_el(0xAE, mux_cat(kids))

  -> seekhead(info, tracks, cues)
    e = ->(id, pos) ebml_el(0x4DBB, mux_cat([ebml_bin(0x53AB, ebml_id(id)), ebml_el8(0x53AC, mux_u64(pos))]))
    ebml_el(0x114D9B74, mux_cat([e.call(0x1549A966, info), e.call(0x1654AE6B, tracks), e.call(0x1C53BB6B, cues)]))

  -> write(ti, s)
    start() if !@started
    t = @tracks[ti]
    @t0 = s.pts if @t0 == nil
    # Opus: block times include the CodecDelay that demuxers subtract
    pts = s.pts
    if t.cfg.codec == "opus"
      x = t.cfg.extra
      pts = pts + (x != nil && x.size >= 12 ? (x[10] | (x[11] << 8)) : 312).to_f / ~48000.0
    ms = (pts * ~1000.0).round
    ms = 0 if ms < 0
    key = s.key || t.kind == :audio
    vkey = t.kind == :video && s.key
    need = @cluster_ms == nil || ms - @cluster_ms > 5000 || ms - @cluster_ms < -32000 || ms - @cluster_ms > 32000
    need = true if vkey && @cluster_ms != nil && ms - @cluster_ms >= 1000
    if need
      close_cluster()
      @cluster_ms = ms
      cpos = @bytes - @seg_data
      # cluster with an 8-byte size, patched when it is closed
      put(mux_cat([ebml_id(0x1F43B675), mux_u8(0x01), mux_zero(7)]))
      @cluster_size_at = @bytes - 7
      put(ebml_uint(0xE7, ms))
      @cues.push([ms, cpos, t.num]) if vkey || !has_video?()
    rel = ms - @cluster_ms
    rel = rel + 65536 if rel < 0
    n = s.data.size
    hdr = mux_cat([mux_u8(0x80 | t.num), mux_u16(rel & 0xFFFF), mux_u8(key ? 0x80 : 0)])
    put(ebml_el_hdr(0xA3, hdr.size + n))
    put(hdr)
    put(s.data)
    e = ms + (s.duration * ~1000.0).round
    @max_ms = e if e > @max_ms
    nil

  # Patch the open cluster's size (its body ends here).
  -> close_cluster
    return nil if @cluster_size_at == nil
    n = @bytes - (@cluster_size_at + 7)
    @f.seek(@cluster_size_at)
    @f.write(webm_size7(n))
    @f.seek(0, 2)
    @cluster_size_at = nil
    nil

  -> finish
    start() if !@started
    close_cluster()
    cues_pos = @bytes - @seg_data
    cps = []
    @cues.each ->(c)
      cps.push(ebml_el(0xBB, mux_cat([ebml_uint(0xB3, c[0]), ebml_el(0xB7, mux_cat([ebml_uint(0xF7, c[2]), ebml_uint(0xF1, c[1])]))])))
    put(ebml_el(0x1C53BB6B, mux_cat(cps))) if cps.size > 0
    total = @bytes - @seg_data
    # patch: segment size, seek positions, duration
    @f.seek(@seg_size_at)
    @f.write(webm_size7(total))
    @f.seek(@seek_at)
    @f.write(seekhead(@info_at - @seg_data, @tracks_at - @seg_data, cps.size > 0 ? cues_pos : 0))
    @f.seek(@dur_at)
    @f.write(webm_f64(@max_ms.to_f))
    @f.close
    {bytes: File.size(@path), duration: @max_ms.to_f / ~1000.0, tracks: @tracks.size}

# ---- EBML helpers ----

# The 7 bytes after an 0x01 length marker: an 8-byte EBML size.
-> webm_size7(n)
  b = ByteArray.new(7)
  i = 0
  while i < 7
    b[i] = (n >> (48 - 8 * i)) & 255
    i += 1
  b

-> ebml_id(id)
  return mux_u8(id) if id < 0x100
  return mux_u16(id) if id < 0x10000
  return mux_u24(id) if id < 0x1000000
  mux_u32(id)

# Size as a vint (shortest form, up to 8 bytes).
-> ebml_size(n)
  return mux_u8(0x80 | n) if n < 127
  return mux_u16(0x4000 | n) if n < 16383
  return mux_u24(0x200000 | n) if n < 2097151
  return mux_u32(0x10000000 | n) if n < 268435455
  mux_cat([mux_u8(0x01), mux_u8(((n >> 48) & 255)), mux_u8(((n >> 40) & 255)), mux_u8(((n >> 32) & 255)), mux_u8(((n >> 24) & 255)), mux_u8(((n >> 16) & 255)), mux_u8(((n >> 8) & 255)), mux_u8(n & 255)])

-> ebml_el_hdr(id, n)
  mux_cat([ebml_id(id), ebml_size(n)])

-> ebml_el(id, body)
  mux_cat([ebml_id(id), ebml_size(body.size), body])

# An element with an 8-byte size field (patchable bodies keep their length).
-> ebml_el8(id, body)
  mux_cat([ebml_id(id), mux_u8(0x80 | body.size), body])

-> ebml_uint(id, v)
  n = 1
  while n < 8 && (v >> (8 * n)) != 0
    n += 1
  b = ByteArray.new(n)
  i = 0
  while i < n
    b[n - 1 - i] = (v >> (8 * i)) & 255
    i += 1
  ebml_el(id, b)

-> ebml_str(id, s)
  ebml_el(id, mux_ascii(s))

-> ebml_bin(id, b)
  ebml_el(id, b)

-> ebml_float(id, f)
  ebml_el(id, webm_f64(f))

# IEEE-754 binary64, big-endian.
-> webm_f64(f)
  b = ByteArray.new(8)
  return b if f == ~0.0
  s = f < ~0.0 ? 1 : 0
  a = f < ~0.0 ? ~0.0 - f : f
  e = 0
  while a >= ~2.0
    a = a / ~2.0
    e += 1
  while a < ~1.0
    a = a * ~2.0
    e -= 1
  m = ((a - ~1.0) * ~4503599627370496.0).round
  bits = (s << 63) | ((e + 1023) << 52) | m
  i = 0
  while i < 8
    b[i] = (bits >> (56 - 8 * i)) & 255
    i += 1
  b

# Xiph lacing of the Vorbis header packets (CodecPrivate).
-> webm_xiph_lace(pk)
  parts = [mux_u8(pk.size - 1)]
  i = 0
  while i < pk.size - 1
    n = pk[i].size
    while n >= 255
      parts.push(mux_u8(255))
      n -= 255
    parts.push(mux_u8(n))
    i += 1
  pk.each ->(p) parts.push(p)
  mux_cat(parts)
