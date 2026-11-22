# core/codec/container/demux_ts — MPEG-2 Transport Stream (ISO/IEC 13818-1) demuxer: HLS
# segments, .ts / .m2ts files.
#
# 188-byte packets (and 192-byte M2TS/BDAV packets with a 4-byte timecode
# prefix); PAT → first program's PMT → elementary streams; PES reassembly
# with 33-bit PTS/DTS (unwrapped across the 2^33 rollover). Stream types:
#   0x1B H.264 ("h264", Annex B)      0x24 HEVC ("hvc1", Annex B)
#   0x0F AAC in ADTS ("mp4a")         0x03/0x04 MPEG-1/2 audio ("mp3 ")
#   0x81 / AC-3 descriptor: AC-3 ("ac-3")   0x87 / E-AC-3 descriptor: E-AC-3 ("ec-3")
#   0x06 private data with an AC-3 (0x6A) / E-AC-3 (0x7A) descriptor
# Audio PES payloads are split into codec frames (ADTS headers stripped, the
# AudioSpecificConfig built from the first header). Video samples are whole
# access units; keyframes are IDR / IRAP pictures (or the adaptation field's
# random_access_indicator). Times are relative to the first PTS of the
# stream (min over tracks), so a stream starts at 0 like an MP4; HLS feeds
# every segment through one demuxer so the timeline stays continuous.
# Not supported: SAMPLE-AES (0xDB/0xCF/0xC1), LATM AAC, MPEG-2 video, SCTE-35.

use core/codec/media
use demux
use core/codec/audio/aac

+ TsPes
  rw :pid, :stype, :codec, :kind, :track, :buf, :len, :pts, :dts, :rai, :first_pts, :last_pts, :cfg, :frac, :got

  -> new(@pid, @stype, @codec, @kind)
    @track = nil
    @buf = nil
    @len = 0
    @pts = nil
    @dts = nil
    @rai = false
    @first_pts = nil
    @last_pts = nil
    @cfg = nil
    @frac = 0
    @got = false

