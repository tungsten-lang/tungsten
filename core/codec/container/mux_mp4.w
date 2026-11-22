# core/codec/container/mux_mp4 — write an MP4 (ISO BMFF) from compressed
# samples, without re-encoding: the remux half of the demuxers.
#
#   m = Mp4Muxer.new("out.mp4")
#   v = m.add_track(:video, video_cfg)      # a CodecConfig as a demuxer gives it
#   a = m.add_track(:audio, audio_cfg)
#   m.write(v, sample)                      # MediaSample: data, pts/dts/duration (s), key
#   m.write(a, sample)                      # any interleaving; each track in decode order
#   info = m.finish                         # {bytes:, duration:, tracks:}
#
# Streams to disk: the mdat (64-bit size) comes first and grows as samples are
# written, the moov follows at finish, so memory holds only the sample tables.
# finish(faststart: true) rewrites the file with the moov first (for playing
# while it downloads), copying the media in chunks.
#
# Codecs (sample entry from CodecConfig.extra): H.264 avc1/avcC, HEVC hvc1/hvcC,
# AV1 av01/av1C, VP9 vp09/vpcC (synthesised when the source had none, e.g.
# WebM), AAC mp4a/esds (AudioSpecificConfig), MP3 mp4a/esds (0x6B), Opus
# Opus/dOps (from the OpusHead), FLAC fLaC/dfLa (STREAMINFO). Timestamps:
# video in a 90 kHz timescale, audio at its sample rate; composition offsets
# in ctts (version 1, signed); each track gets an edit list placing its first
# presented sample at its presentation time (audio priming with negative pts
# is trimmed, a late-starting track gets an empty edit). Keyframes go to stss.
# Mp4Muxer.supports?(codec) tells whether a codec id can be written.

+ Mp4MuxTrack
  rw :kind, :cfg, :timescale, :sizes, :dts, :cts, :durs, :keys, :chunks, :first_pts, :last_dur, :width, :height, :all_key, :id
  # Annex B input (MPEG-TS H.264 / HEVC): samples are rewritten with 4-byte
  # lengths and the decoder configuration is built from the parameter sets.
  rw :annexb, :hevc, :vps, :sps, :pps

  -> new(@id, @kind, @cfg)
    @timescale = @kind == :video ? 90000 : (@cfg.sample_rate > 0 ? @cfg.sample_rate : 48000)
    @sizes = []
    @dts = []
    @cts = []
    @durs = []
    @keys = []
    @chunks = []       # [file offset, first sample index (0-based), count]
    @first_pts = nil
    @last_dur = 0
    @width = @cfg.width
    @height = @cfg.height
    @all_key = true
    @hevc = @cfg.codec == "hvc1" || @cfg.codec == "hev1"
    @annexb = @cfg.codec == "h264" || (@hevc && (@cfg.extra == nil || !@cfg.extra.is_a?(ByteArray) || @cfg.extra.size < 23))
    @vps = nil
    @sps = nil
    @pps = nil

MP4_MUX_CODECS = ["avc1", "avc3", "h264", "hvc1", "hev1", "av01", "vp09", "mp4a", "mp3 ", "opus", "flac"]

