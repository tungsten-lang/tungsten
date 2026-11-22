# core/codec/container/demux — what every container demuxer shares: a growing byte buffer,
# tracks, and the sniffing entry point.
#
# A demuxer is incremental (progressive download and MSE appends feed it in
# pieces):
#
#   d = demux_for(first_bytes)        # MP4 / WebM / Ogg / WAV / MP3 / ADTS / FLAC, or nil
#   d.append(bytes)                   # ByteArray, any size, in file order
#   d.parse                           # consume what is complete
#   d.ready?                          # tracks known (init segment / headers seen)
#   d.tracks                          # Array of MediaTrack
#   d.take                            # Array of [track_id, MediaSample] parsed since the last take
#   d.duration                        # seconds (Float) or nil
#   d.want_offset                     # a byte offset the loader should continue from (MP4 moov after mdat), or nil
#   d.seek_offset(t)                  # byte offset to restart loading from to play from t (nil: unknown)
#   d.restart(offset)                 # the next append starts at this file offset (after a seek)
#   d.finish                          # end of stream (EsDemuxer parses only then)
#   d.error                           # a String after a fatal parse error
#
# Samples carry their data (a ByteArray copy). Timestamps are presentation
# seconds after the container's edit list / codec delay (priming samples get
# negative pts; the player drops them).

+ MediaTrack
  rw :id, :kind, :cfg, :duration, :lang, :label, :default, :timescale, :delay

  -> new(@id, @kind, @cfg)
    @duration = nil
    @lang = nil
    @label = nil
    @default = true
    @timescale = 1000
    @delay = ~0.0

  -> video?
    @kind == :video

  -> audio?
    @kind == :audio

# ---- byte helpers (typed: these run per box / per element) ----

-> dm_copy(dst, doff, src, soff, n) (u8[] i64 u8[] i64 i64) i64
  i = 0
  while i < n
    dst[doff + i] = src[soff + i]
    i += 1
  n

-> dm_be16(b, o) (u8[] i64) i64
  (b[o] << 8) | b[o + 1]

-> dm_be24(b, o) (u8[] i64) i64
  (b[o] << 16) | (b[o + 1] << 8) | b[o + 2]

-> dm_be32(b, o) (u8[] i64) i64
  (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]

-> dm_be64(b, o) (u8[] i64) i64
  (dm_be32(b, o) << 32) | dm_be32(b, o + 4)

-> dm_le16(b, o) (u8[] i64) i64
  b[o] | (b[o + 1] << 8)

-> dm_le32(b, o) (u8[] i64) i64
  b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24)

-> dm_le64(b, o) (u8[] i64) i64
  dm_le32(b, o) | (dm_le32(b, o + 4) << 32)

-> dm_s32(v)
  v >= 2147483648 ? v - 4294967296 : v

-> dm_fourcc(b, o)
  s = StringBuffer()
  i = 0
  while i < 4
    s.append(b[o + i].chr)
    i += 1
  s.to_s

-> dm_slice(b, off, n)
  n = 0 if n < 0
  out = ByteArray.new(n)
  dm_copy(out, 0, b, off, n) if n > 0
  out

-> dm_ascii(b, off, n)
  s = StringBuffer()
  i = 0
  while i < n
    c = b[off + i]
    s.append(c.chr) if c != 0
    i += 1
  s.to_s

# IEEE-754 binary32 / binary64 from raw bits (big-endian fields in MP4/EBML).
-> dm_f32_bits(v)
  return ~0.0 if (v & 0x7FFFFFFF) == 0
  s = (v >> 31) == 1 ? ~-1.0 : ~1.0
  e = (v >> 23) & 0xFF
  m = v & 0x7FFFFF
  return s * ~1.0e300 * ~1.0e300 if e == 255
  return s * m.to_f * (~2.0 ** -149) if e == 0
  s * (~1.0 + m.to_f / ~8388608.0) * (~2.0 ** (e - 127))