+ TsDemuxer < Demuxer
  -> new
    init_demuxer(:ts)
    @pos = 0
    @psize = 0
    @pmt_pid = -1
    @streams = {}
    @order = []
    @base = nil
    @pending = []      # [pid, sample] queued until the base time is known
    @seen = 0
    @wrap_ref = nil

  -> restart(off)
    @buf.reset(off)
    @pos = off
    @streams.each ->(k, st)
      st.buf = nil
      st.len = 0
      st.pts = nil
    nil

  -> parse
    return nil if @error != nil
    begin
      parse_packets()
    rescue e
      fail("ts: " + e.to_s)
    @buf.discard(@pos)
    nil

  -> finish
    parse
    @order.each ->(st) flush_pes(st)
    @ready = true if @tracks.size > 0
    release_pending(true)
    nil

  -> sync_size
    d = @buf.data
    o = @buf.off(@pos)
    lim = @buf.len
    k = 0
    while o + k + 392 <= lim && k < 1024
      if d[o + k] == 0x47 && d[o + k + 188] == 0x47
        @pos += k
        return 188
      if d[o + k] == 0x47 && d[o + k + 192] == 0x47 && k >= 4
        @pos += k - 4
        return 192
      k += 1
    0

  -> parse_packets
    if @psize == 0
      return nil if !@buf.has?(@pos, 400)
      @psize = sync_size()
      if @psize == 0
        fail("ts: no sync")
        return nil
    pre = @psize == 192 ? 4 : 0
    while @buf.has?(@pos, @psize)
      o = @buf.off(@pos) + pre
      d = @buf.data
      if d[o] != 0x47
        # resync
        k = 1
        found = false
        while !found && @buf.has?(@pos + k, @psize + 1)
          o2 = @buf.off(@pos + k) + pre
          if d[o2] == 0x47 && (!@buf.has?(@pos + k + @psize, pre + 1) || d[o2 + @psize] == 0x47)
            found = true
          else
            k += 1
        @pos += k
        next if found
        return nil
      packet(d, o)
      @pos += @psize
    nil

  -> packet(d, o)
    pusi = (d[o + 1] & 0x40) != 0
    pid = ((d[o + 1] & 0x1F) << 8) | d[o + 2]
    afc = (d[o + 3] >> 4) & 3
    p = o + 4
    e = o + 188
    rai = false
    if afc == 2 || afc == 3
      al = d[p]
      rai = al > 0 && (d[p + 1] & 0x40) != 0
      p += 1 + al
    return nil if afc == 1 && false
    return nil if (afc & 1) == 0 || p >= e
    if pid == 0
      psi_pat(d, p, e, pusi)
    elsif pid == @pmt_pid
      psi_pmt(d, p, e, pusi)
    else
      st = @streams[pid]
      return nil if st == nil
      if pusi
        flush_pes(st)
        st.buf = ByteArray.new(65536)
        st.len = 0
        st.rai = rai
      return nil if st.buf == nil
      n = e - p
      if st.len + n > st.buf.size
        nb = ByteArray.new(st.buf.size * 2 + n)
        dm_copy(nb, 0, st.buf, 0, st.len)
        st.buf = nb
      dm_copy(st.buf, st.len, d, p, n)
      st.len += n
      st.rai = true if rai
    nil

  -> psi_start(d, p, pusi)
    p += 1 + d[p] if pusi
    p

  -> psi_pat(d, p, e, pusi)
    return nil if !pusi || @pmt_pid >= 0
    p = psi_start(d, p, pusi)
    return nil if d[p] != 0
    slen = ((d[p + 1] & 0x0F) << 8) | d[p + 2]
    q = p + 8
    stop = p + 3 + slen - 4
    stop = e if stop > e
    while q + 4 <= stop
      prog = (d[q] << 8) | d[q + 1]
      pid = ((d[q + 2] & 0x1F) << 8) | d[q + 3]
      if prog != 0
        @pmt_pid = pid
        return nil
      q += 4
    nil

  -> psi_pmt(d, p, e, pusi)
    return nil if !pusi || @order.size > 0
    p = psi_start(d, p, pusi)
    return nil if d[p] != 2
    slen = ((d[p + 1] & 0x0F) << 8) | d[p + 2]
    stop = p + 3 + slen - 4
    stop = e if stop > e
    pil = ((d[p + 10] & 0x0F) << 8) | d[p + 11]
    q = p + 12 + pil
    while q + 5 <= stop
      stype = d[q]
      pid = ((d[q + 1] & 0x1F) << 8) | d[q + 2]
      eil = ((d[q + 3] & 0x0F) << 8) | d[q + 4]
      # descriptors: AC-3 / E-AC-3 in private streams
      desc_ac3 = false
      desc_eac3 = false
      r = q + 5
      while r + 2 <= q + 5 + eil && r + 2 <= stop
        tag = d[r]
        dl = d[r + 1]
        desc_ac3 = true if tag == 0x6A
        desc_eac3 = true if tag == 0x7A
        if tag == 0x05 && dl >= 4
          fmt = dm_fourcc(d, r + 2)
          desc_ac3 = true if fmt == "AC-3"
          desc_eac3 = true if fmt == "EAC3"
        r += 2 + dl
      codec = nil
      kind = :audio
      if stype == 0x1B
        codec = "h264"
        kind = :video
      elsif stype == 0x24
        codec = "hvc1"
        kind = :video
      elsif stype == 0x0F
        codec = "mp4a"
      elsif stype == 0x03 || stype == 0x04
        codec = "mp3 "
      elsif stype == 0x81 || (stype == 0x06 && desc_ac3)
        codec = "ac-3"
      elsif stype == 0x87 || (stype == 0x06 && desc_eac3)
        codec = "ec-3"
      if codec != nil && !@streams.has_key?(pid)
        st = TsPes.new(pid, stype, codec, kind)
        @streams[pid] = st
        @order.push(st)
      q += 5 + eil
    nil

  -> ts_time(d, o)
    ((d[o] >> 1) & 7) * 1073741824 + (d[o + 1] << 22) + ((d[o + 2] >> 1) << 15) + (d[o + 3] << 7) + (d[o + 4] >> 1)

  # Unwrap a 33-bit 90 kHz timestamp near the previous one.
  -> unwrap(t)
    if @wrap_ref != nil
      while t - @wrap_ref > 4294967296
        t -= 8589934592
      while @wrap_ref - t > 4294967296
        t += 8589934592
    @wrap_ref = t
    t

  -> flush_pes(st)
    return nil if st.buf == nil || st.len < 9
    b = st.buf
    n = st.len
    st.buf = nil
    st.len = 0
    return nil if b[0] != 0 || b[1] != 0 || b[2] != 1
    plen = (b[4] << 8) | b[5]
    flags = b[7]
    hl = b[8]
    pts = nil
    dts = nil
    if (flags & 0x80) != 0 && n >= 14
      pts = unwrap(ts_time(b, 9))
      dts = pts
      if (flags & 0x40) != 0 && n >= 19
        dts = unwrap(ts_time(b, 14))
    s = 9 + hl
    e = plen == 0 ? n : 6 + plen
    e = n if e > n
    return nil if s >= e
    if pts == nil
      pts = st.last_pts == nil ? 0 : st.last_pts
      dts = pts
    st.first_pts = pts if st.first_pts == nil
    st.last_pts = pts
    if st.kind == :video
      key = st.rai || ts_keyframe?(b, s, e, st.codec)
      if st.track == nil
        cfg = CodecConfig.new(st.codec)
        cfg.timescale = 90000
        cfg.codec_string = st.codec == "h264" ? "avc1" : "hvc1"
        st.cfg = cfg
        add_track(st)
      queue(st, MediaSample.new(dm_slice(b, s, e - s), pts.to_f / ~90000.0, dts.to_f / ~90000.0, ~0.0, key))
    else
      audio_frames(st, b, s, e, pts)
    nil

  -> add_track(st)
    t = MediaTrack.new(st.pid, st.kind, st.cfg)
    t.timescale = 90000
    st.track = t
    @tracks.push(t)
    nil

  # Split an audio PES payload into codec frames.
  -> audio_frames(st, b, s, e, pts)
    p = s
    t = pts.to_f / ~90000.0
    while p + 7 <= e
      if st.codec == "mp4a"
        if b[p] != 0xFF || (b[p + 1] & 0xF6) != 0xF0
          p += 1
          next
        prot_absent = b[p + 1] & 1
        prof = (b[p + 2] >> 6) & 3
        sfi = (b[p + 2] >> 2) & 15
        chc = ((b[p + 2] & 1) << 2) | ((b[p + 3] >> 6) & 3)
        flen = ((b[p + 3] & 3) << 11) | (b[p + 4] << 3) | ((b[p + 5] >> 5) & 7)
        nblk = (b[p + 6] & 3) + 1
        break if sfi >= 13 || flen < 7 || p + flen > e
        rate = AAC_RATES[sfi]
        if st.track == nil
          cfg = CodecConfig.new("mp4a", aac_make_asc(prof + 1, rate, chc))
          cfg.sample_rate = rate
          cfg.channels = chc == 7 ? 8 : chc
          cfg.timescale = rate
          cfg.codec_string = "mp4a.40." + (prof + 1).to_s
          st.cfg = cfg
          add_track(st)
        hl = prot_absent == 0 ? 9 : 7
        dur = (nblk * 1024).to_f / rate.to_f
        queue(st, MediaSample.new(dm_slice(b, p + hl, flen - hl), t, t, dur, true)) if flen > hl
        t += dur
        p += flen
      elsif st.codec == "mp3 "
        fi = ts_mpa_frame(b, p)
        if fi == nil
          p += 1
          next
        break if p + fi[0] > e
        if st.track == nil
          cfg = CodecConfig.new("mp3 ")
          cfg.sample_rate = fi[1]
          cfg.channels = fi[2]
          cfg.timescale = fi[1]
          cfg.codec_string = "mp3"
          st.cfg = cfg
          add_track(st)
        dur = fi[3].to_f / fi[1].to_f
        queue(st, MediaSample.new(dm_slice(b, p, fi[0]), t, t, dur, true))
        t += dur
        p += fi[0]
      else
        fi = ts_ac3_frame(b, p, e)
        if fi == nil
          p += 1
          next
        break if p + fi[0] > e
        # E-AC-3: dependent substreams (7.1 extensions) belong to the same sample
        flen = fi[0]
        while st.codec == "ec-3" && p + flen + 6 <= e && b[p + flen] == 0x0B && b[p + flen + 1] == 0x77 && (b[p + flen + 2] >> 6) == 1
          dl = ((((b[p + flen + 2] & 7) << 8) | b[p + flen + 3]) + 1) * 2
          break if p + flen + dl > e
          flen += dl
        fi[0] = flen
        if st.track == nil
          cfg = CodecConfig.new(st.codec)
          cfg.sample_rate = fi[1]
          cfg.channels = fi[2]
          cfg.timescale = fi[1]
          cfg.codec_string = st.codec
          st.cfg = cfg
          add_track(st)
        dur = fi[3].to_f / fi[1].to_f
        queue(st, MediaSample.new(dm_slice(b, p, fi[0]), t, t, dur, true))
        t += dur
        p += fi[0]
    nil

  # Samples wait until every stream has started, so the base time is the
  # earliest first PTS of all tracks.
  -> queue(st, s)
    st.got = true
    if @base != nil
      put(st, s)
      return nil
    @pending.push([st, s])
    release_pending(false)
    nil

  -> release_pending(force)
    return nil if @base != nil || @pending.size == 0
    all = @order.size > 0
    @order.each ->(st) all = false if !st.got
    return nil if !all && !force && @pending.size < 400
    b = nil
    @order.each ->(st)
      if st.first_pts != nil
        v = st.first_pts.to_f / ~90000.0
        b = v if b == nil || v < b
    @base = b == nil ? ~0.0 : b
    @ready = true
    pend = @pending
    @pending = []
    pend.each ->(x) put(x[0], x[1])
    nil

  -> put(st, s)
    s.pts = s.pts - @base
    s.dts = s.dts - @base
    emit(st.pid, s)
    nil

  # Bytes per second over what has been seen (for seek estimates by HLS).
  -> base_time
    @base