+ Mp4Muxer
  ro :path, :tracks, :bytes

  -> .supports?(codec)
    MP4_MUX_CODECS.include?(codec)

  -> new(@path)
    @f = File.open(@path, "w+b")
    @tracks = []
    @bytes = 0
    @cur_track = -1
    @chunk_bytes = 0
    ftyp = mux_box("ftyp", mux_cat([mux_ascii("isom"), mux_u32(512), mux_ascii("isomiso2avc1mp41iso6")]))
    put(ftyp)
    # mdat with a 64-bit size, patched at finish
    @mdat_at = @bytes
    put(mux_cat([mux_u32(1), mux_ascii("mdat"), mux_u64(0)]))

  -> put(b)
    @f.write(b)
    @bytes += b.size
    nil

  -> add_track(kind, cfg)
    raise MediaError.new("mp4 mux: cannot write codec " + cfg.codec) if !Mp4Muxer.supports?(cfg.codec)
    t = Mp4MuxTrack.new(@tracks.size + 1, kind, cfg)
    @tracks.push(t)
    @tracks.size - 1

  -> write(ti, s)
    t = @tracks[ti]
    data = t.annexb ? mp4_annexb_to_avcc(t, s.data) : s.data
    n = data.size
    return nil if n == 0
    # a new chunk when the track changes or the chunk passes 1 MB
    if ti != @cur_track || @chunk_bytes > 1048576
      t.chunks.push([@bytes, t.sizes.size, 0])
      @cur_track = ti
      @chunk_bytes = 0
    c = t.chunks[t.chunks.size - 1]
    c[2] = c[2] + 1
    ts = t.timescale.to_f
    d = (s.dts * ts).round
    p = (s.pts * ts).round
    t.first_pts = s.pts if t.first_pts == nil || s.pts < t.first_pts
    t.sizes.push(n)
    t.dts.push(d)
    t.cts.push(p - d)
    t.last_dur = (s.duration * ts).round
    k = s.key || t.kind == :audio
    t.keys.push(k)
    t.all_key = false if !k
    put(data)
    ccall("w_value_free_w", data) if data != s.data
    @chunk_bytes += n
    nil

  -> finish(faststart = false)
    # patch the mdat size
    msize = @bytes - @mdat_at
    @f.seek(@mdat_at + 8)
    @f.write(mux_u64(msize))
    @f.seek(0, 2)
    moov = build_moov(0)
    put(moov)
    @f.close
    dur = movie_duration()
    if faststart
      mp4_mux_faststart(@path, @mdat_at, msize, self)
    {bytes: File.size(@path), duration: dur, tracks: @tracks.size}

  -> movie_duration
    best = ~0.0
    @tracks.each ->(t)
      d = track_seconds(t)
      best = d if d > best
    best

  # Media duration of a track in seconds (from its decode times).
  -> track_seconds(t)
    n = t.dts.size
    return ~0.0 if n == 0
    (t.dts[n - 1] - t.dts[0] + (t.last_dur > 0 ? t.last_dur : 1)).to_f / t.timescale.to_f

  # The moov; offsets shift by `delta` (faststart moves the media).
  -> build_moov(delta)
    mts = 1000
    dur = (movie_duration() * mts.to_f).round
    mvhd = mux_full("mvhd", 1, 0, mux_cat([mux_u64(0), mux_u64(0), mux_u32(mts), mux_u64(dur), mux_u32(0x00010000), mux_u16(0x0100), mux_zero(10), mux_matrix(), mux_zero(24), mux_u32(@tracks.size + 1)]))
    parts = [mvhd]
    @tracks.each ->(t) parts.push(build_trak(t, mts, delta))
    mux_box("moov", mux_cat(parts))

  -> build_trak(t, mts, delta)
    tdur = (track_seconds(t) * mts.to_f).round
    vol = t.kind == :audio ? 0x0100 : 0
    w = t.kind == :video ? t.width : 0
    h = t.kind == :video ? t.height : 0
    tkhd = mux_full("tkhd", 1, 3, mux_cat([mux_u64(0), mux_u64(0), mux_u32(t.id), mux_u32(0), mux_u64(tdur), mux_zero(8), mux_u16(0), mux_u16(t.kind == :audio ? 1 : 0), mux_u16(vol), mux_u16(0), mux_matrix(), mux_u32(w << 16), mux_u32(h << 16)]))
    # edit list: presentation starts at max(first pts, 0)
    ts = t.timescale.to_f
    first_dts = t.dts.size > 0 ? t.dts[0] : 0
    fp = t.first_pts == nil ? ~0.0 : t.first_pts
    edits = []
    if fp > ~0.001
      edits.push([(fp * mts.to_f).round, -1])
    start = fp > ~0.0 ? fp : ~0.0
    media_time = (start * ts).round - first_dts
    media_time = 0 if media_time < 0
    edits.push([tdur, media_time])
    eb = [mux_u32(edits.size)]
    edits.each ->(e)
      eb.push(mux_u64(e[0]))
      eb.push(mux_u64(e[1] < 0 ? 0xFFFFFFFFFFFFFFFF : e[1]))
      eb.push(mux_u32(0x00010000))
    edts = mux_box("edts", mux_full("elst", 1, 0, mux_cat(eb)))
    mdur = t.dts.size == 0 ? 0 : t.dts[t.dts.size - 1] - first_dts + (t.last_dur > 0 ? t.last_dur : 1)
    mdhd = mux_full("mdhd", 1, 0, mux_cat([mux_u64(0), mux_u64(0), mux_u32(t.timescale), mux_u64(mdur), mux_u16(0x55C4), mux_u16(0)]))
    hname = t.kind == :video ? "VideoHandler" : "SoundHandler"
    hdlr = mux_full("hdlr", 0, 0, mux_cat([mux_u32(0), mux_ascii(t.kind == :video ? "vide" : "soun"), mux_zero(12), mux_ascii(hname), mux_zero(1)]))
    xmhd = t.kind == :video ? mux_full("vmhd", 0, 1, mux_zero(8)) : mux_full("smhd", 0, 0, mux_zero(4))
    dref = mux_full("dref", 0, 0, mux_cat([mux_u32(1), mux_full("url ", 0, 1, ByteArray.new(0))]))
    dinf = mux_box("dinf", dref)
    stbl = build_stbl(t, delta)
    minf = mux_box("minf", mux_cat([xmhd, dinf, stbl]))
    mdia = mux_box("mdia", mux_cat([mdhd, hdlr, minf]))
    mux_box("trak", mux_cat([tkhd, edts, mdia]))

  -> build_stbl(t, delta)
    n = t.sizes.size
    stsd = mux_full("stsd", 0, 0, mux_cat([mux_u32(1), sample_entry(t)]))
    # stts: run-length of decode deltas
    sb = ByteArray.new(n * 8 + 8)
    runs = 0
    o = 4
    i = 0
    while i < n
      d = i + 1 < n ? t.dts[i + 1] - t.dts[i] : (t.last_dur > 0 ? t.last_dur : (i > 0 ? t.dts[i] - t.dts[i - 1] : 1))
      d = 0 if d < 0
      cnt = 1
      while i + cnt < n
        d2 = i + cnt + 1 < n ? t.dts[i + cnt + 1] - t.dts[i + cnt] : (t.last_dur > 0 ? t.last_dur : d)
        break if d2 != d
        cnt += 1
      mux_put32(sb, o, cnt)
      mux_put32(sb, o + 4, d)
      o += 8
      runs += 1
      i += cnt
    mux_put32(sb, 0, runs)
    stts = mux_full("stts", 0, 0, dm_slice(sb, 0, o))
    parts = [stsd, stts]
    # ctts when any composition offset is non-zero
    any = false
    t.cts.each ->(c) any = true if c != 0
    if any
      cb = ByteArray.new(n * 8 + 4)
      runs = 0
      o = 4
      i = 0
      while i < n
        c = t.cts[i]
        cnt = 1
        while i + cnt < n && t.cts[i + cnt] == c
          cnt += 1
        mux_put32(cb, o, cnt)
        mux_put32(cb, o + 4, c & 0xFFFFFFFF)
        o += 8
        runs += 1
        i += cnt
      mux_put32(cb, 0, runs)
      parts.push(mux_full("ctts", 1, 0, dm_slice(cb, 0, o)))
    # stss when not every sample is a keyframe
    if !t.all_key
      ks = []
      i = 0
      while i < n
        ks.push(i + 1) if t.keys[i]
        i += 1
      kb = ByteArray.new(4 + ks.size * 4)
      mux_put32(kb, 0, ks.size)
      ks.each_with_index ->(k, j) mux_put32(kb, 4 + j * 4, k)
      parts.push(mux_full("stss", 0, 0, kb))
    # stsc: one entry per change in samples-per-chunk
    nc = t.chunks.size
    scb = ByteArray.new(4 + nc * 12)
    ent = 0
    prev = -1
    j = 0
    while j < nc
      cnt = t.chunks[j][2]
      if cnt != prev
        mux_put32(scb, 4 + ent * 12, j + 1)
        mux_put32(scb, 8 + ent * 12, cnt)
        mux_put32(scb, 12 + ent * 12, 1)
        ent += 1
        prev = cnt
      j += 1
    mux_put32(scb, 0, ent)
    parts.push(mux_full("stsc", 0, 0, dm_slice(scb, 0, 4 + ent * 12)))
    # stsz
    zb = ByteArray.new(8 + n * 4)
    mux_put32(zb, 0, 0)
    mux_put32(zb, 4, n)
    i = 0
    while i < n
      mux_put32(zb, 8 + i * 4, t.sizes[i])
      i += 1
    parts.push(mux_full("stsz", 0, 0, zb))
    # stco / co64
    big = false
    t.chunks.each ->(c) big = true if c[0] + delta > 0xFFFFFFFF
    if big
      ob = ByteArray.new(4 + nc * 8)
      mux_put32(ob, 0, nc)
      j = 0
      while j < nc
        v = t.chunks[j][0] + delta
        mux_put32(ob, 4 + j * 8, v >> 32)
        mux_put32(ob, 8 + j * 8, v & 0xFFFFFFFF)
        j += 1
      parts.push(mux_full("co64", 0, 0, ob))
    else
      ob = ByteArray.new(4 + nc * 4)
      mux_put32(ob, 0, nc)
      j = 0
      while j < nc
        mux_put32(ob, 4 + j * 4, t.chunks[j][0] + delta)
        j += 1
      parts.push(mux_full("stco", 0, 0, ob))
    mux_box("stbl", mux_cat(parts))

  -> sample_entry(t)
    c = t.cfg
    x = c.extra
    if t.kind == :video
      typ = c.codec
      typ = "avc1" if typ == "avc3" || typ == "h264"
      typ = "hvc1" if typ == "hev1"
      cbox = nil
      if t.annexb
        x = t.hevc ? mp4_hvcc(t) : mp4_avcc(t)
      if typ == "avc1"
        cbox = mux_box("avcC", x)
      elsif typ == "hvc1"
        cbox = mux_box("hvcC", x)
      elsif typ == "av01"
        cbox = mux_box("av1C", x)
      elsif typ == "vp09"
        cbox = x != nil && x.is_a?(ByteArray) && x.size >= 8 ? mux_box("vpcC", x) : mux_box("vpcC", mux_vpcc(c))
      kids = [cbox, mux_box("pasp", mux_cat([mux_u32(1), mux_u32(1)]))]
      if c.primaries != 2 || c.transfer != 2 || c.matrix != 2
        kids.push(mux_box("colr", mux_cat([mux_ascii("nclx"), mux_u16(c.primaries), mux_u16(c.transfer), mux_u16(c.matrix), mux_u8(c.full_range == true ? 0x80 : 0)])))
      body = mux_cat([mux_zero(6), mux_u16(1), mux_zero(16), mux_u16(t.width), mux_u16(t.height), mux_u32(0x00480000), mux_u32(0x00480000), mux_u32(0), mux_u16(1), mux_zero(32), mux_u16(0x18), mux_u16(0xFFFF), mux_cat(kids)])
      return mux_box(typ, body)
    ch = c.channels > 0 ? c.channels : 2
    rate = c.sample_rate > 0 ? c.sample_rate : 48000
    typ = "mp4a"
    cbox = nil
    if c.codec == "mp4a"
      cbox = mux_esds(0x40, x)
    elsif c.codec == "mp3 "
      cbox = mux_esds(0x6B, nil)
    elsif c.codec == "opus"
      typ = "Opus"
      cbox = mux_box("dOps", mux_dops(x))
      rate = 48000
    elsif c.codec == "flac"
      typ = "fLaC"
      cbox = mux_full("dfLa", 0, 0, mux_cat([mux_u8(0x80), mux_u24(34), x]))
    srate = rate > 65535 ? 0 : rate
    body = mux_cat([mux_zero(6), mux_u16(1), mux_zero(8), mux_u16(ch), mux_u16(16), mux_u16(0), mux_u16(0), mux_u32(srate << 16), cbox])
    mux_box(typ, body)

