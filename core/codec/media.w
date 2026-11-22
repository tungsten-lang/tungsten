# core/codec/media — the audio/video codec contract: compressed samples in,
# decoded frames out, and the codec registry (Codec).
#
#   use core/codec                       # every codec and demuxer
#   d = demux_for(first_bytes)           # core/codec/container/demux: MP4 / WebM / Ogg / TS / WAV / AIFF / MP3 / ADTS / FLAC
#   dec = Codec.video(track.cfg)         # or Codec.audio(cfg); raises MediaError when unsupported
#   frames = dec.decode(sample)          # VideoFrame list (Y'CbCr; core/codec/video/yuv converts to RGBA)
#
# Demuxers (core/codec/container) turn a byte stream into tracks of compressed
# samples; codecs turn samples into frames. Codecs register at load time by
# codec id, so a pipeline never names a codec:
#
#   vcodec_register("avc1", ->(cfg) H264Dec.new(cfg))       # Codec.register_video
#   acodec_register("opus", ->(cfg) OpusDec.new(cfg))       # Codec.register_audio
#
# Codec ids: video "avc1" (H.264, also "avc3"), "hvc1" (HEVC, also "hev1"),
# "av01" (AV1), "vp08", "vp09", "theo" (Theora); audio "mp4a" (AAC), "opus",
# "vorb" (Vorbis), "mp3 ", "flac", "alac", "ac-3", "ec-3", "pcm ".
#
# cfg is a CodecConfig: the decoder configuration record exactly as the
# container stores it (avcC / hvcC / av1C / vpcC bytes, Matroska CodecPrivate,
# Ogg identification+comment+setup headers, esds AudioSpecificConfig, dOps,
# …) plus the container's view of size / sample rate / channels.
#
# A video decoder: decode(sample) → Array of VideoFrame (zero or more: decoders
# with reordering return frames in presentation order as they become ready);
# flush → the remaining frames; reset → drop state (after a seek; the next
# sample is a keyframe).
# An audio decoder: decode(sample) → AudioBlock or nil; flush → AudioBlock or
# nil; reset. Decoders do not trim: the caller drops samples before 0 s
# (Opus pre-skip, AAC priming via edit lists / negative pts) and past the end.
# Decoders keep all state on the instance (module-level tables must be
# read-only after load) because decoding may run on a worker thread.
#
# Audio CodecConfig.extra by codec:
#   "mp4a"  AudioSpecificConfig bytes (esds DecSpecificInfo / Matroska CodecPrivate)
#   "opus"  the OpusHead packet ("OpusHead" magic first; MP4 dOps is rewritten to it)
#   "vorb"  [identification, comment, setup] header packets (Array of ByteArray)
#   "flac"  the 34-byte STREAMINFO block body
#   "mp3 "  nil
#   "pcm "  {bits: 8|16|24|32, float: bool, big_endian: bool}
# Elementary-stream files (MP3, ADTS AAC, native FLAC, WAV) are split into
# samples by the codec's own *_es_parse(bytes) (see each codec file).
#
# Streaming consumers (a player) can opt out of per-frame allocation through
# two CodecConfig hints, set before the decoder is created:
#   cfg.reuse_output = true   decoders may return their own buffers, valid
#                             until the next call: audio an f32[] (AudioBlock
#                             #owned false; samples.size may exceed frames *
#                             channels), video planes they would otherwise
#                             allocate per frame (VideoFrame#owned false)
#   cfg.surfaces = true       the system video decoder hands out its picture
#                             buffers as GPU surfaces (VideoFrame#surface, no
#                             planes: core/codec/video/yuv_gpu presents them
#                             without a copy; f.materialize copies them out);
#                             the consumer releases each frame with f.release
# Plane buffers that a consumer keeps (frame rings) come from media_plane(n,
# bits): page-aligned, page-multiple storage that can back a Metal buffer
# without a copy (newBufferWithBytesNoCopy).
# ==== end of core header ====

+ MediaError < StandardError

+ CodecConfig
  rw :codec, :extra, :width, :height, :sample_rate, :channels, :timescale
  # The container's colour description (MP4 colr nclx, Matroska Colour), CICP
  # code points; 2 = unspecified (the bitstream's own VUI wins when present).
  # codec_string: the RFC 6381 string ("avc1.64001f", "vp09.00.10.08") if known.
  rw :primaries, :transfer, :matrix, :full_range, :codec_string
  # Consumer hints (see the header): reuse audio output buffers / take system video surfaces.
  rw :reuse_output, :surfaces

  -> new(@codec, @extra = nil)
    @reuse_output = false
    @surfaces = false
    @primaries = 2
    @transfer = 2
    @matrix = 2
    @full_range = nil
    @codec_string = nil
    @width = 0
    @height = 0
    @sample_rate = 0
    @channels = 0
    @timescale = 1000

# One compressed access unit. pts/dts/duration are in seconds (Float).
+ MediaSample
  rw :data, :pts, :dts, :duration, :key
  # group: the pipeline's coded-frame-group tag (MSE); codecs ignore it.
  rw :group

  -> new(@data, @pts, @dts, @duration, @key)
    @group = 0

