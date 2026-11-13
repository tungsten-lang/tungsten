# studio/encode — segments: the encoder interface and the segment renderer.
#
# A segment is one closed GOP (IDR first) of <= 48 frames, stored as build/segments/<key>.<ext>. The engine only
# talks to SegmentEncoder. MediaSegmentEncoder is core/media's VideoToolbox encoder (HEVC, quality 0.75 by default).

use base
use raster
use render

+ SegmentEncoder
  # open(path, n): start a segment of n frames that will be stored at path (atomically, on close)
  -> open(path, n)
  # write(rgb): one frame, packed RGB24 rows
  -> write(rgb)
  # close: finish; true when the segment is complete and in place
  -> close
  -> name

+ MediaSegmentEncoder < SegmentEncoder
  # Shared VTCompressionSession across segments by default (STUDIO_VT_SESSION=per_segment opts into a fresh session
  # per segment). When quality_by_kind overrides a segment's quality, the session flushes and reopens at that quality.
  -> new(@w, @h, @num, @den, @codec, @quality, @bitrate)
    @per_segment = env("STUDIO_VT_SESSION") == "per_segment"
    @seg_quality = nil
    @active_quality = nil
    @enc = nil
    if !@per_segment
      @enc = new_session()
      @active_quality = @quality
    @pending = nil
    @pending_path = nil
    @rgb_scratch = nil
    @path = nil
    @n = 0

  -> new_session
    return VideoEncoder.new(@w, @h, {codec: @codec, rate: [@num, @den], bitrate: @bitrate, input: :rgba}) if @bitrate != nil
    q = @quality
    q = @seg_quality if @seg_quality != nil
    VideoEncoder.new(@w, @h, {codec: @codec, rate: [@num, @den], quality: q, input: :rgba})

  -> name
    "videotoolbox-" + @codec.to_s

  # q: this segment's quality (the cut's quality_by_kind), or nil for the cut's quality.
  -> open(path, n, q = nil)
    @path = path
    @n = n
    @seg_quality = q
    want_q = q != nil ? q : @quality
    if @per_segment
      @enc = new_session()
      @active_quality = want_q
    elsif @enc == nil || (@bitrate == nil && want_q != @active_quality)
      flush()
      @enc.close if @enc != nil
      @enc = new_session()
      @active_quality = want_q
    self

  -> write_rgba(ptr, stride)
    @enc.encode(ptr, stride)

  -> write(rgb)
    @rgb_scratch = u8[@w * @h * 4] if @rgb_scratch == nil
    rs_rgb_to_rgba_buf(rgb, @w, @h, @rgb_scratch)
    @enc.encode(@rgb_scratch, @w * 4)

  # The GOP closes now; its samples are saved after the next segment's frames have gone in (the first use of a
  # segment waits for the hardware), or at finish.
  -> close
    seg = @enc.segment
    ok = flush()
    @pending = seg
    @pending_path = @path
    if @per_segment
      ok = flush()
      @enc.close
      @enc = nil
    ok

  -> flush
    return true if @pending == nil
    seg = @pending
    path = @pending_path
    @pending = nil
    die("segment " + path + ": " + seg.frames.to_s + " frames, expected more") if seg.frames <= 0
    seg.save(path + ".part")
    seg.release
    File.rename(path + ".part", path)
    true

  -> finish
    ok = flush()
    @enc.close if @enc != nil
    ok

# Encoder in force: VideoToolbox HEVC 0.75 unless the cut says otherwise.
-> encoder_spec(cut)
  e = get(cut, "encoder", {})
  name = env("STUDIO_ENCODER")
  name = get(e, "backend", "videotoolbox") if name == nil || name == ""
  if name == "ffmpeg"
    die("ffmpeg encoder backend removed; use videotoolbox")
  codec = get(e, "codec", "hevc")
  q = to_f(get(e, "quality", ~0.75))
  sess = "shared-session"
  sess = "session-per-segment" if env("STUDIO_VT_SESSION") == "per_segment"
  # a target bitrate (bits per second, averaged over each segment) instead of constant quality
  br = get(e, "bitrate", nil)
  if br != nil
    return {"backend" => "videotoolbox", "codec" => codec, "quality" => q, "bitrate" => br, "ext" => codec,
            "id" => "vt:" + codec + ":b" + br.to_s + ":reorder:bt709-1-1-1:tv:left:420v:" + sess}
  {"backend" => "videotoolbox", "codec" => codec, "quality" => q, "ext" => codec,
   "id" => "vt:" + codec + ":q" + fixed6(q) + ":reorder:bt709-1-1-1:tv:left:420v:" + sess}

-> make_encoder(r, spec, _fifo)
  if spec["backend"] == "ffmpeg"
    die("ffmpeg encoder backend removed; use videotoolbox")
  MediaSegmentEncoder.new(r["w"], r["h"], r["rate"][0], r["rate"][1], spec["codec"], spec["quality"], get(spec, "bitrate", nil))

# STUDIO_SEGMENTS overrides the cache directory (benchmarks render a span fresh without touching the cache).
-> segment_dir(build)
  d = env("STUDIO_SEGMENTS")
  return d if d != nil && d != ""
  build + "/segments"

-> segment_path(build, key)
  segment_dir(build) + "/" + key + "." + get(SEGMENT_EXT, "ext", "hevc")

SEGMENT_EXT = {"ext" => "hevc"}

# Render a list of segments (indices into r["segments"]) through an encoder. Returns frames rendered.
-> render_segments(eng, enc, r, build, idxs, claim_dir = nil)
  segs = r["segments"]
  mkdir_p(segment_dir(build))
  total = 0
  idxs.each ->(i)
    s = segs[i]
    path = segment_path(build, s["key"])
    if !File.exist?(path)
      claimed = claim_dir == nil || ccall("w_media_hardlink", "", claim_dir + "/" + i.to_s)
      if claimed && !File.exist?(path)
        enc.open(path, s["n"], s["q"])
        f = s["f0"]
        e = s["f0"] + s["n"]
        while f < e
          enc.write_rgba(eng.frame_rgba(f), eng.lstride)
          f += 1
        die("segment " + s["key"] + " failed") if !enc.close
        total += s["n"]
  enc.finish
  total

# Decode frame k of a stored segment natively via VideoToolbox to a PNG or raw yuv420p, for `studio frame`.
-> decode_segment_frame(path, k, out, yuv, _rate)
  src = (path.ends_with?(".mp4") || path.ends_with?(".mov")) ? path : [path]
  facts = MediaVerify.facts(src, false, false)
  w = facts[:width]
  h = facts[:height]
  return false if w == nil || h == nil || w <= 0 || h <= 0
  frames = MediaVerify.extract_frames(src, [k])
  return false if frames.size == 0
  rgb = frames[0]
  if yuv
    buf = u8[w * h + (w / 2) * (h / 2) * 2]
    rs_rgb_to_yuv420p(rgb, w, h, buf)
    fh = FileHandle.new(out, "wb")
    fh.write(buf)
    fh.close
    return true
  c = Canvas.new(w, h)
  rs_rgb_to_canvas(rgb, w, h, c.data_pointer, c.stride)
  c.write_png(out)
  c.close
  true
