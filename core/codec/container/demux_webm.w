# core/codec/container/demux_webm — Matroska / WebM (EBML).
#
# EBML header, Segment (known or unknown size), Info (TimestampScale,
# Duration), Tracks (TrackEntry: number, type, CodecID, CodecPrivate,
# CodecDelay, DefaultDuration, Language, FlagDefault, Video size and Colour,
# Audio rate/channels/bit depth, ContentEncoding header stripping), Cluster
# (known or unknown size: live and MSE streams) with Timestamp, SimpleBlock and
# BlockGroup (Block, BlockDuration, ReferenceBlock), all four lacings, Cues
# (seek index). Master elements Segment and Cluster are entered, not buffered,
# so samples come out as each block arrives.

use core/codec/media
use demux

WEBM_SEGMENT = 0x18538067
WEBM_CLUSTER = 0x1F43B675

+ WebmTrack
  rw :num, :type, :codec_id, :priv, :delay, :default_dur, :lang, :default, :width, :height
  rw :rate, :channels, :bits, :strip, :colour, :name

  -> new
    @num = 0
    @type = 0
    @codec_id = ""
    @priv = nil
    @delay = 0
    @default_dur = 0
    @lang = nil
    @default = true
    @width = 0
    @height = 0
    @rate = ~0.0
    @channels = 1
    @bits = 0
    @strip = nil
    @colour = [2, 2, 2, 0]
    @name = nil