# A decoded picture in planar Y'CbCr. planes: [Y, Cb, Cr] as u8[] (ByteArray)
# for 8-bit, u16[] for bit_depth 9-16 (core/codec/video/yuv reads both); strides in
# samples. chroma: "420", "422", "444", "400". Colour description follows
# CICP (ISO/IEC 23091-2): primaries, transfer, matrix, full_range.
#
# Lifetime: a frame's planes stay valid until the decoder's next decode /
# flush / reset call (decoders may hand out their own reference pictures and
# release them later; Tungsten has no collector, so decoders free pictures
# they drop explicitly). owned: true when the planes were allocated for this
# frame alone, so the consumer may release them (ccall "w_value_free_w")
# once it has converted the frame.
# surface: a system decoder's picture buffer (an opaque handle; cfg.surfaces)
# instead of planes; surface_ptr its CVPixelBuffer's address while the handle
# is held. release: the consumer is done (frees owned planes, gives the
# surface back); materialize: copy a surface frame's picture out into planes.
+ VideoFrame
  rw :width, :height, :planes, :strides, :chroma, :bit_depth, :pts, :duration, :primaries, :transfer, :matrix, :full_range, :crop, :owned, :surface, :surface_ptr

  -> new(@width, @height, @planes, @strides, @chroma, @bit_depth, @pts)
    @owned = false
    @surface = nil
    @surface_ptr = 0
    @duration = ~0.0
    @primaries = 1
    @transfer = 1
    @matrix = 1
    @full_range = false
    @crop = nil

  # Release what this frame holds once its consumer is done with it: planes
  # allocated for it alone (owned) and its system surface.
  -> release
    if @surface != nil
      VIDEO_SURFACE_OPS[0].call(@surface) if VIDEO_SURFACE_OPS[0] != nil
      @surface = nil
      @surface_ptr = 0
    if @owned
      i = 0
      while i < @planes.size
        ccall("w_value_free_w", @planes[i])
        i += 1
      @planes = []
      @owned = false
    nil

  # Give a surface frame planes of its own (copied out of the surface, owned
  # by the frame, which keeps the surface until release). Returns self.
  -> materialize
    return self if @surface == nil || @planes.size >= 3 || VIDEO_SURFACE_OPS[1] == nil
    cw = (@width + 1) / 2
    ch = (@height + 1) / 2
    pl = nil
    if @bit_depth > 8
      pl = [u16[@width * @height], u16[cw * ch], u16[cw * ch]]
    else
      pl = [u8[@width * @height], u8[cw * ch], u8[cw * ch]]
    VIDEO_SURFACE_OPS[1].call(@surface, pl)
    @planes = pl
    @strides = [@width, cw, cw]
    @owned = true
    self

# [release(handle), copy_planes(handle, planes)] for surface frames (core/codec/system).
VIDEO_SURFACE_OPS = [nil, nil]

-> video_surface_ops(release, copy)
  VIDEO_SURFACE_OPS[0] = release
  VIDEO_SURFACE_OPS[1] = copy

# Decoded audio: interleaved Float32 samples in -1…1: samples is an f32[] of
# frames * channels values (frame-major: L R L R …), at sample_rate. pts in
# seconds (the pts of the sample it came from). owned: true when samples was
# allocated for this block (the consumer may free it); false when it is the
# decoder's reused buffer (cfg.reuse_output), valid until the next call.
+ AudioBlock
  rw :samples, :frames, :channels, :sample_rate, :pts, :owned

  -> new(@samples, @frames, @channels, @sample_rate, @pts)
    @owned = true

# The output buffer of an audio decoder for n values: the decoder's reused one
# (cfg.reuse_output; grown when too small) or a fresh f32[]. Usage:
#   @obuf = audio_out(@obuf, @reuse, n)  ...  blk.owned = !@reuse
-> audio_out(buf, reuse, n)
  return f32[n < 1 ? 1 : n] if !reuse
  return buf if buf != nil && buf.size >= n
  ccall("w_value_free_w", buf) if buf != nil
  f32[n < 1024 ? 1024 : n]

# Page-aligned plane storage for n samples (u8[] when bits <= 8, else u16[]):
# its base and length are page multiples, so a Metal buffer can wrap it with
# no copy. Costs a system call: allocate once and reuse (frame rings, pools).
-> media_plane(n, bits)
  return ccall("w_array_new_aligned", 16, n < 1 ? 1 : n) if bits > 8
  ccall("w_array_new_aligned", 8, n < 1 ? 1 : n)


VCODECS = {}
ACODECS = {}

-> vcodec_register(id, make)
  VCODECS[id] = make

-> acodec_register(id, make)
  ACODECS[id] = make

-> vcodec_supported?(id)
  VCODECS.has_key?(id)

-> acodec_supported?(id)
  ACODECS.has_key?(id)

# ---- system decoders (core/codec/system registers them) ----
# One maker per kind for the operating system's decoders. The registry uses
# ours unless the codec id is in the system preference list
# (Codec.prefer_system / TUNGSTEN_CODEC_SYSTEM, see core/codec/system); a
# preferred system decoder that fails to open falls back to ours, and a codec
# only the system has goes to the system.
SYS_MAKERS = [nil, nil]       # [video maker, audio maker]
SYS_PREFER = [nil]            # nil: read TUNGSTEN_CODEC_SYSTEM on first use


