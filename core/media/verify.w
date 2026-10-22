# MediaVerify — read a master back with AVFoundation and check the A/V
# contract of studio TIMELINE.md section 2.
#
#   r = MediaVerify.check("master.mp4", rate: [24, 1], tc_start: "00:00:00:00")
#   << MediaVerify.format(r)      # PASS/FAIL per check, with the measured values
#   r[:ok]
#
#   t = MediaVerify.sync_test("sync.mp4")             # flashes + clicks + colour bars
#   r = MediaVerify.check("sync.mp4", sync: true, flashes: t[:flashes], bars: true)
#
# Checks (each one {name:, ok:, detail:}):
#   video     one video track, one sample description, every sample read
#   cfr       every sample lasts den/num s exactly; nominal rate matches
#   pts       sorted presentation times (sample PTS through the track's edit
#             list) are exactly frame x den/num, integers in the track
#             timescale, starting at 0
#   frames    the frame count (when frames: is given)
#   timecode  a tmcd track associated with the video, starting at tc_start,
#             drop-frame flag and frame quanta right for the rate, spanning
#             every frame (skipped with tc_start: nil)
#   audio     audio starts at 0, lasts as long as the video, and decodes to
#             exactly frames x rate x den / num samples (audio: false skips)
#   colour    container tags BT.709 primaries/transfer/matrix, not full
#             range, chroma location stated; the SPS VUI says 1/1/1, limited
#             range and the same chroma_sample_loc_type
#   faststart the moov box precedes the media data
#   sync      (sync: true) every flash frame has a click at its first sample,
#             within +-1 sample, and the flash frames are the expected ones
#   bars      (bars: true, files from sync_test) the decoded Y'CbCr of each bar
#             matches BT.709 limited-range codes (and not BT.601's), and the
#             RGB a player gets back is the RGB encoded

