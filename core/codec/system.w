# core/codec/system — the operating system's decoders behind core/codec's
# decoder contract, and the per-format default for which decoder Codec.video /
# Codec.audio / Image.decode pick (macOS: VideoToolbox, AudioToolbox's
# AudioConverter, ImageIO).
#
#   use core/codec/system            # (core/codec loads it)
#   dec = Codec.video(cfg)           # VideoToolbox for H.264 / HEVC / AV1 / VP9 where it can
#   dec = SysVideoDec.new(cfg)       # force the system decoder (benchmarks)
#
# Default table (SYS_DEFAULT_CODECS / SYS_DEFAULT_IMAGES): the system decoder
# for every format where it is faster or the format sits under a patent pool;
# ours where ours is competitive and the format is royalty-free.
#   system: H.264, HEVC, AV1, VP9 (VideoToolbox; AV1 / VP9 only where the
#           machine decodes them in hardware), AAC-LC / HE-AAC v1/v2 / xHE-AAC,
#           AC-3 / E-AC-3 (AudioToolbox), HEIC/HEIF, AVIF, JPEG XL, and JPEG
#           and WebP (ImageIO is 2x faster: 45 vs 97 ms for a 4K JPEG, 70 vs
#           144 ms for a 4K WebP; animated WebP / AVIF stay ours)
#   ours:   Opus, Vorbis, FLAC, MP3, ALAC, PCM, VP8, Theora; PNG, GIF and
#           the other image formats
# Overrides for testing either path: TUNGSTEN_CODEC_SYSTEM (or BLADE_CODEC):
# "own"/"0" = ours for everything, "system"/"all"/"1" = system wherever it
# exists, "patent" = the default table, or a list of codec ids / image names
# ("avc1,mp4a,heic"); Codec.prefer_system(ids) at run time.
#
# Fallback: when the system decoder cannot open a stream (unsupported
# profile, no hardware AV1) or fails before producing its first frame /
# block, the decoder switches to ours silently, replaying the samples it has
# buffered since the start; images fall back per file. `decoder.backend`
# says which one is running ("system" / "own").
#
# Frames: VideoFrames with planes copied out of the CVPixelBuffer (NV12 /
# P010 de-interleaved into Y, Cb, Cr; owned: true). Audio: AudioBlocks of
# interleaved f32 in WAVE channel order at the rate AudioToolbox decodes to
# (the SBR rate for HE-AAC, stereo for HE-AAC v2).
#
# Measurement helper: sys_rusage → {user:, sys:, max_rss:, now:}.

use core/codec/media
use core/codec/image
use core/canvas

SYS_DEFAULT_CODECS = ["avc1", "avc3", "hvc1", "hev1", "av01", "vp09", "mp4a", "ac-3", "ec-3"]
SYS_DEFAULT_IMAGES = ["heic", "avif", "jxl", "jpeg", "webp"]

-> sys_rusage
  r = ccall("w_media_sys_rusage")
  {user: r[0], sys: r[1], max_rss: r[2], now: r[3]}

# ---- video ----

+ SysVideoDec
  ro :handle, :hevc, :bits, :frames

  -> new(cfg)
    c = cfg.codec
    @hevc = c == "hvc1" || c == "hev1"
    avc = c == "avc1" || c == "avc3"
    raise MediaError.new("system decoder: unsupported video codec " + c) if !@hevc && !avc && c != "av01" && c != "vp09"
    @cfg = cfg
    @codec = c
    @bits = 8
    x = cfg.extra
    x = nil if x != nil && !x.is_a?(ByteArray)
    if @hevc && x != nil && x.size > 20
      # hvcC: bitDepthLumaMinus8 in byte 19 (low 3 bits)
      @bits = (x[19] & 7) + 8
    elsif c == "av01" && x != nil && x.size > 2
      @bits = (x[2] & 64) != 0 ? 10 : 8
    elsif c == "vp09" && x != nil && x.size > 6
      @bits = (x[6] >> 4) > 8 ? 10 : 8
    @colour = (avc || @hevc) ? sys_video_colour(cfg, @hevc) : sys_cfg_colour(cfg)
    @durs = {}
    @frames = 0
    @spare = nil
    @handle = nil
    # VP9 from WebM carries no vpcC: open on the first key frame, from its header
    open(x) if x != nil || c != "vp09"

  -> open(extra)
    @handle = ccall("w_media_vtdec_new", @codec, extra, [@cfg.width, @cfg.height, @bits, 1, 0])

  -> hw?
    return false if @handle == nil
    ccall("w_media_vtdec_info", @handle, "hw")

  -> errors
    return 0 if @handle == nil
    ccall("w_media_vtdec_info", @handle, "errors")

  -> decode(sample)
    if @handle == nil
      v = sys_vp9_vpcc(sample.data)
      return [] if v == nil
      @bits = (v[6] >> 4) > 8 ? 10 : 8
      open(v)
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
    ccall("w_media_vtdec_reset", @handle) if @handle != nil
    @durs = {}

  -> close
    ccall("w_media_vtdec_close", @handle) if @handle != nil
    @handle = nil
    if @spare != nil
      @spare.each ->(p) ccall("w_value_free_w", p)
    @spare = nil

  -> take(fl)
    out = []
    return out if @handle == nil
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