# Is this Annex B access unit a random access point?
-> ts_keyframe?(b, s, e, codec)
  p = s
  while p + 4 < e
    if b[p] == 0 && b[p + 1] == 0 && b[p + 2] == 1
      h = b[p + 3]
      if codec == "h264"
        t = h & 31
        return true if t == 5
      else
        t = (h >> 1) & 63
        return true if t >= 16 && t <= 23
      p += 3
    else
      p += 1
  false

TS_MPA_RATES = [[11025, 12000, 8000], [0, 0, 0], [22050, 24000, 16000], [44100, 48000, 32000]]
TS_MPA_BR = [[0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448], [0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384], [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320], [0, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256], [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160]]

# MPEG audio frame at p: [length, rate, channels, samples] or nil.
-> ts_mpa_frame(b, p)
  return nil if b[p] != 0xFF || (b[p + 1] & 0xE0) != 0xE0
  ver = (b[p + 1] >> 3) & 3
  layer = (b[p + 1] >> 1) & 3
  bri = b[p + 2] >> 4
  sri = (b[p + 2] >> 2) & 3
  pad = (b[p + 2] >> 1) & 1
  return nil if ver == 1 || layer == 0 || bri == 0 || bri == 15 || sri == 3
  rate = TS_MPA_RATES[ver][sri]
  lay = 4 - layer
  tab = 0
  if ver == 3
    tab = lay - 1
  else
    tab = lay == 1 ? 3 : 4
  br = TS_MPA_BR[tab][bri] * 1000
  ch = (b[p + 3] >> 6) == 3 ? 1 : 2
  if lay == 1
    return [(12 * br / rate + pad) * 4, rate, ch, 384]
  spf = (lay == 3 && ver != 3) ? 576 : 1152
  [spf / 8 * br / rate + pad, rate, ch, spf]

