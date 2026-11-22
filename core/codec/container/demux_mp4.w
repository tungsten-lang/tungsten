# core/codec/container/demux_mp4 — ISO BMFF (MP4, M4A, MOV, fragmented MP4 / CMAF, DASH and
# MSE segments).
#
# moov: tkhd/mdhd/hdlr, stsd sample entries (avc1/avc3, hvc1/hev1, av01, vp09,
# vp08, mp4a+esds, Opus+dOps, fLaC+dfLa, .mp3, ipcm/lpcm/sowt/twos), colr/nclx,
# stts/ctts/stss/stsz/stz2/stsc/stco/co64, edts/elst, mvex/trex/mehd.
# Fragments: moof/mfhd/traf/tfhd/tfdt/trun (all flag combinations, signed
# composition offsets), sidx (kept as a seek index). Samples are emitted in
# file order as their bytes arrive, so a progressive download plays while it
# loads; a non-fragmented file whose moov follows mdat asks the loader for the
# moov (want_offset) and then for the mdat again.

use core/codec/media
use demux

+ Mp4Trak
  rw :id, :kind, :cfg, :timescale, :handler, :edit_shift, :entries, :next, :width, :height
  rw :trex_dur, :trex_size, :trex_flags, :decode_time, :media_dur, :lang

  -> new
    @id = 0
    @kind = nil
    @cfg = nil
    @timescale = 1000
    @handler = ""
    @edit_shift = 0
    @entries = nil
    @next = 0
    @width = 0
    @height = 0
    @trex_dur = 0
    @trex_size = 0
    @trex_flags = 0
    @decode_time = 0
    @media_dur = 0
    @lang = nil