-> vcodec_system_register(make)
  SYS_MAKERS[0] = make

-> acodec_system_register(make)
  SYS_MAKERS[1] = make

-> codec_id4(id)
  return id + " " if id == "mp3" || id == "pcm"
  id

# The system decoder's default formats (core/codec/system registers its table).
SYS_DEFAULTS = [[]]

-> codec_system_defaults(list)
  SYS_DEFAULTS[0] = list

# Codec ids and image names the system decoders handle (see core/codec/system):
# the default table, or TUNGSTEN_CODEC_SYSTEM / BLADE_CODEC: "own" / "0" none,
# "system" / "all" / "1" every format the system has, "patent" the table, or
# a comma-separated list.
-> codec_system_list
  if SYS_PREFER[0] == nil
    v = env("TUNGSTEN_CODEC_SYSTEM")
    v = env("BLADE_CODEC") if v == nil || v == ""
    l = SYS_DEFAULTS[0] + []
    if v == "own" || v == "0"
      l = []
    elsif v == "system" || v == "all" || v == "1"
      l = SYS_DEFAULTS[0] + ["usac", "mp3 ", "alac", "flac", "opus", "jpeg", "webp", "jp2", "png", "gif", "tiff", "bmp"]
    elsif v == "patent" || v == nil || v == ""
      l = SYS_DEFAULTS[0] + []
    else
      l = []
      v.split(",").each ->(id)
        l.push(codec_id4(id.strip))
    SYS_PREFER[0] = l
  SYS_PREFER[0]

-> codec_new_with(table, kind, cfg)
  ours = table.has_key?(cfg.codec)
  if SYS_MAKERS[kind] != nil && (!ours || codec_system_list().include?(cfg.codec))
    d = codec_try_system(kind, cfg, !ours)
    if d != nil
      codec_log(kind, cfg, d)
      return d
  raise MediaError.new("unsupported " + (kind == 0 ? "video" : "audio") + " codec " + cfg.codec) if !ours
  d = codec_call_maker(table[cfg.codec], cfg)
  codec_log(kind, cfg, d)
  d

# TUNGSTEN_CODEC_LOG=1: one line per decoder created, saying which one runs.
CODEC_LOG = [nil]

-> codec_log(kind, cfg, d)
  CODEC_LOG[0] = env("TUNGSTEN_CODEC_LOG") == "1" if CODEC_LOG[0] == nil
  return nil if !CODEC_LOG[0]
  who = d.class.to_s
  who = (d.backend == "system" ? "system" : "own (system decoder failed)") + (kind == 0 && d.backend == "system" ? (d.hw? ? " (hardware)" : " (software)") : "") if who == "SysFallback"
  << "codec: " + (kind == 0 ? "video " : "audio ") + cfg.codec + " -> " + who
  nil

# the system decoder, or nil when it cannot open (raises when it is the only one)
-> codec_try_system(kind, cfg, only)
  d = nil
  begin
    d = codec_call_maker(SYS_MAKERS[kind], cfg)
  rescue e
    raise e if only
    d = nil
  d

-> codec_call_maker(make, cfg)
  make.call(cfg)

-> vcodec_new(cfg)
  codec_new_with(VCODECS, 0, cfg)

-> acodec_new(cfg)
  codec_new_with(ACODECS, 1, cfg)

# ==== core API ====
# Codec — the registries above, as one class:
#   Codec.video(cfg) / Codec.audio(cfg) → a decoder (raises MediaError)
#   Codec.video?(id) / Codec.audio?(id) → registered?
#   Codec.register_video(id, make) / Codec.register_audio(id, make)
#   Codec.prefer_system(ids) / Codec.system_preferred — use the OS decoders
#     (core/codec/system: VideoToolbox / AudioToolbox) for these codec ids
# vcodec_* / acodec_* are the same registries under their codec-facing names.
+ Codec
  -> .video(cfg)
    vcodec_new(cfg)

  -> .audio(cfg)
    acodec_new(cfg)

  -> .video?(id)
    vcodec_supported?(id)

  -> .audio?(id)
    acodec_supported?(id)

  -> .register_video(id, make)
    vcodec_register(id, make)

  -> .register_audio(id, make)
    acodec_register(id, make)

  # Prefer the operating system's decoder (core/codec/system) for these
  # codec ids; replaces the list. [] goes back to ours for everything.
  -> .prefer_system(ids)
    SYS_PREFER[0] = ids.map ->(id) codec_id4(id)

  -> .system_preferred
    codec_system_list()

# ---- elementary-stream parsers (MP3, ADTS AAC, native FLAC, raw AC-3 files) ----
# A codec file registers its *_es_parse here; the container layer's EsDemuxer looks it up.
# parse: ->(bytes) {cfg:, samples:, duration:}
ES_PARSERS = {}

-> es_parser_register(kind, parse)
  ES_PARSERS[kind] = parse