-> sys_cfg_colour(cfg)
  p = cfg.primaries
  t = cfg.transfer
  m = cfg.matrix
  fr = cfg.full_range == true
  if p == 2 && t == 2 && m == 2
    return [6, 6, 6, fr] if cfg.height > 0 && cfg.height < 720
    return [1, 1, 1, fr]
  [p, t, m, fr]

# A vpcC payload (version 1) built from a VP9 key frame's uncompressed
# header (profile, bit depth, colour range), or nil if this is not one.
-> sys_vp9_vpcc(d)
  return nil if d == nil || d.size < 10
  if d.is_a?(String)
    d = ccall("w_string_bytes_view", d) ## u8[]
  st = [0]
  return nil if sys_bits(d, st, 2) != 2
  lo = sys_bits(d, st, 1)
  hi = sys_bits(d, st, 1)
  prof = (hi << 1) | lo
  sys_bits(d, st, 1) if prof == 3
  return nil if sys_bits(d, st, 1) == 1          # show_existing_frame
  return nil if sys_bits(d, st, 1) != 0          # not a key frame
  sys_bits(d, st, 2)                             # show_frame, error_resilient_mode
  return nil if sys_bits(d, st, 24) != 0x498342
  bd = 8
  bd = sys_bits(d, st, 1) == 1 ? 12 : 10 if prof >= 2
  cs = sys_bits(d, st, 3)
  full = 0
  full = sys_bits(d, st, 1) if cs != 7
  v = u8[12]
  v[0] = 1
  v[4] = prof
  v[5] = 31
  v[6] = (bd << 4) | (1 << 1) | full
  v[7] = 2
  v[8] = 2
  v[9] = 2
  v

-> sys_bits(d, st, n)
  v = 0
  k = 0
  while k < n
    p = st[0]
    v = (v << 1) | ((d[p >> 3] >> (7 - (p & 7))) & 1)
    st[0] = p + 1
    k += 1
  v

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

  -> errors
    0

  -> sample_rate
    @rate

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

# ---- fallback to ours ----
# The registry's system maker: the system decoder, switching to ours when it
# cannot open the stream or fails before its first output. Samples are kept
# (up to SYS_REPLAY) until then so ours can start from the beginning.
SYS_REPLAY = 96

+ SysFallback
  ro :backend, :inner

  -> new(cfg, kind)
    @cfg = cfg
    @kind = kind
    @kept = []
    @inner = nil
    @backend = "system"
    begin
      @inner = kind == 0 ? SysVideoDec.new(cfg) : SysAudioDec.new(cfg)
    rescue e
      switch
    @out_seen = false

  -> own_maker
    t = @kind == 0 ? VCODECS : ACODECS
    t[@cfg.codec]

  -> switch
    m = own_maker
    raise MediaError.new("no decoder for " + @cfg.codec) if m == nil
    old = @inner
    @inner = codec_call_maker(m, @cfg)
    @backend = "own"
    << "codec: " + @cfg.codec + " system decoder unavailable, using ours" if env("TUNGSTEN_CODEC_LOG") == "1"
    begin
      old.close if old != nil
    rescue e
      0
    0

  -> failed?
    return false if @backend != "system" || @out_seen
    @inner.errors > 0

  -> decode(sample)
    if @backend == "system" && !@out_seen
      @kept.push(sample) if @kept.size < SYS_REPLAY
      r = nil
      begin
        r = @inner.decode(sample)
      rescue e
        return switch_replay
      return switch_replay if failed?
      got = @kind == 0 ? r.size > 0 : r != nil
      if got
        @out_seen = true
        @kept = []
      return r
    @inner.decode(sample)

  # ours, fed everything kept so far; returns what that produced (video: the
  # frames, audio: the last block)
  -> switch_replay
    switch
    out = @kind == 0 ? [] : nil
    i = 0
    while i < @kept.size
      r = @inner.decode(@kept[i])
      if @kind == 0
        j = 0
        while j < r.size
          out.push(r[j])
          j += 1
      elsif r != nil
        out = r
      i += 1
    @kept = []
    @last_replay = out
    out

  -> flush
    @inner.flush

  -> reset
    @inner.reset
    @kept = []

  -> close
    begin
      @inner.close
    rescue e
      0

  # passthrough for callers that look at the decoder
  -> sample_rate
    @inner.sample_rate

  -> channels
    @inner.channels

  -> hw?
    @backend == "system" && @kind == 0 ? @inner.hw? : false

# ---- registry ----

vcodec_system_register(->(cfg) SysFallback.new(cfg, 0))
acodec_system_register(->(cfg) SysFallback.new(cfg, 1))
codec_system_defaults(SYS_DEFAULT_CODECS + SYS_DEFAULT_IMAGES)

# ---- images (ImageIO via core/canvas) ----

# A Bitmap (straight RGBA8, sRGB) decoded by ImageIO: drawn into an sRGB
# canvas so wide-gamut sources (Display P3 HEIC) are converted.
-> sys_image_decode(bytes)
  img = Canvas.load_image_data(bytes)
  w = img.width
  h = img.height
  c = Canvas.new(w, h)
  c.image(img, 0, 0, w, h)
  px = c.bytes
  img.release
  begin
    c.close
  rescue e
    0
  Bitmap.new(w, h, px)

img_system_register(->(b) sys_image_decode(b))