# Annex B (start codes) → 4-byte NAL lengths, dropping access unit
# delimiters; the first parameter sets seen are kept for avcC / hvcC.
-> mp4_annexb_to_avcc(t, b)
  n = b.size
  nals = []
  i = 0
  start = -1
  while i + 2 < n
    if b[i] == 0 && b[i + 1] == 0 && b[i + 2] == 1
      nals.push([start, i]) if start >= 0
      i += 3
      start = i
    else
      i += 1
  nals.push([start, n]) if start >= 0
  return b if nals.size == 0
  parts = []
  nals.each ->(r)
    s = r[0]
    e = r[1]
    # a 4-byte start code leaves a zero before the next one
    while e > s && b[e - 1] == 0
      e -= 1
    if e > s
      typ = t.hevc ? (b[s] >> 1) & 63 : b[s] & 31
      aud = t.hevc ? typ == 35 : typ == 9
      if !aud
        nal = dm_slice(b, s, e - s)
        if t.hevc
          t.vps = nal if typ == 32 && t.vps == nil
          t.sps = nal if typ == 33 && t.sps == nil
          t.pps = nal if typ == 34 && t.pps == nil
        else
          t.sps = nal if typ == 7 && t.sps == nil
          t.pps = nal if typ == 8 && t.pps == nil
        parts.push(mux_u32(e - s))
        parts.push(nal)
  mux_cat(parts)