-> dm_f64_bits(v)
  return ~0.0 if (v & 0x7FFFFFFFFFFFFFFF) == 0
  s = ((v >> 63) & 1) == 1 ? ~-1.0 : ~1.0
  e = (v >> 52) & 0x7FF
  m = v & 0xFFFFFFFFFFFFF
  return s * ~1.0e300 * ~1.0e300 if e == 2047
  return s * m.to_f * (~2.0 ** -1074) if e == 0
  s * (~1.0 + m.to_f / ~4503599627370496.0) * (~2.0 ** (e - 1023))

# CodecConfig.extra for "pcm " (a helper keeps the Hash out of callers' locals).
-> pcm_extra(bits, is_float, big_endian)
  {bits: bits, float: is_float, big_endian: big_endian}

# "mp4a.40.N" from an AudioSpecificConfig, else the codec id.
-> mp4a_codec_string(codec, asc)
  return codec.strip if codec != "mp4a" || asc == nil || !asc.is_a?(ByteArray) || asc.size < 1
  "mp4a.40." + (asc[0] >> 3).to_s

# A ByteArray from a String body (net.w responses are Strings of bytes).
-> dm_bytes(s)
  return s if !s.is_a?(String)
  v = ccall("w_string_bytes_view", s) ## u8[]
  dm_slice(v, 0, v.size)

# ---- a growing buffer addressed by absolute file offset ----

+ MBuf
  ro :base, :len, :data

  -> new
    @data = ByteArray.new(65536)
    @base = 0
    @len = 0

  # Absolute end offset of what is buffered.
  -> limit
    @base + @len

  -> append(bytes)
    n = bytes.size
    return nil if n == 0
    if @len + n > @data.size
      cap = @data.size * 2
      cap = cap * 2 while cap < @len + n
      nd = ByteArray.new(cap)
      dm_copy(nd, 0, @data, 0, @len)
      # no collector: the outgrown buffer is released here
      ccall("w_value_free_w", @data)
      @data = nd
    dm_copy(@data, @len, bytes, 0, n)
    @len += n
    nil

  -> has?(abs, n)
    abs >= @base && abs + n <= @base + @len

  # Drop bytes before abs (they will not be read again).
  -> discard(abs)
    return nil if abs <= @base
    k = abs - @base
    k = @len if k > @len
    # compact only when it frees a good share (avoid copying every append)
    if k >= 1048576 || k * 2 >= @len
      rest = @len - k
      dm_copy(@data, 0, @data, k, rest) if rest > 0
      @len = rest
      @base += k
    nil

  # Forget everything; the next byte appended is at file offset abs.
  -> reset(abs)
    @base = abs
    @len = 0
    nil

  -> off(abs)
    abs - @base

  -> u8(abs)
    @data[abs - @base]

  -> be16(abs)
    dm_be16(@data, abs - @base)

  -> be24(abs)
    dm_be24(@data, abs - @base)

  -> be32(abs)
    dm_be32(@data, abs - @base)

  -> be64(abs)
    dm_be64(@data, abs - @base)

  -> slice(abs, n)
    dm_slice(@data, abs - @base, n)

# Base class: buffer, samples out, tracks.
+ Demuxer
  ro :tracks, :duration, :error, :want_offset, :kind

  -> init_demuxer(kind)
    @kind = kind
    @buf = MBuf.new
    @tracks = []
    @out = []
    @duration = nil
    @error = nil
    @want_offset = nil
    @ready = false

  -> append(bytes)
    @buf.append(bytes)

  -> ready?
    @ready

  -> take
    o = @out
    @out = []
    o

  -> track(id)
    @tracks.each ->(t)
      return t if t.id == id
    nil

  -> emit(tid, s)
    @out.push([tid, s])

  -> seek_offset(t)
    nil

  # The stream has ended (no more appends).
  -> finish
    parse

  -> restart(off)
    @buf.reset(off)

  -> fail(msg)
    @error = msg if @error == nil
    nil