+ WebmDemuxer < Demuxer
  ro :cues

  -> new
    init_demuxer(:webm)
    @pos = 0
    @tscale = 1000000
    @seg_start = 0
    @seg_end = nil
    @cluster_end = nil   # absolute end of the current cluster (nil: unknown size)
    @in_cluster = false
    @cluster_tc = 0
    @wtracks = {}
    @cues = nil
    @cues_pos = nil
    @tracks_done = false

  -> restart(off)
    @buf.reset(off)
    @pos = off
    @in_cluster = false
    @cluster_end = nil
    nil

  # EBML variable-length integer at abs: [value, length] (value -1 = unknown size), or nil.
  -> vint(abs, is_id)
    return nil if !@buf.has?(abs, 1)
    b = @buf.u8(abs)
    return [-2, 1] if b == 0
    len = 1
    mask = 0x80
    while (b & mask) == 0
      mask = mask >> 1
      len += 1
    return nil if !@buf.has?(abs, len)
    v = is_id ? b : (b & (mask - 1))
    allones = (b & (mask - 1)) == mask - 1
    i = 1
    while i < len
      c = @buf.u8(abs + i)
      allones = false if c != 0xFF
      v = (v << 8) | c
      i += 1
    v = -1 if !is_id && allones
    [v, len]

  -> uint(abs, n)
    v = 0
    i = 0
    while i < n
      v = (v << 8) | @buf.u8(abs + i)
      i += 1
    v

  -> float(abs, n)
    return dm_f32_bits(uint(abs, 4)) if n == 4
    return dm_f64_bits(uint(abs, 8)) if n == 8
    ~0.0

  -> str(abs, n)
    dm_ascii(@buf.data, @buf.off(abs), n)

  -> parse
    return nil if @error != nil
    begin
      parse_elems()
    rescue e
      fail("webm: " + e.to_s)
    @buf.discard(@pos)
    nil

  -> parse_elems
    while true
      # the end of a cluster with a known size
      if @in_cluster && @cluster_end != nil && @pos >= @cluster_end
        @in_cluster = false
      idv = vint(@pos, true)
      return nil if idv == nil
      if idv[0] == -2
        fail("bad element id")
        return nil
      sz = vint(@pos + idv[1], false)
      return nil if sz == nil
      id = idv[0]
      size = sz[0]
      body = @pos + idv[1] + sz[1]
      if id == WEBM_SEGMENT
        @seg_start = body
        @seg_end = size == -1 ? nil : body + size
        @pos = body
        next
      if id == WEBM_CLUSTER
        @in_cluster = true
        @cluster_end = size == -1 ? nil : body + size
        @cluster_tc = 0
        @pos = body
        next
      if @in_cluster && @cluster_end == nil && (id == 0x1C53BB6B || id == 0x1654AE6B || id == 0x1549A966 || id == 0x1254C367 || id == 0x114D9B74 || id == 0x1043A770)
        @in_cluster = false
      if size == -1
        fail("unknown-size element " + id.to_s(16))
        return nil
      return nil if !@buf.has?(body, size)
      if @in_cluster
        cluster_child(id, body, size)
      else
        top_child(id, body, size)
      @pos = body + size
    nil

  -> top_child(id, s, n)
    if id == 0x1549A966
      parse_info(s, s + n)
    elsif id == 0x1654AE6B
      parse_tracks(s, s + n)
    elsif id == 0x1C53BB6B
      parse_cues(s, s + n)
    nil

  # Children of [s, e): Array of [id, body, size].
  -> kids(s, e)
    out = []
    p = s
    while p < e
      idv = vint(p, true)
      break if idv == nil
      sz = vint(p + idv[1], false)
      break if sz == nil
      body = p + idv[1] + sz[1]
      size = sz[0]
      size = e - body if size < 0 || body + size > e
      out.push([idv[0], body, size])
      p = body + size
    out

  -> parse_info(s, e)
    dur = nil
    kids(s, e).each ->(c)
      @tscale = uint(c[1], c[2]) if c[0] == 0x2AD7B1
      dur = float(c[1], c[2]) if c[0] == 0x4489
    @duration = dur * @tscale.to_f / ~1.0e9 if dur != nil && dur > ~0.0
    nil

  -> parse_tracks(s, e)
    kids(s, e).each ->(c)
      parse_entry(c[1], c[1] + c[2]) if c[0] == 0xAE
    @ready = true
    nil

  -> parse_entry(s, e)
    t = WebmTrack.new
    kids(s, e).each ->(c)
      id = c[0]
      case id
      when 0xD7
        t.num = uint(c[1], c[2])
      when 0x83
        t.type = uint(c[1], c[2])
      when 0x86
        t.codec_id = str(c[1], c[2])
      when 0x63A2
        t.priv = @buf.slice(c[1], c[2])
      when 0x56AA
        t.delay = uint(c[1], c[2])
      when 0x23E383
        t.default_dur = uint(c[1], c[2])
      when 0x22B59C
        t.lang = str(c[1], c[2])
      when 0x536E
        t.name = str(c[1], c[2])
      when 0x88
        t.default = uint(c[1], c[2]) != 0
      when 0xE0
        kids(c[1], c[1] + c[2]).each ->(v)
          t.width = uint(v[1], v[2]) if v[0] == 0xB0
          t.height = uint(v[1], v[2]) if v[0] == 0xBA
          if v[0] == 0x55B0
            kids(v[1], v[1] + v[2]).each ->(k)
              t.colour[2] = uint(k[1], k[2]) if k[0] == 0x55B1
              t.colour[3] = uint(k[1], k[2]) if k[0] == 0x55B9
              t.colour[1] = uint(k[1], k[2]) if k[0] == 0x55BA
              t.colour[0] = uint(k[1], k[2]) if k[0] == 0x55BB
      when 0xE1
        kids(c[1], c[1] + c[2]).each ->(a)
          t.rate = float(a[1], a[2]) if a[0] == 0xB5
          t.channels = uint(a[1], a[2]) if a[0] == 0x9F
          t.bits = uint(a[1], a[2]) if a[0] == 0x6264
      when 0x6D80
        # ContentEncodings: header stripping (compression algo 3) is supported; encryption is not
        kids(c[1], c[1] + c[2]).each ->(ce)
          kids(ce[1], ce[1] + ce[2]).each ->(x)
            if x[0] == 0x5034
              algo = 0
              set = nil
              kids(x[1], x[1] + x[2]).each ->(y)
                algo = uint(y[1], y[2]) if y[0] == 0x4254
                set = @buf.slice(y[1], y[2]) if y[0] == 0x4255
              t.strip = set if algo == 3
            elsif x[0] == 0x5035
              fail("encrypted WebM tracks are not supported")
    return nil if t.num == 0
    cfg = webm_cfg(t)
    return nil if cfg == nil
    @wtracks[t.num] = t
    kind = t.type == 1 ? :video : :audio
    mt = MediaTrack.new(t.num, kind, cfg)
    mt.lang = t.lang
    mt.label = t.name
    mt.default = t.default
    mt.delay = t.delay.to_f / ~1.0e9
    @tracks.push(mt)
    nil

  -> webm_cfg(t)
    return nil if t.type != 1 && t.type != 2
    id = t.codec_id
    codec = nil
    extra = t.priv
    if t.type == 1
      codec = "vp08" if id == "V_VP8"
      codec = "vp09" if id == "V_VP9"
      codec = "av01" if id == "V_AV1"
      codec = "avc1" if id == "V_MPEG4/ISO/AVC"
      codec = "hvc1" if id == "V_MPEGH/ISO/HEVC"
      if id == "V_THEORA"
        codec = "theo"
        extra = xiph_split(t.priv)
      codec = id if codec == nil
      cfg = CodecConfig.new(codec, extra)
      cfg.width = t.width
      cfg.height = t.height
      cfg.matrix = t.colour[2]
      cfg.transfer = t.colour[1]
      cfg.primaries = t.colour[0]
      cfg.full_range = t.colour[3] == 2 ? true : (t.colour[3] == 1 ? false : nil)
      cfg.codec_string = codec == "vp09" ? "vp09" : (extra != nil && extra.is_a?(ByteArray) ? mp4_codec_string(codec, extra) : codec)
      return cfg
    if id == "A_OPUS"
      codec = "opus"
    elsif id == "A_VORBIS"
      codec = "vorb"
      extra = xiph_split(t.priv)
    elsif id.starts_with?("A_AAC")
      codec = "mp4a"
      if extra == nil || extra.size < 2
        extra = aac_asc_for(id, t.rate.to_i, t.channels)
    elsif id == "A_FLAC"
      codec = "flac"
      # "fLaC" then metadata blocks; STREAMINFO first (4-byte header + 34)
      extra = t.priv != nil && t.priv.size >= 42 ? dm_slice(t.priv, 8, 34) : nil
    elsif id == "A_MPEG/L3" || id == "A_MPEG/L2" || id == "A_MPEG/L1"
      codec = "mp3 "
    elsif id == "A_PCM/INT/LIT" || id == "A_PCM/INT/BIG" || id == "A_PCM/FLOAT/IEEE"
      codec = "pcm "
      extra = pcm_extra(t.bits, id == "A_PCM/FLOAT/IEEE", id == "A_PCM/INT/BIG")
    else
      codec = id
    cfg = CodecConfig.new(codec, extra)
    cfg.sample_rate = t.rate.to_i
    cfg.channels = t.channels
    cfg.codec_string = mp4a_codec_string(codec, extra)
    cfg

  -> parse_cues(s, e)
    @cues = [] if @cues == nil
    kids(s, e).each ->(cp)
      if cp[0] == 0xBB
        tm = nil
        pos = nil
        kids(cp[1], cp[1] + cp[2]).each ->(k)
          tm = uint(k[1], k[2]) if k[0] == 0xB3
          if k[0] == 0xB7
            kids(k[1], k[1] + k[2]).each ->(q)
              pos = uint(q[1], q[2]) if q[0] == 0xF1 && pos == nil
        @cues.push([tm * @tscale / 1000000, @seg_start + pos]) if tm != nil && pos != nil
    nil

  # Seek: the cluster of the last cue point at or before t (ms resolution).
  -> seek_offset(t)
    return nil if @cues == nil || @cues.size == 0
    ms = (t * ~1000.0).to_i
    best = @cues[0][1]
    @cues.each ->(c) best = c[1] if c[0] <= ms
    best

  -> cluster_child(id, s, n)
    if id == 0xE7
      @cluster_tc = uint(s, n)
    elsif id == 0xA3
      block(s, n, true, false, -1)
    elsif id == 0xA0
      blk = nil
      dur = -1
      ref = false
      kids(s, s + n).each ->(k)
        blk = k if k[0] == 0xA1
        dur = uint(k[1], k[2]) if k[0] == 0x9B
        ref = true if k[0] == 0xFB
      block(blk[1], blk[2], false, !ref, dur) if blk != nil
    nil

  # One (Simple)Block: track, relative timestamp, flags, laced frames.
  -> block(s, n, simple, key_bg, dur)
    tv = vint(s, false)
    return nil if tv == nil
    tnum = tv[0]
    t = @wtracks[tnum]
    return nil if t == nil
    p = s + tv[1]
    rel = @buf.be16(p)
    rel = rel - 65536 if rel >= 32768
    flags = @buf.u8(p + 2)
    p += 3
    e = s + n
    key = simple ? (flags & 0x80) != 0 : key_bg
    key = true if t.type == 2
    lacing = (flags >> 1) & 3
    sizes = []
    if lacing == 0
      sizes.push(e - p)
    else
      cnt = @buf.u8(p) + 1
      p += 1
      if lacing == 1
        i = 0
        tot = 0
        while i < cnt - 1
          v = 0
          b = 255
          while b == 255
            b = @buf.u8(p)
            p += 1
            v += b
          sizes.push(v)
          tot += v
          i += 1
        sizes.push(e - p - tot)
      elsif lacing == 2
        each = (e - p) / cnt
        i = 0
        while i < cnt
          sizes.push(each)
          i += 1
      else
        first = vint(p, false)
        p += first[1]
        sizes.push(first[0])
        tot = first[0]
        last = first[0]
        i = 1
        while i < cnt - 1
          d = vint(p, false)
          p += d[1]
          # signed: subtract the bias of a d[1]-byte vint
          bias = (1 << (7 * d[1] - 1)) - 1
          last = last + d[0] - bias
          sizes.push(last)
          tot += last
          i += 1
        sizes.push(e - p - tot)
    ts = (@cluster_tc + rel) * @tscale
    pts = (ts - t.delay).to_f / ~1.0e9
    fdur = t.default_dur > 0 ? t.default_dur.to_f / ~1.0e9 : ~0.0
    if dur >= 0 && sizes.size > 0
      fdur = (dur * @tscale).to_f / ~1.0e9 / sizes.size.to_f
    sizes.each_with_index ->(sz, i)
      if sz >= 0 && p + sz <= e
        data = nil
        if t.strip != nil
          data = ByteArray.new(t.strip.size + sz)
          dm_copy(data, 0, t.strip, 0, t.strip.size)
          dm_copy(data, t.strip.size, @buf.data, @buf.off(p), sz)
        else
          data = @buf.slice(p, sz)
        fp = pts + fdur * i.to_f
        emit(tnum, MediaSample.new(data, fp, fp, fdur, key && i == 0))
      p += sz
    nil