-> mp4_avcc(t)
  sps = t.sps
  pps = t.pps
  return mux_cat([mux_u8(1), mux_u8(66), mux_u8(0), mux_u8(30), mux_u8(0xFF), mux_u8(0xE0), mux_u8(0)]) if sps == nil || sps.size < 4
  pp = pps == nil ? [] : [mux_u8(1), mux_u16(pps.size), pps]
  mux_cat([mux_u8(1), mux_u8(sps[1]), mux_u8(sps[2]), mux_u8(sps[3]), mux_u8(0xFF), mux_u8(0xE1), mux_u16(sps.size), sps, pps == nil ? mux_u8(0) : mux_cat(pp)])

# A minimal hvcC: general profile/tier/level copied from the SPS's
# profile_tier_level, 4:2:0, 8-bit, 4-byte lengths, the VPS/SPS/PPS arrays.
-> mp4_hvcc(t)
  ptl = ByteArray.new(12)
  sps = t.sps
  if sps != nil && sps.size >= 15
    dm_copy(ptl, 0, sps, 3, 12)
  arrays = []
  [[32, t.vps], [33, t.sps], [34, t.pps]].each ->(a)
    if a[1] != nil
      arrays.push(mux_cat([mux_u8(0x80 | a[0]), mux_u16(1), mux_u16(a[1].size), a[1]]))
  mux_cat([mux_u8(1), ptl, mux_u16(0xF000), mux_u8(0xFC), mux_u8(0xFD), mux_u8(0xF8), mux_u8(0xF8), mux_u16(0), mux_u8(0x0F), mux_u8(arrays.size), mux_cat(arrays)])

