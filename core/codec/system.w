# core/codec/system — the operating system's decoders (macOS: VideoToolbox
# for H.264 / HEVC, AudioToolbox for AAC, HE-AAC v1/v2, xHE-AAC, AC-3,
# E-AC-3) behind core/codec's decoder contract, as an alternative to the
# pure-Tungsten decoders.
#
#   use core/codec/system
#   dec = SysVideoDec.new(cfg)        # same API as Codec.video(cfg): decode / flush / reset
#   dec = SysAudioDec.new(cfg)        # same API as Codec.audio(cfg)
#   Codec.prefer_system(["avc1", "hvc1", "mp4a", "ec-3"])   # registry picks these first
#
# Policy (core/codec/media): Codec.video / Codec.audio use our decoders
# unless the codec id is in the system preference list (Codec.prefer_system,
# or the environment: TUNGSTEN_CODEC_SYSTEM=avc1,hvc1,… / "patent" for the
# patent-pool set SYS_PATENT_CODECS / "all" / "0" for none). A preferred
# system decoder that cannot be created (unsupported profile, no
# VideoToolbox) falls back to ours, and a codec only the system decodes goes
# to the system.
#
# Frames: SysVideoDec returns VideoFrames with planes copied out of the
# CVPixelBuffer (NV12 / P010 de-interleaved into Y, Cb, Cr; owned: true).
# Audio: AudioBlocks of interleaved f32 in WAVE channel order, at the rate
# AudioToolbox decodes to (the SBR rate for HE-AAC, stereo for HE-AAC v2).
#
# Measurement helper: sys_rusage → {user:, sys:, max_rss:, now:} (seconds,
# bytes) for benchmarks.

use core/codec/media

-> sys_rusage
  r = ccall("w_media_sys_rusage")
  {user: r[0], sys: r[1], max_rss: r[2], now: r[3]}

# ---- video ----

+ SysVideoDec
  ro :handle, :hevc, :bits

  -> new(cfg)
    c = cfg.codec
    @hevc = c == "hvc1" || c == "hev1"
    raise MediaError.new("system decoder: unsupported video codec " + c) if !@hevc && c != "avc1" && c != "avc3"
    @bits = 8
    if @hevc && cfg.extra != nil && cfg.extra.size > 20
      # hvcC: bitDepthLumaMinus8 in byte 19 (low 3 bits)
      @bits = (cfg.extra[19] & 7) + 8
    @cfg = cfg
    @colour = sys_video_colour(cfg, @hevc)
    @handle = ccall("w_media_vtdec_new", c, cfg.extra, [cfg.width, cfg.height, @bits, 1, 0])
    @durs = {}
    @frames = 0
    @spare = nil

  -> hw?
    ccall("w_media_vtdec_info", @handle, "hw")

  -> errors
    ccall("w_media_vtdec_info", @handle, "errors")

  -> decode(sample)
    us = (sample.pts * 1000000.0).round
    @durs[us] = sample.duration
    ccall("w_media_vtdec_decode", @handle, sample.data, us, sys_dts_us(sample))
    take(false)

  -> flush
    take(true)

  # decode / flush without copying the pictures out (benchmarks): returns
  # the presentation times of the frames that came out
  -> decode_drop(sample)
    us = (sample.pts * 1000000.0).round
    ccall("w_media_vtdec_decode", @handle, sample.data, us, sys_dts_us(sample))
    drain(false)

  -> flush_drop
    drain(true)

  -> drain(fl)
    out = []
    r = ccall("w_media_vtdec_take", @handle, fl, nil)
    while r != nil
      out.push(r[0] / 1000000.0)
      r = ccall("w_media_vtdec_take", @handle, false, nil)
    out

  -> reset
    ccall("w_media_vtdec_reset", @handle)
    @durs = {}

  -> close
    ccall("w_media_vtdec_close", @handle)
    if @spare != nil
      @spare.each ->(p) ccall("w_value_free_w", p)
    @spare = nil

  -> take(fl)
    out = []
    more = true
    while more
      f = take_one(fl)
      if f == nil
        more = false
      else
        out.push(f)
    out

  # One frame (nil when none is ready). Planes are allocated for the frame.
  -> take_one(fl)
    w = @cfg.width
    h = @cfg.height
    # planes for the next frame, kept until a frame takes them
    @spare = sys_planes(w, h, @bits) if @spare == nil && w > 0 && h > 0
    planes = @spare
    r = ccall("w_media_vtdec_take", @handle, fl, planes)
    return nil if r == nil
    @spare = nil
    if r[1] != w || r[2] != h
      # the container's size was wrong or missing: this frame is lost, the
      # next ones come at the real size
      if planes != nil
        planes.each ->(p) ccall("w_value_free_w", p)
      @cfg.width = r[1]
      @cfg.height = r[2]
      return nil
    pts = r[0] / 1000000.0
    cw = (w + 1) / 2
    f = VideoFrame.new(w, h, planes, [w, cw, cw], "420", @bits, pts)
    f.owned = true
    d = @durs.delete(r[0])
    f.duration = d if d != nil
    f.primaries = @colour[0]
    f.transfer = @colour[1]
    f.matrix = @colour[2]
    f.full_range = @colour[3]
    @frames += 1
    f