TS_AC3_RATES = [48000, 44100, 32000]
TS_AC3_SIZE = [64, 64, 80, 80, 96, 96, 112, 112, 128, 128, 160, 160, 192, 192, 224, 224, 256, 256, 320, 320, 384, 384, 448, 448, 512, 512, 640, 640, 768, 768, 896, 896, 1024, 1024, 1152, 1152, 1280, 1280]
TS_AC3_CH = [2, 1, 2, 3, 3, 4, 4, 5]

# AC-3 / E-AC-3 frame at p: [length, rate, channels, samples] or nil.
-> ts_ac3_frame(b, p, e)
  return nil if p + 7 > e || b[p] != 0x0B || b[p + 1] != 0x77
  bsid = b[p + 5] >> 3
  if bsid <= 10
    fscod = b[p + 4] >> 6
    frm = b[p + 4] & 63
    return nil if fscod == 3 || frm >= 38
    rate = TS_AC3_RATES[fscod]
    words = TS_AC3_SIZE[frm]
    words = TS_AC3_SIZE44[frm] if fscod == 1
    words = words * 3 / 2 if fscod == 2
    acmod = b[p + 6] >> 5
    # lfeon position depends on acmod's optional fields
    bits = 3
    bits += 2 if (acmod & 1) != 0 && acmod != 1
    bits += 2 if (acmod & 4) != 0
    bits += 2 if acmod == 2
    lfe = (((b[p + 6] << 8) | b[p + 7]) >> (15 - bits)) & 1
    return [words * 2, rate, TS_AC3_CH[acmod] + lfe, 1536]
  return nil if bsid < 11 || bsid > 16
  frmsiz = ((b[p + 2] & 7) << 8) | b[p + 3]
  fscod = b[p + 4] >> 6
  nblk = 6
  rate = 48000
  if fscod == 3
    fscod2 = (b[p + 4] >> 4) & 3
    rate = [24000, 22050, 16000, 0][fscod2]
  else
    rate = TS_AC3_RATES[fscod]
    nblk = [1, 2, 3, 6][(b[p + 4] >> 4) & 3]
  acmod = (b[p + 4] >> 1) & 7
  lfe = b[p + 4] & 1
  return nil if rate == 0
  [(frmsiz + 1) * 2, rate, TS_AC3_CH[acmod] + lfe, nblk * 256]

# 44.1 kHz AC-3 frame sizes in 16-bit words (frmsizecod 0..37).
TS_AC3_SIZE44 = [69, 70, 87, 88, 104, 105, 121, 122, 139, 140, 174, 175, 208, 209, 243, 244, 278, 279, 348, 349, 417, 418, 487, 488, 557, 558, 696, 697, 835, 836, 975, 976, 1114, 1115, 1253, 1254, 1393, 1394]
