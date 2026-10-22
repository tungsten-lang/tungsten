# studio/encode — segments: the encoder interface, the interim ffmpeg adapter, and the segment renderer.
#
# A segment is one closed GOP (IDR first) of <= 48 frames, stored as build/segments/<key>.<ext>. The engine only
# talks to SegmentEncoder. MediaSegmentEncoder is core/media's VideoToolbox encoder (HEVC, quality 0.75 by
# default: libx264 crf 18's VMAF); FfmpegSegmentEncoder, the interim back end (raw RGB24 through a FIFO into
# libx264), stays for the comparison (`--encoder ffmpeg`).

use base
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
  -> new(@w, @h, @num, @den, @codec, @quality)
    @enc = VideoEncoder.new(@w, @h, {codec: @codec, rate: [@num, @den], quality: @quality, input: :rgb24})
    @pending = nil
    @pending_path = nil
    @path = nil
    @n = 0

  -> name
    "videotoolbox-" + @codec.to_s

  -> open(path, n)
    @path = path
    @n = n
    self

  -> write(rgb)
    @enc.encode(rgb, @w * 3)

  # The GOP closes now; its samples are saved after the next segment's frames have gone in (the first use of a
  # segment waits for the hardware), or at finish.
  -> close
    seg = @enc.segment
    ok = flush()
    @pending = seg
    @pending_path = @path
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
    @enc.close
    ok

+ FfmpegSegmentEncoder < SegmentEncoder
  -> new(@w, @h, @num, @den, @fifo)
    @proc = nil
    @fh = nil
    @path = nil
    @part = nil

  -> name
    "ffmpeg-libx264"

  -> open(path, n)
    @path = path
    @part = path + ".part.mp4"
    OS.system("rm -f " + shq(@fifo) + " && mkfifo " + shq(@fifo))
    # keyint is the same for every segment (SEG_MAX), not the segment's length: a shorter GOP setting changes the
    # SPS (x264 drops B-frames for keyint < 4), and passthrough concatenation needs one SPS for the whole track.
    # Each segment is its own encode, so it still opens with an IDR and closes its GOP.
    gop = SEG_MAX.to_s
    args = ["ffmpeg", "-nostdin", "-y", "-v", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", @w.to_s + "x" + @h.to_s,
            "-framerate", @num.to_s + "/" + @den.to_s, "-i", @fifo,
            "-vf", "scale=out_range=tv:out_color_matrix=bt709:out_h_chr_pos=0:out_v_chr_pos=128:flags=bicubic+accurate_rnd+full_chroma_int,format=yuv420p,setparams=range=tv:color_primaries=bt709:color_trc=bt709:colorspace=bt709:chroma_location=left",
            "-c:v", "libx264", "-preset", "medium", "-crf", "18", "-g", gop, "-keyint_min", gop, "-sc_threshold", "0",
            "-x264-params", "open-gop=0:scenecut=0", "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709",
            "-color_range", "tv", "-chroma_sample_location", "left", "-video_track_timescale", "12288", "-f", "mp4", @part]
    @proc = Process.spawn(args)
    @fh = FileHandle.new(@fifo, "wb")
    self

  -> write(rgb)
    @fh.write(rgb)

  -> close
    @fh.close
    code = @proc.wait
    if code != 0
      << "ffmpeg failed (" + code.to_s + ") on " + @path
      return false
    File.rename(@part, @path)
    true

  -> finish
    true

# Encoder in force: VideoToolbox HEVC 0.75 unless the cut says otherwise or STUDIO_ENCODER=ffmpeg.
-> encoder_spec(cut)
  e = get(cut, "encoder", {})
  name = env("STUDIO_ENCODER")
  name = get(e, "backend", "videotoolbox") if name == nil || name == ""
  if name == "ffmpeg"
    return {"backend" => "ffmpeg", "ext" => "mp4", "id" => "ffmpeg-libx264:crf18:medium:g48:closed:bt709-1-1-1:tv:left:yuv420p"}
  codec = get(e, "codec", "hevc")
  q = to_f(get(e, "quality", ~0.75))
  {"backend" => "videotoolbox", "codec" => codec, "quality" => q, "ext" => codec,
   "id" => "vt:" + codec + ":q" + fixed6(q) + ":reorder:bt709-1-1-1:tv:left:420v"}

-> make_encoder(r, spec, fifo)
  if spec["backend"] == "ffmpeg"
    return FfmpegSegmentEncoder.new(r["w"], r["h"], r["rate"][0], r["rate"][1], fifo)
  MediaSegmentEncoder.new(r["w"], r["h"], r["rate"][0], r["rate"][1], spec["codec"], spec["quality"])

# STUDIO_SEGMENTS overrides the cache directory (benchmarks render a span fresh without touching the cache).
-> segment_dir(build)
  d = env("STUDIO_SEGMENTS")
  return d if d != nil && d != ""
  build + "/segments"

-> segment_path(build, key)
  segment_dir(build) + "/" + key + "." + get(SEGMENT_EXT, "ext", "hevc")

SEGMENT_EXT = {"ext" => "hevc"}

# Render a list of segments (indices into r["segments"]) through an encoder. Returns frames rendered.
-> render_segments(eng, enc, r, build, idxs)
  segs = r["segments"]
  mkdir_p(segment_dir(build))
  total = 0
  idxs.each ->(i)
    s = segs[i]
    path = segment_path(build, s["key"])
    if !File.exist?(path)
      enc.open(path, s["n"])
      f = s["f0"]
      e = s["f0"] + s["n"]
      while f < e
        enc.write(eng.frame_into(f))
        f += 1
      die("segment " + s["key"] + " failed") if !enc.close
      total += s["n"]
  enc.finish
  total

# Decode frame k of a stored segment (interim: ffmpeg) to a PNG or raw yuv420p, for `studio frame`.
-> decode_segment_frame(path, k, out, yuv)
  if path.ends_with?(".hevc") || path.ends_with?(".h264")
    wrap = out + ".seg.mp4"
    m = Mux.new(wrap, {rate: [24, 1], tc_start: nil})
    m.append_file(path)
    m.close
    path = wrap
  sel = "select=eq(n\\," + k.to_s + ")"
  if yuv
    cmd = "ffmpeg -nostdin -y -v error -i " + shq(path) + " -vf " + shq(sel) + " -fps_mode passthrough -frames:v 1 -pix_fmt yuv420p -f rawvideo " + shq(out)
  else
    cmd = "ffmpeg -nostdin -y -v error -i " + shq(path) + " -vf " + shq(sel + ",scale=in_color_matrix=bt709:in_range=tv:out_range=pc:flags=accurate_rnd+full_chroma_int") + " -fps_mode passthrough -frames:v 1 " + shq(out)
  OS.system(cmd)
