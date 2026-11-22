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
# ==== end of core header ====

+ MediaError < StandardError

+ CodecConfig
  rw :codec, :extra, :width, :height, :sample_rate, :channels, :timescale
  # The container's colour description (MP4 colr nclx, Matroska Colour), CICP
  # code points; 2 = unspecified (the bitstream's own VUI wins when present).
  # codec_string: the RFC 6381 string ("avc1.64001f", "vp09.00.10.08") if known.
  rw :primaries, :transfer, :matrix, :full_range, :codec_string

  -> new(@codec, @extra = nil)
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
+ VideoFrame
  rw :width, :height, :planes, :strides, :chroma, :bit_depth, :pts, :duration, :primaries, :transfer, :matrix, :full_range, :crop

  -> new(@width, @height, @planes, @strides, @chroma, @bit_depth, @pts)
    @duration = ~0.0
    @primaries = 1
    @transfer = 1
    @matrix = 1
    @full_range = false
    @crop = nil

# Decoded audio: interleaved Float32 samples in -1…1: samples is an f32[] of
# frames * channels values (frame-major: L R L R …), at sample_rate. pts in
# seconds (the pts of the sample it came from).
+ AudioBlock
  rw :samples, :frames, :channels, :sample_rate, :pts

  -> new(@samples, @frames, @channels, @sample_rate, @pts)

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

-> vcodec_new(cfg)
  m = VCODECS[cfg.codec]
  raise MediaError.new("unsupported video codec " + cfg.codec) if m == nil
  m.call(cfg)

-> acodec_new(cfg)
  m = ACODECS[cfg.codec]
  raise MediaError.new("unsupported audio codec " + cfg.codec) if m == nil
  m.call(cfg)

# ==== core API ====
# Codec — the registries above, as one class:
#   Codec.video(cfg) / Codec.audio(cfg) → a decoder (raises MediaError)
#   Codec.video?(id) / Codec.audio?(id) → registered?
#   Codec.register_video(id, make) / Codec.register_audio(id, make)
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
