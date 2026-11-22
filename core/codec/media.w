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
#
# Lifetime: a frame's planes stay valid until the decoder's next decode /
# flush / reset call (decoders may hand out their own reference pictures and
# release them later; Tungsten has no collector, so decoders free pictures
# they drop explicitly). owned: true when the planes were allocated for this
# frame alone, so the consumer may release them (ccall "w_value_free_w")
# once it has converted the frame.
+ VideoFrame
  rw :width, :height, :planes, :strides, :chroma, :bit_depth, :pts, :duration, :primaries, :transfer, :matrix, :full_range, :crop, :owned

  -> new(@width, @height, @planes, @strides, @chroma, @bit_depth, @pts)
    @owned = false
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

# ---- system decoders (core/codec/system registers them) ----
# One maker per kind for the operating system's decoders. The registry uses
# ours unless the codec id is in the system preference list
# (Codec.prefer_system / TUNGSTEN_CODEC_SYSTEM, see core/codec/system); a
# preferred system decoder that fails to open falls back to ours, and a codec
# only the system has goes to the system.
SYS_MAKERS = [nil, nil]       # [video maker, audio maker]
SYS_PREFER = [nil]            # nil: read TUNGSTEN_CODEC_SYSTEM on first use

# The codec ids "patent" selects: the formats with patent pools behind them.
SYS_PATENT_CODECS = ["avc1", "avc3", "hvc1", "hev1", "mp4a", "ac-3", "ec-3"]

-> vcodec_system_register(make)
  SYS_MAKERS[0] = make

-> acodec_system_register(make)
  SYS_MAKERS[1] = make

-> codec_id4(id)
  id.size == 3 ? id + " " : id

-> codec_system_list
  if SYS_PREFER[0] == nil
    v = env("TUNGSTEN_CODEC_SYSTEM")
    l = []
    if v == "patent" || v == "1"
      l = SYS_PATENT_CODECS + []
    elsif v == "all"
      l = SYS_PATENT_CODECS + ["usac", "mp3 "]
    elsif v != nil && v != "" && v != "0"
      v.split(",").each ->(id)
        l.push(codec_id4(id))
    SYS_PREFER[0] = l
  SYS_PREFER[0]

# (each maker is called from its own function: one closure call per method)
-> codec_new_with(table, kind, cfg)
  ours = table.has_key?(cfg.codec)
  if SYS_MAKERS[kind] != nil && (!ours || codec_system_list().include?(cfg.codec))
    d = codec_try_system(kind, cfg, !ours)
    return d if d != nil
  raise MediaError.new("unsupported " + (kind == 0 ? "video" : "audio") + " codec " + cfg.codec) if !ours
  codec_call_maker(table[cfg.codec], cfg)

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
