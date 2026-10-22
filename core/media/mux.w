# Mux — an MP4 or MOV master from encoded segments, audio and timecode, with
# no re-encode: AVAssetWriter passthrough.
#
#   mux = Mux.new("master.mp4", rate: [24, 1], audio: "mix.wav", tc_start: "00:00:00:00")
#   keys.each -> mux.append_file("build/segments/[x].h264")   # or mux.append(segment)
#   r = mux.close          # {frames:, audio_samples:, audio_source_samples:, video_bytes:, file_bytes:}
#
# Video: each segment's samples are copied in order with PTS = frame x den /
# num, in a track timescale where a frame is a whole number of ticks (24 fps:
# 24000, 1000 ticks a frame; 24000/1001: 24000, 1001 ticks), so the file is
# constant frame rate with exact timestamps. Every segment must start with a
# sync sample and share the first segment's format description (codec, size,
# colour tags, parameter sets); anything else raises instead of writing a
# file players would mis-decode.
#
# Audio (optional): a WAV file (16/24/32-bit PCM or 32/64-bit float, any
# rate, up to 8 channels). MP4 carries AAC (audio_kbps, default 320 stereo /
# 192 mono); MOV carries 24-bit PCM, or AAC with audio_codec: :aac. The
# audio is padded with silence or trimmed to exactly frames x rate x den /
# num samples, and AAC encoder priming sits behind an edit list, so audio
# sample 0 plays with video frame 0. close reports the WAV's own length too.
# AVAssetWriter interleaves in about one-second chunks and holds the video
# until the audio leads it, so the audio is fed ahead of the video; without a
# frames: promise, silence past the WAV's end may run up to 250 ms past the
# last frame, where the session end trims it (an edit list).
#
# Timecode: a tmcd track starting at tc_start (default "00:00:00:00"; nil for
# none), drop-frame for 30000/1001 and 60000/1001 unless drop: false, with the
# 24-hour flag, one sample spanning the whole video. faststart: true (default)
# puts the moov before the media data.
#
# Chapters: chapters: [[title, first frame], ...] (ascending; or add them one
# at a time with #chapter before close) become a QuickTime chapter track: a
# disabled text track, one sample per chapter lasting until the next (the
# last until the end), referenced from the video and audio tracks through
# 'chap', which AVFoundation reads as chapterMetadataGroups and ffprobe as
# chapters. Starts are exact frames (the track uses the video's timescale);
# a first chapter after frame 0 sits behind an empty edit. MP4s also get a
# Nero chpl box in moov/udta (100 ns starts, titles cut to 255 bytes, at
# most 255 chapters) for players that read only that; chpl: false leaves it
# out.

+ Mux
  ro :path, :rate, :format, :frames, :tc_start, :drop, :handle

  # Mux.new(path, rate: [24, 1], format: nil (from the extension), audio: nil,
  # audio_codec: nil, audio_kbps: nil, tc_start: "00:00:00:00", drop: nil,
  # faststart: true, frames: nil, chapters: nil, chpl: true). frames:
  # promises the total frame count, so the audio is fed exactly (close
  # raises if a different count arrived).
  -> new(@path, opts = {})
    @rate = Timecode.rate(Mux.opt(opts, :rate, [24, 1]))
    @format = Mux.opt(opts, :format, nil)
    @frames = 0
    @drop = Mux.opt(opts, :drop, Timecode.drop_frame?(@rate))
    @tc_start = "00:00:00:00"
    if opts != nil && opts.has_key?(:tc_start)
      @tc_start = opts[:tc_start]
    tc_frame = nil
    if @tc_start != nil
      label = @tc_start.to_s
      if label.size == 11 && @drop
        label = label[0...8] + ";" + label[9...11]
      elsif label.size == 11
        label = label[0...8] + ":" + label[9...11]
      tc_frame = Timecode.parse(label, @rate)
      @tc_start = Timecode.to_smpte(tc_frame, @rate, @drop)
    fmt = @format == nil ? nil : @format.to_s
    @handle = ccall("w_media_mux_new", @path, fmt, @rate[0], @rate[1], opts[:audio], opts[:audio_codec], opts[:audio_kbps],
                    tc_frame, @drop, Timecode.quanta(@rate), Mux.opt(opts, :faststart, true), opts[:frames])
    @chapters = []
    if opts != nil && opts.has_key?(:chapters) && opts[:chapters] != nil
      opts[:chapters].each ->(c)
        chapter(c[0], c[1])
    if opts != nil && opts.has_key?(:chpl) && opts[:chpl] != nil
      ccall("w_media_mux_set", @handle, "chpl", opts[:chpl])

  # Add a chapter starting at `frame` (frames must ascend). Returns the count.
  -> chapter(title, frame)
    if @chapters.size > 0 && frame <= @chapters[@chapters.size - 1][1]
      raise "Mux#chapter: '[title]' at frame [frame] is not after the previous chapter (frame [@chapters[@chapters.size - 1][1]])"
    @chapters << [title.to_s, frame]
    @chapters.size

  -> chapters
    @chapters

  # Add chapters to an existing movie (no chapter track yet) without
  # re-encoding or re-muxing: the moov gets the chapter track (and chpl for
  # MP4) and moves to the front; the media data is copied once. rate:
  # defaults to the video's frame duration. Returns the chapter count.
  #   Mux.chapterize("master.mp4", "master.chapters.mp4", [["Opening", 0], ["Act I", 587]])
  -> .chapterize(src, dst, chapters, opts = {})
    r = Mux.opt(opts, :rate, nil)
    if r == nil
      md = MediaVerify.facts(src, false, false)[:min_frame_duration]
      raise "Mux.chapterize: [src] has no video frame duration; pass rate:" if md == nil
      r = [md[1], md[0]]
    ccall("w_media_chapterize", src, dst, chapters, Timecode.rate(r))

  -> .opt(opts, key, fallback)
    if opts == nil || !opts.has_key?(key) || opts[key] == nil
      return fallback
    opts[key]

  # Append one segment (a VideoSegment); returns the frames written so far.
  -> append(segment)
    @frames = ccall("w_media_mux_append", @handle, segment.handle)
    @frames

  # Load a segment file, append it and free it.
  -> append_file(path)
    seg = VideoSegment.load(path)
    begin
      append(seg)
    ensure
      seg.release
    @frames

  # Finish the file. Returns {frames:, audio_samples:, audio_source_samples:,
  # video_bytes:, file_bytes:}.
  -> close
    if @chapters.size > 0
      ccall("w_media_mux_set", @handle, "chapters", @chapters)
    r = ccall("w_media_mux_close", @handle)
    {frames: r[0], audio_samples: r[1], audio_source_samples: r[2], video_bytes: r[3], file_bytes: r[4]}