+ MediaVerify
  -> .opt(opts, key, fallback)
    if opts == nil || !opts.has_key?(key) || opts[key] == nil
      return fallback
    opts[key]

  # The raw facts as a Hash with Symbol keys (see runtime/media/media_avf.m).
  -> .facts(path, samples = true, audio = true)
    pairs = ccall("w_media_probe", path, samples, audio)
    h = {}
    pairs.each ->(p)
      h[p[0].to_sym] = p[1]
    h

  # 75% colour bars of sync_test, bottom third, left to right.
  -> .bars
    [[191, 191, 191], [191, 191, 0], [0, 191, 191], [0, 191, 0], [191, 0, 191], [191, 0, 0], [0, 0, 191], [0, 0, 0]]

  -> .rational_eq?(a, b)
    a != nil && b != nil && a[0] * b[1] == b[0] * a[1]

  -> .check(path, opts = {})
    want_audio = MediaVerify.opt(opts, :audio, true)
    f = MediaVerify.facts(path, true, want_audio)
    checks = []
    rate = nil
    if opts != nil && opts.has_key?(:rate) && opts[:rate] != nil
      rate = Timecode.rate(opts[:rate])
    elsif f[:min_frame_duration] != nil
      md = f[:min_frame_duration]
      rate = Timecode.rate([md[1], md[0]])
    frames = f[:frames] == nil ? 0 : f[:frames]

    # video
    vok = f[:video_tracks] == 1 && f[:sample_descriptions] == 1 && f[:read_status] == 2
    checks << {name: "video", ok: vok,
               detail: "[f[:video_tracks]] video track(s), [f[:sample_descriptions]] sample description(s), [f[:codec]] [f[:width]]x[f[:height]], read status [f[:read_status]]"}
    ts = f[:timescale]
    ticks = 0
    if rate != nil && ts != nil && (ts * rate[1]) % rate[0] == 0
      ticks = ts * rate[1] / rate[0]

    # cfr
    durs = f[:durations]
    bad_dur = 0
    odd = ""
    if durs != nil
      di = 0
      while di < durs.size
        if durs[di] != ticks
          bad_dur += 1
          odd = " (sample [di] lasts [durs[di]])" if odd == ""
        di += 1
    fps_ok = rate != nil && f[:nominal_fps] != nil && MediaVerify.near(f[:nominal_fps], rate[0].to_f / rate[1].to_f, ~0.001)
    checks << {name: "cfr", ok: ticks > 0 && bad_dur == 0 && fps_ok && frames > 0,
               detail: "rate [rate == nil ? "?" : rate[0].to_s + "/" + rate[1].to_s], timescale [ts], [ticks] ticks a frame, [bad_dur] of [frames] durations differ[odd], nominal [f[:nominal_fps]] fps"}

    # pts
    bad_pts = 0
    first_bad = -1
    pts = f[:pts]
    first_pts = nil
    shift = f[:video_edit_offset] == nil ? 0 : f[:video_edit_offset]
    if pts != nil && ticks > 0
      sorted = pts.sort
      if shift != 0
        k = 0
        while k < sorted.size
          sorted[k] = sorted[k] + shift
          k += 1
      first_pts = sorted.size > 0 ? sorted[0] : nil
      i = 0
      while i < sorted.size
        if sorted[i] != i * ticks
          bad_pts += 1
          first_bad = i if first_bad < 0
        i += 1
    pdetail = "[frames] PTS (through the edit list, [shift] ticks) checked against frame x [ticks]/[ts]: [bad_pts] off"
    pdetail = pdetail + " (first at sample [first_bad]; the first PTS is [first_pts] ticks)" if first_bad >= 0
    pdetail = pdetail + ", [f[:inexact_times]] not representable in the track timescale" if f[:inexact_times] != nil && f[:inexact_times] > 0
    checks << {name: "pts", ok: ticks > 0 && bad_pts == 0 && f[:inexact_times] == 0 && frames > 0, detail: pdetail}

    # frames
    if opts != nil && opts.has_key?(:frames) && opts[:frames] != nil
      checks << {name: "frames", ok: frames == opts[:frames], detail: "[frames] frames, expected [opts[:frames]]"}

    # timecode
    want_tc = "00:00:00:00"
    if opts != nil && opts.has_key?(:tc_start)
      want_tc = opts[:tc_start]
    if want_tc != nil && rate != nil
      drop = MediaVerify.opt(opts, :drop, Timecode.drop_frame?(rate))
      label = want_tc.to_s
      if label.size == 11
        label = label[0...8] + (drop ? ";" : ":") + label[9...11]
      want_frame = Timecode.parse(label, rate)
      tc_frames = -1
      tdur = f[:timecode_duration]
      if tdur != nil && (tdur[0] * rate[0]) % (tdur[1] * rate[1]) == 0
        tc_frames = tdur[0] * rate[0] / (tdur[1] * rate[1])
      flags = f[:timecode_flags] == nil ? 0 : f[:timecode_flags]
      tok = f[:timecode_tracks] == 1 && f[:timecode_frame] == want_frame && (flags % 2 == 1) == drop
      tok = tok && f[:timecode_quanta] == Timecode.quanta(rate) && tc_frames == frames
      tok = tok && f[:timecode_associated] != nil && f[:timecode_associated] >= 1
      got = f[:timecode_frame] == nil ? "none" : Timecode.to_smpte(f[:timecode_frame], rate, flags % 2 == 1)
      checks << {name: "timecode", ok: tok,
                 detail: "[f[:timecode_tracks]] tmcd track(s), start [got] (frame [f[:timecode_frame]]), expected [Timecode.to_smpte(want_frame, rate, drop)]; [flags % 2 == 1 ? "drop" : "non-drop"], quanta [f[:timecode_quanta]], spans [tc_frames] of [frames] frames, associated [f[:timecode_associated]]"}

    # audio
    if want_audio
      sr = f[:audio_rate]
      want_samples = sr == nil || rate == nil ? -1 : Timecode.samples(frames, rate, sr)
      got_samples = f[:audio_decoded_frames]
      start_ok = f[:audio_start] != nil && f[:audio_start][0] == 0
      dur_ok = MediaVerify.rational_eq?(f[:audio_duration], f[:video_duration])
      aok = f[:audio_tracks] == 1 && start_ok && dur_ok && got_samples == want_samples
      ad = f[:audio_duration]
      vd = f[:video_duration]
      checks << {name: "audio", ok: aok,
                 detail: "[f[:audio_tracks]] audio track(s) [f[:audio_codec]] [sr] Hz x [f[:audio_channels]]; [got_samples] samples decoded, expected [want_samples]; duration [ad] vs video [vd]; [f[:audio_edits]] edit(s), media starts at [f[:audio_edit_media_start]]"}

    # colour
    siting = MediaVerify.opt(opts, :siting, "left").to_s
    loc_name = "Left"
    loc_code = 0
    if siting == "center"
      loc_name = "Center"
      loc_code = 1
    elsif siting == "topleft"
      loc_name = "TopLeft"
      loc_code = 2
    cok = f[:primaries] == "ITU_R_709_2" && f[:transfer] == "ITU_R_709_2" && f[:matrix] == "ITU_R_709_2" && f[:full_range] != true
    cok = cok && (f[:chroma_location] == loc_name || f[:codec] == "apcn" || f[:codec] == "apch" || f[:codec] == "apcs" || f[:codec] == "apco")
    vd = ""
    if f[:vui_present] != nil
      vok2 = f[:vui_ok] == true && f[:vui_present] == true && f[:vui_primaries] == 1 && f[:vui_transfer] == 1 && f[:vui_matrix] == 1 && f[:vui_full_range] == 0
      vok2 = vok2 && (f[:vui_chroma_loc] == loc_code || (loc_code == 0 && f[:vui_chroma_loc] == -1))
      cok = cok && vok2
      vd = "; SPS VUI primaries/transfer/matrix [f[:vui_primaries]]/[f[:vui_transfer]]/[f[:vui_matrix]], full_range [f[:vui_full_range]], chroma_sample_loc [f[:vui_chroma_loc]] (profile [f[:profile]], level [f[:level]], [f[:bit_depth]]-bit)"
    checks << {name: "colour", ok: cok,
               detail: "container [f[:primaries]] / [f[:transfer]] / [f[:matrix]], full range [f[:full_range]], chroma [f[:chroma_location]]" + vd}

    # faststart
    if MediaVerify.opt(opts, :faststart, true)
      checks << {name: "faststart", ok: f[:moov_first] == true, detail: "moov before mdat: [f[:moov_first]] (brand [f[:brand]])"}

    if MediaVerify.opt(opts, :sync, false) && rate != nil
      checks << MediaVerify.sync_check(path, rate, opts)
    if MediaVerify.opt(opts, :bars, false)
      checks << MediaVerify.bars_check(path, f, opts)

    ok = true
    checks.each ->(c)
      ok = false if !c[:ok]
    {ok: ok, path: path, rate: rate, frames: frames, checks: checks, facts: f}

  -> .near(a, b, tol)
    d = a.to_f - b.to_f
    d = ~0.0 - d if d < ~0.0
    d <= tol

  # Flash frames (mean luma above the midpoint of the darkest and brightest
  # frame) against click peaks.
  -> .sync_check(path, rate, opts)
    scan = ccall("w_media_sync_scan", path, MediaVerify.opt(opts, :sync_frames, nil), nil)
    lum = scan[0]
    clicks = scan[1]
    sr = scan[2]
    lo = ~1000.0
    hi = ~0.0
    lum.each ->(v)
      lo = v if v < lo
      hi = v if v > hi
    flashes = []
    if hi - lo > ~40.0
      mid = (lo + hi) / ~2.0
      i = 0
      while i < lum.size
        flashes << i if lum[i] > mid
        i += 1
    worst = ~0.0
    offs = []
    ok = flashes.size > 0 && flashes.size == clicks.size
    i = 0
    while i < flashes.size && i < clicks.size
      want = Timecode.samples(flashes[i], rate, sr)
      off = clicks[i] - want.to_f
      offs << off
      a = off < ~0.0 ? ~0.0 - off : off
      worst = a if a > worst
      ok = false if a > ~1.0
      i += 1
    expect = MediaVerify.opt(opts, :flashes, nil)
    frames_ok = expect == nil || expect == flashes
    ok = ok && frames_ok
    shown = flashes.size > 6 ? flashes[0...6].to_s + "…" : flashes.to_s
    {name: "sync", ok: ok,
     detail: "[flashes.size] flash frame(s) [shown], [clicks.size] click(s); worst click offset [MediaVerify.round3(worst)] samples at [sr] Hz; flash frames [frames_ok ? "as expected (0 frames off)" : "differ from " + expect.to_s]"}

  -> .round3(x)
    (x * ~1000.0).round.to_f / ~1000.0

  # Bars of sync_test: native Y'CbCr codes against BT.709 and BT.601, and the
  # decoded RGB against the encoded RGB.
  -> .bars_check(path, f, opts)
    w = f[:width]
    h = f[:height]
    frame = MediaVerify.opt(opts, :bars_frame, 0)
    bars = MediaVerify.bars
    pts = []
    i = 0
    while i < bars.size
      pts << [(2 * i + 1) * w / 16, h * 5 / 6]
      i += 1
    ten = f[:bit_depth] != nil && f[:bit_depth] > 8
    prores = f[:codec] == "apcn" || f[:codec] == "apch" || f[:codec] == "apcs" || f[:codec] == "apco"
    bits = ten || prores ? 10 : 8
    yuv = ccall("w_media_frame_probe", path, [frame], pts, "yuv")[0]
    rgb = ccall("w_media_frame_probe", path, [frame], pts, "rgb")[0]
    q709 = YCbCr.bt709(bits)
    q601 = YCbCr.bt601(bits)
    e709 = 0
    e601 = 0
    ergb = 0
    i = 0
    while i < bars.size
      b = bars[i]
      a = q709.encode_rgb8(b[0], b[1], b[2])
      c = q601.encode_rgb8(b[0], b[1], b[2])
      k = 0
      while k < 3
        d1 = (yuv[i][k] - a[k]).abs
        d2 = (yuv[i][k] - c[k]).abs
        d3 = (rgb[i][k] - b[k]).abs
        e709 = d1 if d1 > e709
        e601 = d2 if d2 > e601
        ergb = d3 if d3 > ergb
        k += 1
      i += 1
    tol = bits == 10 ? 8 : 2
    ok = e709 <= tol && e601 > 3 * tol && ergb <= 4
    {name: "bars", ok: ok,
     detail: "decoded [bits]-bit Y'CbCr of 8 bars at frame [frame]: max error [e709] codes against BT.709 limited range, [e601] against BT.601; decoded RGB within [ergb]/255 of the encoded RGB"}

  # PASS/FAIL lines.
  -> .format(r)
    out = []
    out << "[r[:path]]: [r[:ok] ? "OK" : "FAILED"]"
    r[:checks].each ->(c)
      out << "  [c[:ok] ? "PASS" : "FAIL"] [c[:name]]: [c[:detail]]"
    out.join("\n")

  # Write a test master: black frames with a white flash in the top two
  # thirds every two seconds, 75% colour bars in the bottom third, and a
  # click (a 9-sample raised-cosine peak) at the first audio sample of each
  # flash frame. Options: rate ([24, 1]), seconds (10), width (1280), height
  # (720), codec (:h264), quality (0.8), gop (48), audio_codec, tc_start
  # ("00:00:00:00"), wav (path.wav), reorder (the encoder's default), promise (true: tell the mux the frame
  # count up front). Returns {path:, frames:, flashes:,
  # clicks:, sample_rate:, wav:, mux:}.
  -> .sync_test(path, opts = {})
    rate = Timecode.rate(MediaVerify.opt(opts, :rate, [24, 1]))
    w = MediaVerify.opt(opts, :width, 1280)
    h = MediaVerify.opt(opts, :height, 720)
    q = Timecode.quanta(rate)
    total = MediaVerify.opt(opts, :seconds, 10) * q
    gop = MediaVerify.opt(opts, :gop, 48)
    sr = 48000
    flashes = []
    fr = q / 2
    while fr < total
      flashes << fr
      fr += 2 * q
    bars = i64[24]
    i = 0
    MediaVerify.bars.each ->(b)
      bars[i] = b[0]
      bars[i + 1] = b[1]
      bars[i + 2] = b[2]
      i += 3
    dark = u8[w * h * 4]
    lit = u8[w * h * 4]
    media_paint(dark, w, h, 0, bars)
    media_paint(lit, w, h, 255, bars)
    enc = VideoEncoder.new(w, h, codec: MediaVerify.opt(opts, :codec, "h264"), rate: rate, gop: gop,
                           quality: MediaVerify.opt(opts, :quality, ~0.8), reorder: MediaVerify.opt(opts, :reorder, nil))
    segs = []
    k = 0
    f = 0
    while f < total
      px = dark
      if k < flashes.size && flashes[k] == f
        px = lit
        k += 1
      enc.encode(px)
      if (f + 1) % gop == 0 || f == total - 1
        segs << enc.segment
      f += 1
    enc.close
    n = Timecode.samples(total, rate, sr)
    clicks = []
    flashes.each ->(x)
      clicks << Timecode.samples(x, rate, sr)
    wav = MediaVerify.opt(opts, :wav, path + ".wav")
    MediaVerify.write_click_wav(wav, n, sr, clicks)
    promise = MediaVerify.opt(opts, :promise, true) ? total : nil
    mux = Mux.new(path, rate: rate, audio: wav, audio_codec: MediaVerify.opt(opts, :audio_codec, nil),
                  tc_start: MediaVerify.opt(opts, :tc_start, "00:00:00:00"), frames: promise)
    segs.each ->(s)
      mux.append(s)
      s.release
    r = mux.close
    {path: path, frames: total, flashes: flashes, clicks: clicks, sample_rate: sr, wav: wav, mux: r}

  # A stereo 24-bit WAV of n samples, silent except a raised-cosine click
  # peaking (0.9 full scale) at each listed sample.
  -> .write_click_wav(path, n, sr, clicks)
    ch = 2
    data = n * ch * 3
    buf = u8[44 + data]
    media_wav_header(buf, n, ch, sr)
    at = i64[clicks.size]
    i = 0
    clicks.each ->(c)
      at[i] = c
      i += 1
    media_wav_clicks(buf, n, ch, at, clicks.size)
    File.write_bytes(path, buf)
    path


