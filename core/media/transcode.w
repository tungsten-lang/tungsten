# VideoDecoder and Transcode — read masters and segments back with
# VideoToolbox, and make scaled, re-encoded copies of them (share copies, 4K
# masters, a resolution ladder, verticals) with no ffmpeg.
#
#   dec = VideoDecoder.new("master.mp4")                 # or an array of segment files
#   while dec.read(buf = nil) != nil  ...                # RGBA frames in presentation order
#
#   r = Transcode.run("master.mp4", "share.mp4", preset: :share)     # 720p H.264 + AAC, chapters and timecode kept
#   r = Transcode.run("master.mp4", "yt4k.mp4", preset: "2160p")    # 4K from 1080p, Lanczos-3
#   r = Transcode.run(segment_paths, "share.mp4", rate: [24, 1], audio_src: "mix.wav", preset: :share)
#   << MediaVerify.format(Transcode.check("share.mp4", preset: :share, chapters: ...))
#
# Decoding. Samples come from the movie's first video track (AVAssetReader,
# passthrough) or from segment files, and are decoded by a
# VTDecompressionSession (hardware) on a thread of their own; frames come out
# in presentation order. A frame's index is its presentation time (through
# the track's edit list) times the rate, rounded, so a master whose frame
# times wander a little (the legacy one has a 513-tick frame) still maps
# each frame to its own index.
#
# Transcoding. By default (via: :yuv) frames decode to 8-bit 4:2:0 and the
# Y' and CbCr planes are resampled separately (Scaler's filters, chroma
# siting honoured on both sides) straight into the encoder's buffers: no
# colour conversion, so the BT.709 values of the master carry over. via:
# :rgb decodes to BGRA (VideoToolbox's BT.709 conversion), scales RGBA and
# converts back like rendered frames. The copy is constant frame rate with
# exactly `frames` frames: a source frame that maps to an index already
# written is dropped, a gap repeats the previous frame (both counted in the
# result). Segments are closed GOPs of gop frames. Chapters (:copy reads the
# source's chapter track), timecode (:copy keeps the source's tmcd start;
# segments start at 00:00:00:00) and
# audio (:copy passes the AAC through; :aac / :pcm decode and re-encode it,
# sample-exact) carry through; a range (start:, frames:) shifts all three.
#
# Presets (Transcode.presets): share (1280x720 H.264 at 2.5 Mb/s, AAC 128k,
# 2 s GOP: the studio's share copy), the ladder 480p, 720p, 1080p, 1440p,
# 2160p (alias 4k), 4320p (8k, HEVC: H.264 stops at 4096 x 2304), and
# vertical (1080x1920, centre crop) / vertical_pad (whole frame, bars) /
# vertical4k. Ladder bitrates are YouTube's recommended upload rates (SDR, up
# to 30 fps; doubled above), GOP half a second, B-frames on. H.264 levels are
# set to the lowest level that holds the size, frame rate and bitrate;
# Transcode.check verifies codec, profile, bit depth, 4:2:0, size and that
# the stream's level holds the picture (and is no higher than the preset's
# cap), on top of every MediaVerify check.

+ VideoDecoder
  ro :source, :format, :width, :height, :rate, :handle, :frame

  # VideoDecoder.new(source, format: :rgba (:bgra, :nv12), start: 0, rate: nil)
  # source: a movie path, or an Array of segment files (in order).
  -> new(@source, opts = {})
    @format = Transcode.opt(opts, :format, "rgba").to_s
    r = Transcode.opt(opts, :rate, nil)
    rr = r == nil ? [0, 0] : Timecode.rate(r)
    @handle = ccall("w_media_decoder_open", @source, @format, [Transcode.opt(opts, :start, 0), rr[0], rr[1]])
    @width = ccall("w_media_decoder_info", @handle, "width")
    @height = ccall("w_media_decoder_info", @handle, "height")
    @rate = ccall("w_media_decoder_info", @handle, "rate")
    @frame = -1
    @buf = nil

  # Bytes in one frame of this format.
  -> frame_bytes
    @format == "nv12" ? @width * @height + ((@width + 1) / 2) * 2 * ((@height + 1) / 2) : @width * @height * 4

  # The next frame (presentation order) into buf (a u8[] / ByteArray /
  # address; nil: one buffer the decoder keeps), or nil at the end. #frame
  # is then its index.
  -> read(buf = nil, stride = nil)
    b = buf
    if b == nil
      @buf = u8[frame_bytes] if @buf == nil
      b = @buf
    f = ccall("w_media_decoder_read", @handle, b, stride)
    if f == nil
      return nil
    @frame = f
    b

  # Frames the movie should hold (from its duration), or nil for segments.
  -> frames
    ccall("w_media_decoder_info", @handle, "frames")

  -> codec
    ccall("w_media_decoder_info", @handle, "codec")

  -> decode_seconds
    ccall("w_media_decoder_info", @handle, "decode_s")

  -> close
    ccall("w_media_decoder_close", @handle)