# Sniff a container from its first bytes. Elementary streams whose codec owns
# the parser (MP3, ADTS, FLAC) are handled by demux_es.
-> demux_sniff(b)
  n = b.size
  return nil if n < 4
  return :webm if b[0] == 0x1A && b[1] == 0x45 && b[2] == 0xDF && b[3] == 0xA3
  return :ogg if b[0] == 0x4F && b[1] == 0x67 && b[2] == 0x67 && b[3] == 0x53
  if n >= 12
    t = dm_fourcc(b, 4)
    return :mp4 if t == "ftyp" || t == "moov" || t == "styp" || t == "moof" || t == "sidx" || t == "free" || t == "skip" || t == "wide" || (t == "mdat" && n >= 16)
    return :wav if dm_fourcc(b, 0) == "RIFF" && dm_fourcc(b, 8) == "WAVE"
  return :flac if b[0] == 0x66 && b[1] == 0x4C && b[2] == 0x61 && b[3] == 0x43
  return :mp3 if b[0] == 0x49 && b[1] == 0x44 && b[2] == 0x33
  return :adts if b[0] == 0xFF && (b[1] & 0xF6) == 0xF0
  return :mp3 if b[0] == 0xFF && (b[1] & 0xE0) == 0xE0
  return demux_sniff_more(b)

# Containers added later (MPEG-TS, AIFF, CAF), tried after the ones above.
-> demux_sniff_more(b)
  n = b.size
  return :ts if n >= 377 && b[0] == 0x47 && b[188] == 0x47 && b[376] == 0x47
  return :ts if n >= 389 && b[4] == 0x47 && b[196] == 0x47 && b[388] == 0x47
  return :aiff if n >= 12 && dm_fourcc(b, 0) == "FORM" && (dm_fourcc(b, 8) == "AIFF" || dm_fourcc(b, 8) == "AIFC")
  return :caf if n >= 8 && dm_fourcc(b, 0) == "caff"
  return :ac3 if n >= 6 && b[0] == 0x0B && b[1] == 0x77 && (b[5] >> 3) <= 16
  nil

# MIME type → container kind (for MSE and <source type>).
-> demux_kind_for_mime(mime)
  m = mime.downcase
  semi = m.index(";")
  m = m.slice(0, semi) if semi != nil
  m = m.strip
  return :mp4 if m == "video/mp4" || m == "audio/mp4" || m == "audio/x-m4a" || m == "video/quicktime" || m == "audio/aac+mp4"
  return :webm if m == "video/webm" || m == "audio/webm" || m == "video/x-matroska" || m == "audio/x-matroska"
  return :ogg if m == "video/ogg" || m == "audio/ogg" || m == "application/ogg" || m == "audio/opus"
  return :wav if m == "audio/wav" || m == "audio/wave" || m == "audio/x-wav" || m == "audio/vnd.wave"
  return :mp3 if m == "audio/mpeg" || m == "audio/mp3"
  return :adts if m == "audio/aac" || m == "audio/aacp" || m == "audio/x-aac"
  return :flac if m == "audio/flac" || m == "audio/x-flac"
  return :ts if m == "video/mp2t" || m == "audio/mp2t" || m == "video/mpeg2-ts"
  return :aiff if m == "audio/aiff" || m == "audio/x-aiff"
  return :caf if m == "audio/x-caf"
  return :ac3 if m == "audio/ac3" || m == "audio/eac3" || m == "audio/ec3"
  return :hls if m == "application/vnd.apple.mpegurl" || m == "application/x-mpegurl" || m == "audio/mpegurl" || m == "audio/x-mpegurl"
  nil

-> demux_new(kind)
  return Mp4Demuxer.new if kind == :mp4
  return WebmDemuxer.new if kind == :webm
  return OggDemuxer.new if kind == :ogg
  return WavDemuxer.new if kind == :wav
  return EsDemuxer.new(kind) if kind == :mp3 || kind == :adts || kind == :flac || kind == :ac3
  return TsDemuxer.new if kind == :ts
  return AiffDemuxer.new(kind) if kind == :aiff || kind == :caf
  nil

-> demux_for(first_bytes)
  k = demux_sniff(first_bytes)
  k == nil ? nil : demux_new(k)
