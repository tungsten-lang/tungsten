# VideoEncoder — VideoToolbox H.264 / HEVC / ProRes from RGBA frames, emitted
# as closed-GOP segments that a Mux appends without re-encoding.
#
#   enc = VideoEncoder.new(1920, 1080, codec: :h264, rate: [24, 1], quality: 0.6)
#   48.times ->
#     draw(canvas, f)
#     enc.encode(canvas)                 # a Canvas, or pixels + stride
#   seg = enc.segment                    # closes the GOP: one IDR, then 47 P-frames
#   seg.save("build/segments/c41b.h264") # compressed samples + format description
#   enc.close
#
# Codecs: :h264 (High), :hevc (Main), :hevc10 (Main10), :prores422,
# :prores422hq, :prores422lt, :prores422proxy. VideoEncoder.codecs lists the
# ones this machine's VideoToolbox can open.
#
# Frames: a Canvas (its premultiplied RGBA, taken as composited over black),
# or pixels given as an address (Canvas#data_pointer), a ByteArray / u8[] or
# an Mmap, with stride (bytes per row, default width x bytes per pixel) and
# a byte offset. input: :rgba (default), :bgra, :argb, :rgb24 or :bgr24.
#
# Colour: R'G'B' code values are converted to Y'CbCr here, not inside
# VideoToolbox, with the BT.709 matrix, limited range and chroma siting
# :left (H.264/HEVC chroma_sample_loc_type 0; also :center, :topleft),
# bit for bit as YuvFrame.from_rgba. The stream and container are tagged
# BT.709 primaries / transfer / matrix (1/1/1), limited range, the siting.
# H.264/HEVC are 4:2:0 (8-bit; 10-bit for :hevc10), ProRes 4:2:2 10-bit.
#
# Rate control: quality: 0..1 (VideoToolbox constant quality, default 0.75)
# or bitrate: bits per second. gop: the keyframe backstop for segments longer
# than gop frames (default 48). speed: true asks VideoToolbox to favour speed.
# reorder: true (default) lets H.264/HEVC use B-frames inside a segment: at
# equal VMAF they are 13% (H.264) to 19% (HEVC) smaller; false keeps decode
# order equal to presentation order.
#
# Segments: every #segment call closes the open GOP. Its first frame is a
# forced IDR and no frame of a segment refers outside it (B-frames only
# reorder within it), so each segment is self-contained. Parameter sets live
# in the format description, not the samples, and VideoToolbox derives them
# from the settings alone: segments encoded by separate encoders with the same
# width, height, codec, quality, reorder and rate concatenate under one
# sample description.
# Frames are encoded asynchronously: #segment returns at once and the first
# use of the segment (frames, save, a Mux append) waits for its samples, so
# keep encoding the next segment before saving the last one.