-> sys_dts_us(sample)
  return nil if sample.dts == nil
  (sample.dts * 1000000.0).round

-> sys_planes(w, h, bits)
  cw = (w + 1) / 2
  ch = (h + 1) / 2
  return [u16[w * h], u16[cw * ch], u16[cw * ch]] if bits > 8
  [u8[w * h], u8[cw * ch], u8[cw * ch]]

# [primaries, transfer, matrix, full_range] from the stream's VUI, else the
# container, else BT.709 (BT.601 below 720 lines, as our decoders do).
-> sys_video_colour(cfg, hevc)
  p = cfg.primaries
  t = cfg.transfer
  m = cfg.matrix
  fr = cfg.full_range == true
  begin
    v = {}
    ccall("w_media_parse_sps", cfg.extra, hevc).each ->(kv)
      v[kv[0]] = kv[1]
    if v["ok"] == true && v["vui"] == true
      p = v["primaries"] if v["primaries"] != 2 && v["primaries"] != 0
      t = v["transfer"] if v["transfer"] != 2 && v["transfer"] != 0
      m = v["matrix"] if v["matrix"] != 2
      fr = v["full_range"] == 1
  rescue e
    0
  if p == 2 && t == 2 && m == 2
    if cfg.height > 0 && cfg.height < 720
      return [6, 6, 6, fr]
    return [1, 1, 1, fr]
  [p, t, m, fr]

# ---- audio ----

+ SysAudioDec
  ro :handle, :rate, :channels, :format

  -> new(cfg)
    c = cfg.codec
    fmt = c
    cookie = nil
    if c == "mp4a"
      fmt = "aac "
      cookie = cfg.extra
      if cookie.is_a?(String)
        cookie = ccall("w_string_bytes_view", cookie) ## u8[]
      fmt = "usac" if cookie != nil && cookie.size > 0 && (cookie[0] >> 3) == 31 && cookie.size > 1 && ((((cookie[0] & 7) << 3) | (cookie[1] >> 5)) + 32) == 42
    elsif c == "usac"
      cookie = cfg.extra
    elsif c != "ac-3" && c != "ec-3" && c != "mp3 " && c != "alac" && c != "flac" && c != "opus"
      raise MediaError.new("system decoder: unsupported audio codec " + c)
    @cfg = cfg
    @fmt = fmt
    @cookie = cookie
    @handle = nil
    @rate = cfg.sample_rate
    @channels = cfg.channels
    @format = fmt
    @buf = nil
    @frames = 0
    # AC-3 / E-AC-3 take their format from the first packet's header, so
    # those open on the first decode; MPEG-4 audio opens now (fails early)
    open(nil) if @cookie != nil

  -> open(first)
    fpp = 0
    fpp = 1536 if @fmt == "ac-3" || @fmt == "ec-3"
    ck = @cookie
    ck = first if ck == nil
    @handle = ccall("w_media_atdec_new", @fmt, ck, [@cfg.sample_rate, @cfg.channels, fpp])
    @rate = ccall("w_media_atdec_info", @handle, "rate")
    @channels = ccall("w_media_atdec_info", @handle, "channels")
    @format = ccall("w_media_atdec_info", @handle, "format")
    @buf = f32[8192 * @channels]

  -> decode(sample)
    d = sample.data
    if d.is_a?(String)
      d = ccall("w_string_bytes_view", d) ## u8[]
    open(d) if @handle == nil
    n = ccall("w_media_atdec_decode", @handle, d, @buf)
    return nil if n == 0
    @frames += n
    AudioBlock.new(sys_take_f32(@buf, n * @channels), n, @channels, @rate, sample.pts)

  -> flush
    nil

  -> reset
    ccall("w_media_atdec_reset", @handle) if @handle != nil

  -> close
    ccall("w_media_atdec_close", @handle) if @handle != nil
    @handle = nil

# the first n samples of the scratch buffer, as their own f32[]
-> sys_take_f32(src, n) (f32[] i64) f32[]
  o = f32[n]
  i = 0
  while i < n
    o[i] = src[i]
    i += 1
  o

# ---- registry ----

vcodec_system_register(->(cfg) SysVideoDec.new(cfg))
acodec_system_register(->(cfg) SysAudioDec.new(cfg))
