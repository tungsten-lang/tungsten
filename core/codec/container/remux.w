# core/codec/container/remux — copy the tracks of one or more media files into
# a single MP4 or WebM, without re-encoding (separate DASH/HLS/MSE video and
# audio streams → one playable file).
#
#   info = media_remux(["video.mp4", "audio.webm"], "out.mp4")           # format from the extension
#   info = media_remux(inputs, "out.webm", "webm", ctrl)                 # ctrl: i64[4] or nil
#   media_remux_format(cfgs)                                             # "mp4", "webm" or nil
#
# Each input is demuxed incrementally from disk (1 MB reads; an MP4 whose moov
# follows its mdat is handled by seeking), so files of any size stream through
# in bounded memory. The first video track and the first audio track found
# (in input order) are kept. Samples are written interleaved by decode time.
# ctrl (shared with another thread): [0] set to 1 cancels, [1] bytes read so
# far, [2] total input bytes, [3] samples written. Returns {bytes:, duration:,
# tracks:} or raises MediaError.

+ RemuxInput
  rw :path, :fh, :size, :pos, :demux, :queue, :done, :vt, :at, :error

  -> new(@path)
    @fh = File.open(@path, "rb")
    @size = File.size(@path)
    @pos = 0
    @demux = nil
    @queue = []
    @done = false
    @vt = nil
    @at = nil
    @error = nil
    @chosen = false

  # Read and demux the next MB; false at the end.
  -> step(ctrl)
    return false if @done
    n = 1048576
    n = @size - @pos if @pos + n > @size
    if n <= 0
      @demux.finish if @demux != nil
      take()
      @done = true
      return false
    b = @fh.read(n)
    if b == nil || b.size == 0
      @demux.finish if @demux != nil
      take()
      @done = true
      return false
    bb = dm_bytes(b)
    if @demux == nil
      @demux = demux_for(bb)
      raise MediaError.new("remux: unrecognised format: " + @path) if @demux == nil
    @demux.append(bb)
    ccall("w_value_free_w", bb) if bb != b
    @pos += b.size
    ctrl[1] = ctrl[1] + b.size if ctrl != nil
    @demux.parse
    raise MediaError.new("remux: " + @demux.error) if @demux.error != nil
    wo = @demux.want_offset
    if wo != nil
      @demux.restart(wo)
      @fh.seek(wo)
      @pos = wo
    take()
    true

  # Queue what the demuxer produced: everything until the tracks are chosen
  # (select then filters), afterwards only the chosen tracks.
  -> take
    return nil if @demux == nil
    @demux.take.each ->(ts)
      if !@chosen || (@vt != nil && ts[0] == @vt.id) || (@at != nil && ts[0] == @at.id)
        @queue.push(ts)
      else
        ccall("w_value_free_w", ts[1].data)
    nil

  -> select(vt, at)
    @vt = vt
    @at = at
    @chosen = true
    keep = []
    @queue.each ->(ts)
      if (@vt != nil && ts[0] == @vt.id) || (@at != nil && ts[0] == @at.id)
        keep.push(ts)
      else
        ccall("w_value_free_w", ts[1].data)
    @queue = keep
    nil

  -> close
    @fh.close

# "mp4" when every codec can go in an MP4, else "webm" when WebM can hold them all, else nil.
-> media_remux_format(cfgs)
  return "mp4" if cfgs.all?(->(c) Mp4Muxer.supports?(c.codec))
  return "webm" if cfgs.all?(->(c) WebmMuxer.supports?(c.codec))
  nil

-> media_remux(paths, out, format = nil, ctrl = nil)
  inputs = paths.map(->(p) RemuxInput.new(p))
  total = 0
  inputs.each ->(i) total += i.size
  ctrl[2] = total if ctrl != nil
  # read until every input knows its tracks
  vt = nil
  at = nil
  inputs.each ->(inp)
    while inp.demux == nil || !inp.demux.ready?
      break if !inp.step(ctrl)
    if inp.demux != nil && inp.demux.ready?
      mv = nil
      ma = nil
      inp.demux.tracks.each ->(t)
        if t.kind == :video && vt == nil
          vt = t
          mv = t
        elsif t.kind == :audio && at == nil
          at = t
          ma = t
      inp.take
      inp.select(mv, ma)
    else
      inp.select(nil, nil)
  raise MediaError.new("remux: no tracks") if vt == nil && at == nil
  cfgs = []
  cfgs.push(vt.cfg) if vt != nil
  cfgs.push(at.cfg) if at != nil
  if format == nil
    format = out.downcase.ends_with?(".webm") ? "webm" : "mp4"
  ok = format == "webm" ? cfgs.all?(->(c) WebmMuxer.supports?(c.codec)) : cfgs.all?(->(c) Mp4Muxer.supports?(c.codec))
  raise MediaError.new("remux: " + cfgs.map(->(c) c.codec.strip).join("+") + " cannot go in " + format) if !ok
  m = format == "webm" ? WebmMuxer.new(out) : Mp4Muxer.new(out)
  vi = vt == nil ? -1 : m.add_track(:video, vt.cfg)
  ai = at == nil ? -1 : m.add_track(:audio, at.cfg)
  written = 0
  running = true
  while running
    if ctrl != nil && ctrl[0] == 1
      inputs.each ->(i) i.close
      raise MediaError.new("remux: cancelled")
    # keep a sample queued from every input that still has data
    inputs.each ->(inp)
      while inp.queue.size == 0 && !inp.done
        inp.step(ctrl)
    best = nil
    inputs.each ->(inp)
      if inp.queue.size > 0
        s = inp.queue[0][1]
        best = inp if best == nil || s.dts < best.queue[0][1].dts
    if best == nil
      running = false
    else
      ts = best.queue[0]
      best.queue = best.queue.copy(1, best.queue.size - 1)
      ti = (best.vt != nil && ts[0] == best.vt.id) ? vi : ai
      m.write(ti, ts[1])
      ccall("w_value_free_w", ts[1].data)
      written += 1
      ctrl[3] = written if ctrl != nil
  inputs.each ->(i) i.close
  format == "webm" ? m.finish : m.finish(true)