+ VideoEncoder
  ro :width, :height, :codec, :rate, :input, :handle

  # VideoEncoder.new(width, height, codec: :h264, rate: [24, 1], quality: nil,
  # bitrate: nil, gop: 48, input: :rgba, siting: :left, reorder: true,
  # speed: false)
  -> new(@width, @height, opts = {})
    @codec = VideoEncoder.opt(opts, :codec, "h264").to_s
    @rate = Timecode.rate(VideoEncoder.opt(opts, :rate, [24, 1]))
    @input = VideoEncoder.opt(opts, :input, "rgba").to_s
    siting = VideoEncoder.opt(opts, :siting, "left").to_s
    @closed = false
    @handle = ccall("w_media_encoder_new", @width, @height, @codec, @rate[0], @rate[1], opts[:quality], opts[:bitrate],
                    VideoEncoder.opt(opts, :gop, 48), @input, siting, VideoEncoder.opt(opts, :reorder, true),
                    VideoEncoder.opt(opts, :speed, false))

  -> .opt(opts, key, fallback)
    if opts == nil || !opts.has_key?(key) || opts[key] == nil
      return fallback
    opts[key]

  # True when this build has the native bridge (macOS).
  -> .available?
    ccall("w_media_available")

  # Codec names VideoToolbox can open here (probed once).
  -> .codecs
    ccall("w_media_codecs")

  # Native objects alive: {encoders:, segments:, segment_bytes:, muxes:}.
  -> .stats
    s = ccall("w_media_stats")
    {encoders: s[0], segments: s[1], segment_bytes: s[2], muxes: s[3]}

  # Encode one frame. Returns the number of frames in the open segment.
  -> encode(pixels, stride = nil, offset = 0)
    # A Canvas hands over its buffer (checked by name, so media programs do
    # not load Canvas; File.mmap's object is not is_a?(Mmap), hence no
    # positive type test for the raw kinds, which the runtime checks).
    if type(pixels) == "Canvas"
      return ccall("w_media_encoder_encode", @handle, pixels.data_pointer, 0, pixels.stride)
    ccall("w_media_encoder_encode", @handle, pixels, offset, stride)

  # Close the open GOP and return it as a VideoSegment.
  -> segment
    VideoSegment.new(ccall("w_media_encoder_segment", @handle))

  -> frames
    ccall("w_media_encoder_info", @handle, "frames")

  -> segments
    ccall("w_media_encoder_info", @handle, "segments")

  # {frames:, segments:, pixel_format:, bits:, convert_s:, submit_s:, wait_s:}
  -> stats
    {frames: frames, segments: segments, pixel_format: ccall("w_media_encoder_info", @handle, "pixel_format"),
     bits: ccall("w_media_encoder_info", @handle, "bits"),
     convert_s: ccall("w_media_encoder_info", @handle, "convert_s"),
     submit_s: ccall("w_media_encoder_info", @handle, "submit_s"),
     wait_s: ccall("w_media_encoder_info", @handle, "wait_s")}

  # Finish every frame in flight and free the session. Frames encoded since
  # the last #segment are discarded; returns how many.
  -> close
    @closed = true
    ccall("w_media_encoder_close", @handle)

  -> closed?
    @closed


# VideoSegment — one closed GOP: compressed samples in decode order plus the
# format description (codec, size, colour tags, parameter sets).
#
# Files (#save / VideoSegment.load) hold exactly that: a 64-byte header, the
# format description extensions, a sample table and the sample data (see
# doc/media.md). Loading does not decode anything.
+ VideoSegment
  ro :handle

  -> new(@handle)

  -> .load(path)
    VideoSegment.new(ccall("w_media_segment_load", path))

  -> frames
    ccall("w_media_segment_info", @handle, "frames")

  # Compressed bytes (sample data only).
  -> bytes
    ccall("w_media_segment_info", @handle, "bytes")

  # Codec fourcc: "avc1", "hvc1", "apcn", "apch", ...
  -> codec
    ccall("w_media_segment_info", @handle, "codec")

  -> width
    ccall("w_media_segment_info", @handle, "width")

  -> height
    ccall("w_media_segment_info", @handle, "height")

  -> rate
    ccall("w_media_segment_info", @handle, "rate")

  -> keyframes
    ccall("w_media_segment_info", @handle, "keyframes")

  # Per sample, decode order: 1 for a sync sample.
  -> sync
    ccall("w_media_segment_info", @handle, "sync")

  -> sizes
    ccall("w_media_segment_info", @handle, "sizes")

  # Per sample, decode order: the frame index within the segment.
  -> pts
    ccall("w_media_segment_info", @handle, "pts")

  # The avcC / hvcC record (SPS/PPS/VPS), or nil for ProRes.
  -> param_sets
    ccall("w_media_segment_info", @handle, "param_sets")

  # The serialized format description extensions.
  -> format
    ccall("w_media_segment_info", @handle, "format")

  # One sample's bytes (length-prefixed NAL units for H.264/HEVC).
  -> sample(i)
    ccall("w_media_segment_sample", @handle, i)

  # Write the segment file; returns its size in bytes.
  -> save(path)
    ccall("w_media_segment_save", @handle, path)

  # Free the native samples now (there are no finalizers).
  -> release
    ccall("w_media_segment_release", @handle)