# Rewrite path with the moov before the mdat (copying the media in 4 MB pieces).
-> mp4_mux_faststart(path, mdat_at, msize, m)
  tmp = path + ".faststart"
  moov = m.build_moov(0)
  moov = m.build_moov(moov.size)
  src = File.open(path, "rb")
  dst = File.open(tmp, "wb")
  head = src.read(mdat_at)
  dst.write(head)
  dst.write(moov)
  src.seek(mdat_at)
  left = msize
  while left > 0
    n = left > 4194304 ? 4194304 : left
    b = src.read(n)
    break if b == nil || b.size == 0
    dst.write(b)
    left -= b.size
  src.close
  dst.close
  File.rename(tmp, path)
  nil

# ---- box helpers ----

-> mux_u8(v)
  b = ByteArray.new(1)
  b[0] = v & 255
  b

-> mux_u16(v)
  b = ByteArray.new(2)
  b[0] = (v >> 8) & 255
  b[1] = v & 255
  b

-> mux_u24(v)
  b = ByteArray.new(3)
  b[0] = (v >> 16) & 255
  b[1] = (v >> 8) & 255
  b[2] = v & 255
  b

-> mux_u32(v)
  b = ByteArray.new(4)
  mux_put32(b, 0, v)
  b

-> mux_u64(v)
  b = ByteArray.new(8)
  mux_put32(b, 0, (v >> 32) & 0xFFFFFFFF)
  mux_put32(b, 4, v & 0xFFFFFFFF)
  b

