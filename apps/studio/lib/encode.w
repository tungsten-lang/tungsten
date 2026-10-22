# studio/encode — segments: the encoder interface, the interim ffmpeg adapter, and the segment renderer.
#
# A segment is one closed GOP (IDR first) of <= 48 frames, stored as build/segments/<key>.mp4. The engine only
# talks to SegmentEncoder; FfmpegSegmentEncoder is the interim back end (raw RGB24 through a FIFO into libx264,
# BT.709 matrix, limited range, left chroma siting, all tagged) until core/media's VideoToolbox encoder lands.

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

-> segment_path(build, key)
  build + "/segments/" + key + ".mp4"

# Render a list of segments (indices into r["segments"]) through an encoder. Returns frames rendered.
-> render_segments(eng, enc, r, build, idxs)
  segs = r["segments"]
  mkdir_p(build + "/segments")
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
  total

# Decode frame k of a stored segment (interim: ffmpeg) to a PNG or raw yuv420p, for `studio frame`.
-> decode_segment_frame(path, k, out, yuv)
  sel = "select=eq(n\\," + k.to_s + ")"
  if yuv
    cmd = "ffmpeg -nostdin -y -v error -i " + shq(path) + " -vf " + shq(sel) + " -fps_mode passthrough -frames:v 1 -pix_fmt yuv420p -f rawvideo " + shq(out)
  else
    cmd = "ffmpeg -nostdin -y -v error -i " + shq(path) + " -vf " + shq(sel + ",scale=in_color_matrix=bt709:in_range=tv:out_range=pc:flags=accurate_rnd+full_chroma_int") + " -fps_mode passthrough -frames:v 1 " + shq(out)
  OS.system(cmd)