-> media_put_le(buf, o, v, n) (u8[] i64 i64 i64) i64
  i = 0
  x = v
  while i < n
    buf[o + i] = x & 255
    x = x >> 8
    i += 1
  n

-> media_wav_header(buf, n, ch, sr) (u8[] i64 i64 i64) i64
  data = n * ch * 3
  buf[0] = 82
  buf[1] = 73
  buf[2] = 70
  buf[3] = 70
  media_put_le(buf, 4, 36 + data, 4)
  buf[8] = 87
  buf[9] = 65
  buf[10] = 86
  buf[11] = 69
  buf[12] = 102
  buf[13] = 109
  buf[14] = 116
  buf[15] = 32
  media_put_le(buf, 16, 16, 4)
  media_put_le(buf, 20, 1, 2)
  media_put_le(buf, 22, ch, 2)
  media_put_le(buf, 24, sr, 4)
  media_put_le(buf, 28, sr * ch * 3, 4)
  media_put_le(buf, 32, ch * 3, 2)
  media_put_le(buf, 34, 24, 2)
  buf[36] = 100
  buf[37] = 97
  buf[38] = 116
  buf[39] = 97
  media_put_le(buf, 40, data, 4)
  44

# 0.5 + 0.5 cos(pi j / 5), j = -4..4, scaled to 0.9 x 2^23.
-> media_wav_clicks(buf, n, ch, at, count) (u8[] i64 i64 i64[] i64) i64
  shape = f64[9]
  shape[0] = ~0.0954915028125263
  shape[1] = ~0.3454915028125263
  shape[2] = ~0.6545084971874737
  shape[3] = ~0.9045084971874737
  shape[4] = ~1.0
  shape[5] = ~0.9045084971874737
  shape[6] = ~0.6545084971874737
  shape[7] = ~0.3454915028125263
  shape[8] = ~0.0954915028125263
  k = 0
  while k < count
    j = 0
    while j < 9
      s = at[k] + j - 4
      if s >= 0 && s < n
        amp = shape[j] * ~0.9 * ~8388607.0 + ~0.5
        v = amp ## i64
        c = 0
        while c < ch
          media_put_le(buf, 44 + (s * ch + c) * 3, v, 3)
          c += 1
      j += 1
    k += 1
  count

-> media_paint(px, w, h, top, bars) (u8[] i64 i64 i64 i64[]) i64
  split = (h * 2) / 3
  y = 0
  while y < h
    x = 0
    while x < w
      o = (y * w + x) * 4
      if y >= split
        c = (x * 8) / w
        px[o] = bars[c * 3]
        px[o + 1] = bars[c * 3 + 1]
        px[o + 2] = bars[c * 3 + 2]
      else
        px[o] = top
        px[o + 1] = top
        px[o + 2] = top
      px[o + 3] = 255
      x += 1
    y += 1
  w * h