# Transcode — decode, scale, encode and mux in one pass: share copies, 4K masters,
# the resolution ladder and verticals, with chapters, timecode and audio carried through.
+ Transcode
  -> .opt(opts, key, fallback)
    if opts == nil || !opts.has_key?(key) || opts[key] == nil
      return fallback
    opts[key]

  # name -> options. Bitrates in bits per second.
  -> .presets
    {"share" => {width: 1280, height: 720, codec: "h264", bitrate: 2500000, audio: "aac", audio_kbps: 128, gop_seconds: 2,
                 level_cap: "4.0", note: "studio share copy"},
     "480p" => {width: 854, height: 480, codec: "h264", bitrate: 2500000, audio: "aac", audio_kbps: 128, level_cap: "3.1"},
     "720p" => {width: 1280, height: 720, codec: "h264", bitrate: 5000000, audio: "aac", audio_kbps: 192, level_cap: "4.0"},
     "1080p" => {width: 1920, height: 1080, codec: "h264", bitrate: 8000000, audio: "copy", level_cap: "4.2"},
     "1440p" => {width: 2560, height: 1440, codec: "h264", bitrate: 16000000, audio: "copy", level_cap: "5.1"},
     "2160p" => {width: 3840, height: 2160, codec: "h264", bitrate: 40000000, audio: "copy", level_cap: "5.2"},
     "4320p" => {width: 7680, height: 4320, codec: "hevc", bitrate: 120000000, audio: "copy", level_cap: "6.2"},
     "vertical" => {width: 1080, height: 1920, codec: "h264", bitrate: 8000000, audio: "aac", audio_kbps: 192, fit: "cover", level_cap: "4.2"},
     "vertical_pad" => {width: 1080, height: 1920, codec: "h264", bitrate: 8000000, audio: "aac", audio_kbps: 192, fit: "contain", level_cap: "4.2"},
     "vertical4k" => {width: 2160, height: 3840, codec: "h264", bitrate: 40000000, audio: "copy", fit: "cover", level_cap: "5.2"}}

  -> .preset_name(name)
    n = name.to_s
    n = "2160p" if n == "4k" || n == "uhd" || n == "youtube4k"
    n = "4320p" if n == "8k"
    n = "1080p" if n == "hd"
    n

  -> .preset(name)
    p = Transcode.presets[Transcode.preset_name(name)]
    if p == nil
      raise "Transcode: unknown preset '[name]' ([Transcode.presets.keys.join(", ")])"
    p

  # H.264 levels (Table A-1): [name, level_idc, MaxMBPS, MaxFS, MaxBR kb/s (High = 1.25 x)].
  -> .h264_levels
    [["3.0", 30, 40500, 1620, 10000], ["3.1", 31, 108000, 3600, 14000], ["3.2", 32, 216000, 5120, 20000],
     ["4.0", 40, 245760, 8192, 20000], ["4.1", 41, 245760, 8192, 50000], ["4.2", 42, 522240, 8704, 50000],
     ["5.0", 50, 589824, 22080, 135000], ["5.1", 51, 983040, 36864, 240000], ["5.2", 52, 2073600, 36864, 240000]]

  # HEVC Main tier (Table A.8): [name, general_level_idc, MaxLumaPs, MaxLumaSr, MaxBR kb/s].
  -> .hevc_levels
    [["3", 90, 552960, 16588800, 6000], ["3.1", 93, 983040, 33177600, 10000], ["4", 120, 2228224, 66846720, 12000],
     ["4.1", 123, 2228224, 133693440, 20000], ["5", 150, 8912896, 267386880, 25000], ["5.1", 153, 8912896, 534773760, 40000],
     ["5.2", 156, 8912896, 1069547520, 60000], ["6", 180, 35651584, 1069547520, 60000], ["6.1", 183, 35651584, 2139095040, 120000],
     ["6.2", 186, 35651584, 4278190080, 240000]]

  # The lowest level row that holds w x h at rate (and bits/s when given):
  # [name, idc, ...] or nil.
  -> .min_level(codec, w, h, rate, bits = nil)
    r = Timecode.rate(rate)
    if codec.to_s == "h264"
      mbw = (w + 15) / 16
      mbh = (h + 15) / 16
      fs = mbw * mbh
      rows = Transcode.h264_levels
      i = 0
      while i < rows.size
        l = rows[i]
        lim = Math.sqrt((l[3] * 8).to_f)
        okb = bits == nil || bits.to_f * ~1.5 <= l[4].to_f * ~1250.0
        if fs <= l[3] && fs * r[0] <= l[2] * r[1] && mbw.to_f <= lim && mbh.to_f <= lim && okb
          return l
        i += 1
      return nil
    ps = w * h
    rows = Transcode.hevc_levels
    i = 0
    while i < rows.size
      l = rows[i]
      lim = Math.sqrt((l[2] * 8).to_f)
      okb = bits == nil || bits.to_f <= l[4].to_f * ~1000.0
      if ps <= l[2] && ps * r[0] <= l[3] * r[1] && w.to_f <= lim && h.to_f <= lim && okb
        return l
      i += 1
    nil

  # The level row named `name` (or with level_idc `name`) for codec, or nil.
  -> .level_row(codec, name)
    rows = codec.to_s == "h264" ? Transcode.h264_levels : Transcode.hevc_levels
    i = 0
    while i < rows.size
      if rows[i][0] == name.to_s || rows[i][1] == name
        return rows[i]
      i += 1
    nil

  -> .wav?(path)
    s = path.to_s
    s.size >= 4 && s[(s.size - 4)...s.size].downcase == ".wav"

  # Source facts the copy needs: rate, frames, chapters (frames), tc frame.
  -> .source_facts(src, rate = nil)
    f = MediaVerify.facts(src, false, false)
    r = rate
    if r == nil
      md = f[:min_frame_duration]
      raise "Transcode: [src] has no video frame duration; pass rate:" if md == nil
      r = Timecode.rate([md[1], md[0]])
    r = Timecode.rate(r)
    vd = f[:video_duration]
    frames = 0
    if vd != nil
      frames = (vd[0] * r[0] * 2 + vd[1] * r[1]) / (2 * vd[1] * r[1])
    chapters = []
    if f[:chapters] != nil
      f[:chapters].each ->(c)
        st = c[1]
        if st != nil && c[0] != nil
          chapters << [c[0], (st[0] * r[0] * 2 + st[1] * r[1]) / (2 * st[1] * r[1])]
    flags = f[:timecode_flags] == nil ? 0 : f[:timecode_flags]
    {rate: r, frames: frames, chapters: chapters, tc: f[:timecode_frame], drop: flags % 2 == 1, facts: f}

  # Transcode.run(src, dst, opts) -> {frames:, seconds:, fps:, file_bytes:, ...}
  # src: a movie or an Array of segment files (then rate: and, for sound,
  # audio_src: are needed). Options (a preset: fills in the rest): width,
  # height, fit (:stretch, :contain, :cover), crop, rect, filter
  # (:lanczos3), scale_backend (:auto), via (:yuv, :rgb), codec, quality or
  # bitrate, level (H.264; default: the lowest that fits), gop or
  # gop_seconds, reorder, speed, format, audio (:copy, :aac, :pcm, false),
  # audio_src, audio_kbps, chapters (:copy, an Array, false), tc (:copy, a
  # label, false), start, frames, rate, faststart, progress (true: a line
  # every ~10 s of video).
  -> .run(src, dst, opts = {})
    o = {}
    pn = Transcode.opt(opts, :preset, nil)
    if pn != nil
      p = Transcode.preset(pn)
      p.keys.each ->(k)
        o[k] = p[k]
    if opts != nil
      opts.keys.each ->(k)
        o[k] = opts[k]
    movie = type(src) != "Array"
    if movie && File.expand_path(src.to_s) == File.expand_path(dst.to_s)
      raise "Transcode: [dst] is the source; write a new file"
    sf = nil
    rate = Transcode.opt(o, :rate, nil)
    if movie
      sf = Transcode.source_facts(src, rate)
      rate = sf[:rate]
    if rate == nil
      raise "Transcode: segments need rate:"
    rate = Timecode.rate(rate)
    start = Transcode.opt(o, :start, 0)
    total = Transcode.opt(o, :frames, nil)
    if total == nil
      if !movie
        total = 0
        src.each ->(s)
          seg = VideoSegment.load(s)
          total += seg.frames
          seg.release
      else
        total = sf[:frames] - start
    if total <= 0
      raise "Transcode: nothing to do ([total] frames)"
    # size and geometry
    dec_w = 0
    dec_h = 0
    if movie
      dec_w = sf[:facts][:width]
      dec_h = sf[:facts][:height]
    else
      seg = VideoSegment.load(src[0])
      dec_w = seg.width
      dec_h = seg.height
      seg.release
    w = Transcode.opt(o, :width, dec_w)
    h = Transcode.opt(o, :height, dec_h)
    g = Scaler.fit(dec_w, dec_h, w, h, Transcode.opt(o, :fit, "stretch"))
    codec = Transcode.opt(o, :codec, "h264").to_s
    gop = Transcode.opt(o, :gop, nil)
    if gop == nil
      gs = Transcode.opt(o, :gop_seconds, nil)
      gop = gs == nil ? (rate[0] + rate[1]) / (2 * rate[1]) : (gs * rate[0] + rate[1] / 2) / rate[1]
    gop = 1 if gop < 1
    bitrate = Transcode.opt(o, :bitrate, nil)
    quality = Transcode.opt(o, :quality, nil)
    bitrate = nil if quality != nil && !opts.has_key?(:bitrate)
    level = Transcode.opt(o, :level, nil)
    if level == nil && codec == "h264"
      row = Transcode.min_level("h264", w, h, rate, bitrate)
      level = row == nil ? "auto" : row[0]
    # chapters and timecode
    chapters = Transcode.opt(o, :chapters, "copy")
    chs = []
    if chapters.to_s == "copy" && movie
      sf[:chapters].each ->(c)
        f = c[1] - start
        if f <= 0
          chs = [[c[0], 0]]
        elsif f < total
          chs << [c[0], f]
    elsif type(chapters) == "Array"
      chs = chapters
    tc = Transcode.opt(o, :tc, "copy")
    tc_frame = nil
    drop = Timecode.drop_frame?(rate)
    if tc.to_s == "copy"
      if movie && sf[:tc] != nil
        tc_frame = sf[:tc] + start
        drop = sf[:drop]
      elsif !movie
        tc_frame = 0
    elsif tc != false && tc != nil
      label = tc.to_s
      if label.size == 11
        label = label[0...8] + (drop ? ";" : ":") + label[9...11]
      tc_frame = Timecode.parse(label, rate)
    audio_src = Transcode.opt(o, :audio_src, nil)
    audio = Transcode.opt(o, :audio, movie ? "copy" : (audio_src != nil ? "aac" : nil))
    audio = nil if audio == false
    if audio != nil && audio.to_s == "copy" && (start > 0 || (audio_src != nil && Transcode.wav?(audio_src)))
      audio = "aac"
    if audio != nil && movie && audio_src == nil && (sf[:facts][:audio_tracks] == nil || sf[:facts][:audio_tracks] == 0)
      audio = nil
    spec = [["src", src], ["dst", dst], ["rate", rate], ["start", start], ["frames", total], ["width", w], ["height", h],
            ["crop", Transcode.opt(o, :crop, g[:crop])], ["rect", Transcode.opt(o, :rect, g[:rect])],
            ["filter", Transcode.opt(o, :filter, "lanczos3").to_s], ["scale_backend", Transcode.opt(o, :scale_backend, "auto").to_s],
            ["via", Transcode.opt(o, :via, "yuv").to_s], ["codec", codec], ["quality", quality], ["bitrate", bitrate],
            ["level", level == nil ? nil : level.to_s], ["gop", gop], ["reorder", Transcode.opt(o, :reorder, true)],
            ["speed", Transcode.opt(o, :speed, false)], ["format", Transcode.opt(o, :format, nil)],
            ["audio", audio == nil ? nil : audio.to_s], ["audio_src", audio_src], ["audio_kbps", Transcode.opt(o, :audio_kbps, nil)],
            ["tc", tc_frame], ["drop", drop], ["quanta", Timecode.quanta(rate)], ["chapters", chs],
            ["faststart", Transcode.opt(o, :faststart, true)]]
    t0 = clock()
    th = ccall("w_media_transcode_new", spec)
    done = false
    res = nil
    progress = Transcode.opt(o, :progress, false)
    step = rate[0] * 10 / rate[1]
    step = 240 if step < 240
    begin
      d = [0, total]
      while d[0] < d[1]
        d = ccall("w_media_transcode_step", th, step)
        if progress
          << "  [d[0]] / [d[1]] frames, [((clock() - t0) * ~10.0).round.to_f / ~10.0] s"
      pairs = ccall("w_media_transcode_finish", th)
      done = true
      res = {}
      pairs.each ->(pr)
        res[pr[0].to_sym] = pr[1]
    ensure
      ccall("w_media_transcode_free", th) if !done
    res[:fps] = res[:frames].to_f / res[:seconds]
    res[:path] = dst
    res[:rate] = rate
    res[:width] = w
    res[:height] = h
    res[:codec] = codec
    res[:level] = level
    res[:bitrate] = bitrate
    res[:quality] = quality
    res[:chapters] = chs
    res[:tc_start] = tc_frame == nil ? nil : Timecode.to_smpte(tc_frame, rate, drop)
    res[:audio] = audio
    res

  # MediaVerify.check plus codec/size/level checks for a preset or explicit
  # options (width:, height:, codec:, level_cap:). Pass MediaVerify's options
  # too (rate:, frames:, tc_start:, chapters:, audio: ...).
  -> .check(path, opts = {})
    o = {}
    pn = Transcode.opt(opts, :preset, nil)
    if pn != nil
      p = Transcode.preset(pn)
      p.keys.each ->(k)
        o[k] = p[k]
    if opts != nil
      opts.keys.each ->(k)
        o[k] = opts[k]
    r = MediaVerify.check(path, o)
    f = r[:facts]
    codec = Transcode.opt(o, :codec, nil)
    if codec != nil
      want4cc = codec.to_s == "h264" ? "avc1" : "hvc1"
      prof_ok = codec.to_s == "h264" ? f[:profile] == 100 : f[:profile] == 1
      w = Transcode.opt(o, :width, f[:width])
      h = Transcode.opt(o, :height, f[:height])
      rate = r[:rate]
      bits = nil
      if f[:video_bytes] != nil && r[:frames] > 0 && rate != nil
        bits = f[:video_bytes] * 8 * rate[0] / (r[:frames] * rate[1])
      need = rate == nil ? nil : Transcode.min_level(codec, w, h, rate, nil)
      cap = Transcode.opt(o, :level_cap, nil)
      caprow = cap == nil ? nil : Transcode.level_row(codec, cap)
      lvl = f[:level]
      ok = f[:codec] == want4cc && prof_ok && f[:bit_depth] == 8 && f[:chroma_format] == 1 && f[:width] == w && f[:height] == h
      ok = ok && need != nil && lvl != nil && lvl >= need[1] && (caprow == nil || lvl <= caprow[1])
      maxbr = nil
      if lvl != nil
        lr = Transcode.level_row(codec, lvl)
        maxbr = lr == nil ? nil : (codec.to_s == "h264" ? lr[4] * 1250 : lr[4] * 1000)
        ok = ok && (bits == nil || maxbr == nil || bits <= maxbr)
      lname = lvl == nil ? "?" : (codec.to_s == "h264" ? (lvl / 10).to_s + "." + (lvl % 10).to_s : (lvl / 30).to_s + "." + ((lvl % 30) / 3).to_s)
      detail = "[f[:codec]] profile [f[:profile]] level [lname] (idc [lvl]; the picture needs >= [need == nil ? "?" : need[0]][cap == nil ? "" : ", cap " + cap.to_s]), [f[:bit_depth]]-bit chroma_format [f[:chroma_format]], [f[:width]]x[f[:height]] (want [w]x[h])"
      detail = detail + ", [bits == nil ? "?" : (bits / 1000).to_s] kb/s average (level max [maxbr == nil ? "?" : (maxbr / 1000).to_s])"
      r[:checks] << {name: "preset", ok: ok, detail: detail}
      r[:ok] = r[:ok] && ok
    r