+ Mp4Demuxer < Demuxer
  ro :sidx

  -> new
    init_demuxer(:mp4)
    @pos = 0             # absolute offset of the next top-level box
    @traks = {}
    @movie_ts = 1000
    @moov = false
    @pending = []        # [abs offset, size, track id, pts, dts, dur, key] in file order
    @pi = 0
    @mdat_skipped = nil  # [start, end] of an mdat seen before the moov
    @sidx = nil          # [[offset, pts seconds, duration], …] from the first sidx
    @frag_dur = nil
    @fragmented = false

  -> parse
    return nil if @error != nil
    begin
      parse_boxes()
      emit_ready()
    rescue e
      fail("mp4: " + e.to_s)
    nil

  -> parse_boxes
    while @buf.has?(@pos, 8)
      size = @buf.be32(@pos)
      typ = dm_fourcc(@buf.data, @buf.off(@pos) + 4)
      hdr = 8
      if size == 1
        return nil if !@buf.has?(@pos, 16)
        size = @buf.be64(@pos + 8)
        hdr = 16
      elsif size == 0
        size = -1
      if size != -1 && size < hdr
        fail("bad box size")
        return nil
      if typ == "mdat"
        if !@moov
          # moov comes later: remember where this mdat is and ask for the bytes after it
          if size == -1
            fail("mdat to end of file before moov")
            return nil
          @mdat_skipped = [@pos, @pos + size] if @mdat_skipped == nil
          @want_offset = @pos + size
          @pos = @pos + size
          return nil
        # samples are read out of it by offset; just step over the header
        @pos = size == -1 ? @pos + hdr + (1 << 60) : @pos + size
        next
      if typ == "moov" || typ == "moof" || typ == "sidx" || typ == "ftyp" || typ == "styp" || typ == "mvex" || typ == "emsg"
        return nil if size == -1 || !@buf.has?(@pos, size)
        body = @pos + hdr
        bend = @pos + size
        if typ == "moov"
          parse_moov(body, bend)
        elsif typ == "moof"
          parse_moof(@pos, body, bend)
        elsif typ == "sidx"
          parse_sidx(body, bend) if @sidx == nil
        @pos = bend
        next
      # anything else (free, skip, uuid, meta, prft …): skip
      return nil if size == -1
      @pos = @pos + size
    nil

  # Emit samples whose bytes are buffered, in file order; drop consumed bytes.
  -> emit_ready
    while @pi < @pending.size
      p = @pending[@pi]
      break if !@buf.has?(p[0], p[1])
      s = MediaSample.new(@buf.slice(p[0], p[1]), p[3], p[4], p[5], p[6])
      emit(p[2], s)
      @pi += 1
    if @pi >= @pending.size
      @pending = []
      @pi = 0
    elsif @pi > 4096
      @pending = @pending.copy(@pi, @pending.size - @pi)
      @pi = 0
    keep = @pos
    keep = @pending[@pi][0] if @pi < @pending.size && @pending[@pi][0] < keep
    keep = @mdat_skipped[0] if @mdat_skipped != nil && @mdat_skipped[0] < keep
    @buf.discard(keep)
    nil

  # ---- boxes ----

  # Children of [s, e): Array of [type, body start, end].
  -> children(s, e)
    out = []
    p = s
    while p + 8 <= e
      size = @buf.be32(p)
      typ = dm_fourcc(@buf.data, @buf.off(p) + 4)
      hdr = 8
      if size == 1
        size = @buf.be64(p + 8)
        hdr = 16
      elsif size == 0
        size = e - p
      break if size < hdr || p + size > e
      out.push([typ, p + hdr, p + size])
      p += size
    out

  -> child(s, e, typ)
    children(s, e).each ->(c)
      return c if c[0] == typ
    nil

  -> parse_moov(s, e)
    return nil if @moov
    @moov = true
    children(s, e).each ->(c)
      if c[0] == "mvhd"
        v = @buf.u8(c[1])
        if v == 1
          @movie_ts = @buf.be32(c[1] + 20)
          d = @buf.be64(c[1] + 24)
        else
          @movie_ts = @buf.be32(c[1] + 12)
          d = @buf.be32(c[1] + 16)
        @duration = d.to_f / @movie_ts.to_f if @movie_ts > 0 && d > 0 && d != 0xFFFFFFFF
      elsif c[0] == "trak"
        parse_trak(c[1], c[2])
      elsif c[0] == "mvex"
        parse_mvex(c[1], c[2])
    @ready = true
    if @mdat_skipped != nil
      # the media comes before the moov: read it again now
      @want_offset = @mdat_skipped[0]
      @mdat_skipped = nil
    else
      @want_offset = nil
    nil

  -> parse_mvex(s, e)
    @fragmented = true
    children(s, e).each ->(c)
      if c[0] == "trex"
        t = @traks[@buf.be32(c[1] + 4)]
        if t != nil
          t.trex_dur = @buf.be32(c[1] + 12)
          t.trex_size = @buf.be32(c[1] + 16)
          t.trex_flags = @buf.be32(c[1] + 20)
      elsif c[0] == "mehd"
        v = @buf.u8(c[1])
        d = v == 1 ? @buf.be64(c[1] + 4) : @buf.be32(c[1] + 4)
        @duration = d.to_f / @movie_ts.to_f if d > 0
    nil

  -> parse_trak(s, e)
    t = Mp4Trak.new
    edts = nil
    children(s, e).each ->(c)
      if c[0] == "tkhd"
        v = @buf.u8(c[1])
        t.id = v == 1 ? @buf.be32(c[1] + 20) : @buf.be32(c[1] + 12)
        wo = v == 1 ? c[1] + 88 : c[1] + 76
        t.width = @buf.be32(wo) >> 16
        t.height = @buf.be32(wo + 4) >> 16
      elsif c[0] == "edts"
        edts = c
      elsif c[0] == "mdia"
        parse_mdia(t, c[1], c[2])
    return nil if t.kind == nil
    # edit list: an empty first edit delays the track; the media edit's start trims it
    if edts != nil
      el = child(edts[1], edts[2], "elst")
      if el != nil
        v = @buf.u8(el[1])
        n = @buf.be32(el[1] + 4)
        p = el[1] + 8
        delay = 0
        mt = 0
        i = 0
        found = false
        while i < n && !found
          if v == 1
            sd = @buf.be64(p)
            m = @buf.be64(p + 8)
            p += 20
          else
            sd = @buf.be32(p)
            m = dm_s32(@buf.be32(p + 4))
            p += 12
          if m == -1 || m == 0xFFFFFFFFFFFFFFFF
            delay += sd
          else
            mt = m
            found = true
          i += 1
        # shift in media timescale units: pts = cts + shift
        t.edit_shift = (delay * t.timescale / (@movie_ts > 0 ? @movie_ts : 1)) - mt
    if t.edit_shift != 0 && t.entries != nil
      sh = t.edit_shift.to_f / t.timescale.to_f
      t.entries.each ->(en)
        en[3] = en[3] + sh
        en[4] = en[4] + sh
    @traks[t.id] = t
    mt = MediaTrack.new(t.id, t.kind, t.cfg)
    mt.timescale = t.timescale
    mt.lang = t.lang
    mt.duration = t.media_dur > 0 ? t.media_dur.to_f / t.timescale.to_f : nil
    @tracks.push(mt)
    # a complete sample table (non-fragmented file): queue every sample by offset
    if t.entries != nil && t.entries.size > 0
      t.entries.each ->(en)
        @pending.push(en)
      @pending = @pending.sort_by(->(x) x[0])
    nil

  -> parse_mdia(t, s, e)
    minf = nil
    children(s, e).each ->(c)
      if c[0] == "mdhd"
        v = @buf.u8(c[1])
        if v == 1
          t.timescale = @buf.be32(c[1] + 20)
          t.media_dur = @buf.be64(c[1] + 24)
          lo = c[1] + 32
        else
          t.timescale = @buf.be32(c[1] + 12)
          t.media_dur = @buf.be32(c[1] + 16)
          lo = c[1] + 20
        t.timescale = 1000 if t.timescale <= 0
        l = @buf.be16(lo)
        if l != 0 && l != 0x7FFF && l != 0x55C4
          t.lang = (((l >> 10) & 31) + 0x60).chr + (((l >> 5) & 31) + 0x60).chr + ((l & 31) + 0x60).chr
      elsif c[0] == "hdlr"
        t.handler = dm_fourcc(@buf.data, @buf.off(c[1]) + 8)
      elsif c[0] == "minf"
        minf = c
    t.kind = :video if t.handler == "vide"
    t.kind = :audio if t.handler == "soun"
    return nil if t.kind == nil || minf == nil
    stbl = child(minf[1], minf[2], "stbl")
    parse_stbl(t, stbl[1], stbl[2]) if stbl != nil
    nil

  -> parse_stbl(t, s, e)
    cs = children(s, e)
    stts = nil
    ctts = nil
    stss = nil
    stsz = nil
    stz2 = nil
    stsc = nil
    stco = nil
    co64 = nil
    cs.each ->(c)
      case c[0]
      when "stsd"
        parse_stsd(t, c[1], c[2])
      when "stts"
        stts = c
      when "ctts"
        ctts = c
      when "stss"
        stss = c
      when "stsz"
        stsz = c
      when "stz2"
        stz2 = c
      when "stsc"
        stsc = c
      when "stco"
        stco = c
      when "co64"
        co64 = c
    return nil if t.cfg == nil
    # sizes
    sizes = []
    if stsz != nil
      fixed = @buf.be32(stsz[1] + 4)
      n = @buf.be32(stsz[1] + 8)
      i = 0
      while i < n
        sizes.push(fixed != 0 ? fixed : @buf.be32(stsz[1] + 12 + i * 4))
        i += 1
    elsif stz2 != nil
      fs = @buf.u8(stz2[1] + 7)
      n = @buf.be32(stz2[1] + 8)
      i = 0
      while i < n
        if fs == 16
          sizes.push(@buf.be16(stz2[1] + 12 + i * 2))
        elsif fs == 8
          sizes.push(@buf.u8(stz2[1] + 12 + i))
        else
          b = @buf.u8(stz2[1] + 12 + i / 2)
          sizes.push(i % 2 == 0 ? b >> 4 : b & 15)
        i += 1
    n = sizes.size
    return nil if n == 0
    # chunk offsets
    chunks = []
    if stco != nil
      k = @buf.be32(stco[1] + 4)
      i = 0
      while i < k
        chunks.push(@buf.be32(stco[1] + 8 + i * 4))
        i += 1
    elsif co64 != nil
      k = @buf.be32(co64[1] + 4)
      i = 0
      while i < k
        chunks.push(@buf.be64(co64[1] + 8 + i * 8))
        i += 1
    # sample → offset through stsc
    offs = Array.new(n, 0)
    if stsc != nil && chunks.size > 0
      ne = @buf.be32(stsc[1] + 4)
      si = 0
      j = 0
      while j < ne && si < n
        first = @buf.be32(stsc[1] + 8 + j * 12) - 1
        per = @buf.be32(stsc[1] + 12 + j * 12)
        last = j + 1 < ne ? @buf.be32(stsc[1] + 8 + (j + 1) * 12) - 1 : chunks.size
        ch = first
        while ch < last && ch < chunks.size && si < n
          o = chunks[ch]
          q = 0
          while q < per && si < n
            offs[si] = o
            o += sizes[si]
            si += 1
            q += 1
          ch += 1
        j += 1
    # decode times
    dts = Array.new(n, 0)
    durs = Array.new(n, 0)
    if stts != nil
      ne = @buf.be32(stts[1] + 4)
      si = 0
      tcur = 0
      j = 0
      while j < ne && si < n
        cnt = @buf.be32(stts[1] + 8 + j * 8)
        d = @buf.be32(stts[1] + 12 + j * 8)
        q = 0
        while q < cnt && si < n
          dts[si] = tcur
          durs[si] = d
          tcur += d
          si += 1
          q += 1
        j += 1
    cto = nil
    if ctts != nil
      cto = Array.new(n, 0)
      ne = @buf.be32(ctts[1] + 4)
      si = 0
      j = 0
      while j < ne && si < n
        cnt = @buf.be32(ctts[1] + 8 + j * 8)
        o = dm_s32(@buf.be32(ctts[1] + 12 + j * 8))
        q = 0
        while q < cnt && si < n
          cto[si] = o
          si += 1
          q += 1
        j += 1
    keys = nil
    if stss != nil
      keys = Array.new(n, false)
      ne = @buf.be32(stss[1] + 4)
      j = 0
      while j < ne
        k = @buf.be32(stss[1] + 8 + j * 4) - 1
        keys[k] = true if k >= 0 && k < n
        j += 1
    t.entries = []
    ts = t.timescale.to_f
    i = 0
    while i < n
      c = dts[i] + (cto == nil ? 0 : cto[i])
      t.entries.push([offs[i], sizes[i], t.id, c.to_f / ts, dts[i].to_f / ts, durs[i].to_f / ts, keys == nil ? true : keys[i]])
      i += 1
    nil

  -> parse_stsd(t, s, e)
    n = @buf.be32(s + 4)
    return nil if n < 1
    p = s + 8
    size = @buf.be32(p)
    typ = dm_fourcc(@buf.data, @buf.off(p) + 4)
    es = p + 8
    ee = p + size
    ee = e if ee > e
    if t.kind == :video
      parse_visual(t, typ, es, ee)
    else
      parse_audio(t, typ, es, ee)
    nil

  -> parse_visual(t, typ, s, e)
    codec = nil
    codec = "avc1" if typ == "avc1" || typ == "avc3"
    codec = "hvc1" if typ == "hvc1" || typ == "hev1"
    codec = "av01" if typ == "av01"
    codec = "vp09" if typ == "vp09"
    codec = "vp08" if typ == "vp08"
    if typ == "encv"
      fail("encrypted video (encv) is not supported")
      return nil
    codec = typ if codec == nil
    cfg = CodecConfig.new(codec)
    cfg.width = @buf.be16(s + 24)
    cfg.height = @buf.be16(s + 26)
    cfg.timescale = t.timescale
    children(s + 78, e).each ->(c)
      ty = c[0]
      if ty == "avcC" || ty == "hvcC" || ty == "av1C" || ty == "vpcC"
        cfg.extra = @buf.slice(c[1], c[2] - c[1])
        cfg.codec_string = mp4_codec_string(codec, cfg.extra)
      elsif ty == "colr" && c[2] - c[1] >= 11
        ct = dm_fourcc(@buf.data, @buf.off(c[1]))
        if ct == "nclx" || ct == "nclc"
          cfg.primaries = @buf.be16(c[1] + 4)
          cfg.transfer = @buf.be16(c[1] + 6)
          cfg.matrix = @buf.be16(c[1] + 8)
          cfg.full_range = ct == "nclx" ? (@buf.u8(c[1] + 10) & 0x80) != 0 : false
    t.cfg = cfg
    nil

  -> parse_audio(t, typ, s, e)
    if typ == "enca"
      fail("encrypted audio (enca) is not supported")
      return nil
    ver = @buf.be16(s + 8)
    ch = @buf.be16(s + 16)
    bits = @buf.be16(s + 18)
    rate = @buf.be32(s + 24) >> 16
    kids = s + 28
    if ver == 1
      kids = s + 44
    elsif ver == 2
      rate = dm_f64_bits(@buf.be64(s + 32)).to_i
      ch = @buf.be32(s + 40)
      bits = @buf.be32(s + 48)
      kids = s + 64
    codec = nil
    extra = nil
    if typ == "mp4a"
      codec = "mp4a"
      esds = child(kids, e, "esds")
      if esds == nil
        wave = child(kids, e, "wave")
        esds = child(wave[1], wave[2], "esds") if wave != nil
      if esds != nil
        r = mp4_esds(esds[1] + 4, esds[2])
        codec = r[0]
        extra = r[1]
    elsif typ == "Opus"
      codec = "opus"
      d = child(kids, e, "dOps")
      extra = mp4_dops_to_opushead(d[1], d[2]) if d != nil
    elsif typ == "fLaC"
      codec = "flac"
      d = child(kids, e, "dfLa")
      # full box, then metadata blocks; the first is STREAMINFO (4-byte header + 34)
      extra = @buf.slice(d[1] + 8, 34) if d != nil && d[2] - d[1] >= 42
    elsif typ == ".mp3" || typ == "mp3 "
      codec = "mp3 "
    elsif typ == "alac"
      codec = "alac"
      d = child(kids, e, "alac")
      # full box (version/flags), then the 24-byte ALACSpecificConfig
      extra = @buf.slice(d[1] + 4, 24) if d != nil && d[2] - d[1] >= 28
    elsif typ == "ipcm" || typ == "lpcm" || typ == "sowt" || typ == "twos" || typ == "fpcm" || typ == "raw " || typ == "in24" || typ == "in32" || typ == "fl32" || typ == "fl64"
      codec = "pcm "
      be = typ == "twos" || typ == "in24" || typ == "in32" || typ == "fl32" || typ == "fl64"
      fl = typ == "fl32" || typ == "fl64" || typ == "fpcm"
      bb = bits
      bb = 24 if typ == "in24"
      bb = 32 if typ == "in32" || typ == "fl32"
      bb = 64 if typ == "fl64"
      bb = 8 if typ == "raw "
      pc = child(kids, e, "pcmC")
      if pc != nil
        be = (@buf.u8(pc[1] + 4) & 1) == 0
        bb = @buf.u8(pc[1] + 5)
      extra = pcm_extra(bb, fl, be)
    else
      codec = typ
    cfg = CodecConfig.new(codec, extra)
    cfg.sample_rate = rate
    cfg.channels = ch
    cfg.timescale = t.timescale
    cfg.codec_string = mp4a_codec_string(codec, extra)
    t.cfg = cfg
    nil

  # esds (after the full-box header): [codec id, DecoderSpecificInfo bytes or nil].
  -> mp4_esds(s, e)
    p = s
    codec = "mp4a"
    extra = nil
    while p < e
      tag = @buf.u8(p)
      p += 1
      len = 0
      k = 0
      more = true
      while more && k < 4 && p < e
        b = @buf.u8(p)
        p += 1
        len = (len << 7) | (b & 0x7F)
        more = (b & 0x80) != 0
        k += 1
      if tag == 3
        flags = @buf.u8(p + 2)
        p += 3
        p += 2 if (flags & 0x80) != 0
        p += 1 + @buf.u8(p) if (flags & 0x40) != 0
        p += 2 if (flags & 0x20) != 0
      elsif tag == 4
        oti = @buf.u8(p)
        codec = "mp3 " if oti == 0x69 || oti == 0x6B
        p += 13
      elsif tag == 5
        extra = @buf.slice(p, len)
        p = e
      else
        p += len
    [codec, extra]

  # dOps (big-endian, version 0) → an OpusHead packet (little-endian).
  -> mp4_dops_to_opushead(s, e)
    n = e - s
    out = ByteArray.new(19 + (n > 11 ? n - 11 : 0))
    magic = "OpusHead"
    i = 0
    while i < 8
      out[i] = magic.byte_at(i)
      i += 1
    out[8] = 1
    out[9] = @buf.u8(s + 1)
    ps = @buf.be16(s + 2)
    out[10] = ps & 255
    out[11] = ps >> 8
    r = @buf.be32(s + 4)
    out[12] = r & 255
    out[13] = (r >> 8) & 255
    out[14] = (r >> 16) & 255
    out[15] = (r >> 24) & 255
    g = @buf.be16(s + 8)
    out[16] = g & 255
    out[17] = g >> 8
    out[18] = @buf.u8(s + 10)
    i = 11
    while i < n
      out[19 + i - 11] = @buf.u8(s + i)
      i += 1
    out

  # ---- fragments ----

  -> parse_moof(moof_start, s, e)
    @fragmented = true
    children(s, e).each ->(c)
      parse_traf(moof_start, c[1], c[2]) if c[0] == "traf"
    @pending = @pending.sort_by(->(x) x[0]) if @pending.size - @pi > 1 && @tracks.size > 1
    nil

  -> parse_traf(moof_start, s, e)
    tf = child(s, e, "tfhd")
    return nil if tf == nil
    flags = @buf.be24(tf[1] + 1)
    tid = @buf.be32(tf[1] + 4)
    t = @traks[tid]
    return nil if t == nil
    p = tf[1] + 8
    base = moof_start
    if (flags & 1) != 0
      base = @buf.be64(p)
      p += 8
    p += 4 if (flags & 2) != 0
    ddur = t.trex_dur
    dsize = t.trex_size
    dflags = t.trex_flags
    if (flags & 8) != 0
      ddur = @buf.be32(p)
      p += 4
    if (flags & 0x10) != 0
      dsize = @buf.be32(p)
      p += 4
    if (flags & 0x20) != 0
      dflags = @buf.be32(p)
      p += 4
    td = child(s, e, "tfdt")
    if td != nil
      t.decode_time = @buf.u8(td[1]) == 1 ? @buf.be64(td[1] + 4) : @buf.be32(td[1] + 4)
    ts = t.timescale.to_f
    data_end = base
    children(s, e).each ->(c)
      if c[0] == "trun"
        v = @buf.u8(c[1])
        rf = @buf.be24(c[1] + 1)
        cnt = @buf.be32(c[1] + 4)
        q = c[1] + 8
        off = data_end
        if (rf & 1) != 0
          off = base + dm_s32(@buf.be32(q))
          q += 4
        first_flags = nil
        if (rf & 4) != 0
          first_flags = @buf.be32(q)
          q += 4
        i = 0
        while i < cnt
          d = ddur
          sz = dsize
          fl = dflags
          co = 0
          if (rf & 0x100) != 0
            d = @buf.be32(q)
            q += 4
          if (rf & 0x200) != 0
            sz = @buf.be32(q)
            q += 4
          if (rf & 0x400) != 0
            fl = @buf.be32(q)
            q += 4
          elsif i == 0 && first_flags != nil
            fl = first_flags
          if (rf & 0x800) != 0
            co = @buf.be32(q)
            co = dm_s32(co) if v == 1 || co >= 0x80000000
            q += 4
          fl = first_flags if i == 0 && first_flags != nil
          key = t.kind == :audio || (fl & 0x10000) == 0
          dt = t.decode_time
          pt = dt + co + t.edit_shift
          @pending.push([off, sz, tid, pt.to_f / ts, (dt + t.edit_shift).to_f / ts, d.to_f / ts, key])
          off += sz
          t.decode_time = dt + d
          i += 1
        data_end = off
    nil

  -> parse_sidx(s, e)
    v = @buf.u8(s)
    ts = @buf.be32(s + 8)
    p = s + 12
    if v == 0
      ept = @buf.be32(p)
      first = @buf.be32(p + 4)
      p += 8
    else
      ept = @buf.be64(p)
      first = @buf.be64(p + 8)
      p += 16
    n = @buf.be16(p + 2)
    p += 4
    off = e + first
    tcur = ept
    @sidx = []
    i = 0
    while i < n
      r = @buf.be32(p)
      d = @buf.be32(p + 4)
      size = r & 0x7FFFFFFF
      @sidx.push([off, tcur.to_f / ts.to_f, d.to_f / ts.to_f, size])
      off += size
      tcur += d
      p += 12
      i += 1
    tot = tcur - ept
    @duration = (ept + tot).to_f / ts.to_f if @duration == nil && ts > 0
    nil

  # Byte offset to load from to play from t: a sidx entry, or the sample
  # table's keyframe at or before t (the earliest across tracks).
  -> seek_offset(t)
    if @sidx != nil && @sidx.size > 0
      best = @sidx[0][0]
      @sidx.each ->(x) best = x[0] if x[1] <= t + 0.000001
      return best
    best = nil
    @traks.each ->(id, tr)
      if tr.entries != nil && tr.entries.size > 0
        cand = tr.entries[0][0]
        tr.entries.each ->(en)
          cand = en[0] if en[6] && en[3] <= t + 0.000001
        best = cand if best == nil || cand < best
    best

  # Re-queue a non-fragmented file's samples from offset off on (after a seek).
  -> restart(off)
    @buf.reset(off)
    @want_offset = nil
    @pending = []
    @pi = 0
    if !@fragmented
      @traks.each ->(id, tr)
        if tr.entries != nil
          tr.entries.each ->(en)
            @pending.push(en) if en[0] >= off
      @pending = @pending.sort_by(->(x) x[0])
      # top-level parsing resumes past the moov: skip to the end of what we know
      @pos = off
    else
      @pos = off
    nil

# RFC 6381 codec string from a decoder configuration record.
-> mp4_codec_string(codec, x)
  return codec if x == nil || x.size < 4
  hx = ->(v) (v < 16 ? "0" : "") + v.to_s(16)
  return "avc1." + hx.call(x[1]) + hx.call(x[2]) + hx.call(x[3]) if codec == "avc1"
  if codec == "vp09" && x.size >= 8
    return "vp09." + (x[4] < 10 ? "0" : "") + x[4].to_s + "." + (x[5] < 10 ? "0" : "") + x[5].to_s + "." + ((x[6] >> 4) < 10 ? "0" : "") + (x[6] >> 4).to_s
  if codec == "av01"
    prof = (x[1] >> 5) & 7
    lvl = x[1] & 31
    tier = (x[2] >> 7) == 1 ? "H" : "M"
    hb = (x[2] >> 6) & 1
    tw = (x[2] >> 5) & 1
    bd = hb == 1 ? (prof == 2 && tw == 1 ? 12 : 10) : 8
    return "av01." + prof.to_s + "." + (lvl < 10 ? "0" : "") + lvl.to_s + tier + "." + (bd < 10 ? "0" : "") + bd.to_s
  codec