# Xiph-laced CodecPrivate (Vorbis / Theora headers) → Array of ByteArray.
-> xiph_split(b)
  return nil if b == nil || b.size < 1
  n = b[0] + 1
  p = 1
  sizes = []
  i = 0
  while i < n - 1
    v = 0
    c = 255
    while c == 255 && p < b.size
      c = b[p]
      p += 1
      v += c
    sizes.push(v)
    i += 1
  out = []
  sizes.each ->(sz)
    out.push(dm_slice(b, p, sz))
    p += sz
  out.push(dm_slice(b, p, b.size - p))
  out

# An AudioSpecificConfig for the legacy A_AAC/MPEG4/… codec ids.
-> aac_asc_for(id, rate, ch)
  obj = 2
  obj = 1 if id.index("MAIN") != nil
  obj = 3 if id.index("SSR") != nil
  obj = 4 if id.index("LTP") != nil
  rates = [96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350]
  idx = 4
  rates.each_with_index ->(r, i) idx = i if r == rate
  sbr = id.index("SBR") != nil
  if sbr
    # explicit HE-AAC: object 5, then the core at half the rate
    idx2 = idx
    rates.each_with_index ->(r, i) idx2 = i if r == rate / 2
    out = ByteArray.new(4)
    v = (5 << 27) | (idx2 << 23) | (ch << 19) | (idx << 15) | (2 << 10)
    out[0] = (v >> 24) & 255
    out[1] = (v >> 16) & 255
    out[2] = (v >> 8) & 255
    out[3] = v & 255
    return out
  out = ByteArray.new(2)
  v = (obj << 11) | (idx << 7) | (ch << 3)
  out[0] = v >> 8
  out[1] = v & 255
  out