-> mux_put32(b, o, v)
  b[o] = (v >> 24) & 255
  b[o + 1] = (v >> 16) & 255
  b[o + 2] = (v >> 8) & 255
  b[o + 3] = v & 255
  nil

-> mux_zero(n)
  ByteArray.new(n)

-> mux_ascii(s)
  b = ByteArray.new(s.size)
  i = 0
  while i < s.size
    b[i] = s.byte_at(i)
    i += 1
  b

-> mux_cat(parts)
  n = 0
  parts.each ->(p) n += p.size if p != nil
  out = ByteArray.new(n)
  o = 0
  parts.each ->(p)
    if p != nil
      dm_copy(out, o, p, 0, p.size)
      o += p.size
  out

-> mux_box(typ, body)
  b = body == nil ? ByteArray.new(0) : body
  mux_cat([mux_u32(8 + b.size), mux_ascii(typ), b])

-> mux_full(typ, ver, flags, body)
  mux_box(typ, mux_cat([mux_u8(ver), mux_u24(flags), body]))

-> mux_matrix
  mux_cat([mux_u32(0x00010000), mux_u32(0), mux_u32(0), mux_u32(0), mux_u32(0x00010000), mux_u32(0), mux_u32(0), mux_u32(0), mux_u32(0x40000000)])

# MPEG-4 descriptor length (4-byte form).
-> mux_desc(tag, body)
  n = body.size
  mux_cat([mux_u8(tag), mux_u8(0x80 | ((n >> 21) & 127)), mux_u8(0x80 | ((n >> 14) & 127)), mux_u8(0x80 | ((n >> 7) & 127)), mux_u8(n & 127), body])

-> mux_esds(oti, asc)
  dsi = asc != nil && asc.is_a?(ByteArray) && asc.size > 0 ? mux_desc(5, asc) : ByteArray.new(0)
  dcd = mux_desc(4, mux_cat([mux_u8(oti), mux_u8(0x15), mux_u24(0), mux_u32(0), mux_u32(0), dsi]))
  sl = mux_desc(6, mux_u8(2))
  es = mux_desc(3, mux_cat([mux_u16(1), mux_u8(0), dcd, sl]))
  mux_full("esds", 0, 0, es)

# OpusHead (little-endian) → dOps (big-endian).
-> mux_dops(h)
  return mux_cat([mux_u8(0), mux_u8(2), mux_u16(312), mux_u32(48000), mux_u16(0), mux_u8(0)]) if h == nil || h.size < 19
  ch = h[9]
  pre = h[10] | (h[11] << 8)
  rate = h[12] | (h[13] << 8) | (h[14] << 16) | (h[15] << 24)
  gain = h[16] | (h[17] << 8)
  fam = h[18]
  rest = h.size > 19 ? dm_slice(h, 19, h.size - 19) : ByteArray.new(0)
  mux_cat([mux_u8(0), mux_u8(ch), mux_u16(pre), mux_u32(rate), mux_u16(gain), mux_u8(fam), fam != 0 ? rest : nil])

# A vpcC (version 1) for VP9 without one (WebM): profile 0, level 3.1, 8-bit 4:2:0.
-> mux_vpcc(c)
  rng = c.full_range == true ? 1 : 0
  mux_cat([mux_u8(1), mux_u24(0), mux_u8(0), mux_u8(31), mux_u8((8 << 4) | (1 << 1) | rng), mux_u8(c.primaries), mux_u8(c.transfer), mux_u8(c.matrix), mux_u16(0)])
