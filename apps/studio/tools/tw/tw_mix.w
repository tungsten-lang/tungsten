# The film's mix as the master takes it (Tungsten, no ffmpeg): render/mix.wav (tools/mix.py, already loudness-normalised
# to -16 LUFS / -1.5 dBTP by its loudnorm pass) copied sample for sample into a 24-bit 48 kHz stereo WAV of exactly the
# picture's length (frames x 2000 samples: cut, or padded with silence), then measured with the studio engine's
# BS.1770-4 integrated loudness and 4x-oversampled true peak (apps/studio/lib/audio.w, as the Numbers master measures).
# The samples are not touched unless --level is given: then the engine's leveling (a linear gain to --lufs and the
# true-peak look-ahead limiter at --tp less --margin, as engine/master.w of the Numbers series) is applied instead.
#
#   tw_mix <in.wav> <out.wav> <frames> [--fps 24] [--lufs -16] [--tp -1.5] [--margin 0.3] [--level]
# Prints one "key value" line per fact. Compile with the ceil worktree's Tungsten (tools/tw_render.sh does).

use ../../lib/audio

-> arg_of(args, name, fallback)
  i = 0
  while i + 1 < args.size
    return args[i + 1] if args[i] == name
    i += 1
  fallback

# 24-bit stereo PCM (from byte offset off, frames of it) into an interleaved f32 bus of n frames (zeros past the end).
-> s24_bus(u, off, frames, n, bus) (u8[] i64 i64 i64 f32[]) i64
  m = frames
  m = n if m > n
  i = 0
  while i < m * 2
    p = off + i * 3
    v = u[p] + u[p + 1] * 256 + u[p + 2] * 65536
    v = v - 16777216 if v >= 8388608
    bus[i] = ((v ## f64) / ~8388608.0) ## f32
    i += 1
  m

-> copy_u8(src, so, dst, n) (u8[] i64 u8[] i64) i64
  i = 0
  while i < n
    dst[i] = src[so + i]
    i += 1
  n

-> zero_u8(dst, n) (u8[] i64) i64
  i = 0
  while i < n
    dst[i] = 0
    i += 1
  n

# The source's sample bytes, cut or padded to n frames, under a canonical 44-byte header.
-> write_exact(src_path, info, out, n)
  frames = info[1] / 6
  data = n * 6
  hdr = u8[44]
  bytes = [82, 73, 70, 70] + le32(36 + data) + [87, 65, 86, 69, 102, 109, 116, 32] + le32(16) + [1, 0, 2, 0] + le32(48000) + le32(288000) + [6, 0, 24, 0, 100, 97, 116, 97] + le32(data)
  i = 0
  while i < 44
    hdr[i] = bytes[i]
    i += 1
  tmp = out + ".part"
  fh = FileHandle.new(tmp, "wb")
  fh.write(hdr)
  mm = File.mmap(src_path)
  u = mm.as_u8
  blk = 1048576
  buf = u8[blk * 6]
  f = 0
  while f < n
    k = [blk, n - f].min
    if k < blk
      buf = u8[k * 6]
    have = frames - f
    have = 0 if have < 0
    have = k if have > k
    zero_u8(buf, k * 6) if have < k
    copy_u8(u, info[0] + f * 6, buf, have * 6) if have > 0
    fh.write(buf)
    f += k
  fh.close
  mm.close
  File.rename(tmp, out)
  frames

-> dbtp(x)
  ~20.0 * Math.log(x) * ~0.4342944819032518

-> lufs_of(bus, n, zs, sub)
  integrated_lufs(zs, k_weight_blocks(bus, n, zs, sub))

-> copy_bus(a, b, n) (f32[] f32[] i64) i64
  i = 0
  while i < n
    b[i] = a[i]
    i += 1
  n

-> main(args)
  die("usage: tw_mix <in.wav> <out.wav> <frames> \[--fps 24] \[--lufs -16] \[--tp -1.5] \[--margin 0.3] \[--level]") if args.size < 3
  src = args[0]
  out = args[1]
  nfr = args[2].to_i
  fps = arg_of(args, "--fps", "24").to_i
  target = arg_of(args, "--lufs", "-16").to_f
  tp_db = arg_of(args, "--tp", "-1.5").to_f
  margin = arg_of(args, "--margin", "0.3").to_f
  level = args.include?("--level")
  t0 = clock_ms()
  info = wav_info(src)
  die("mix.wav: " + info[3].to_s + " Hz, expected 48000") if info[3] != 48000
  die("mix.wav: expected 24-bit stereo PCM") if info[5] || info[4] != 24 || info[2] != 2
  frames = info[1] / 6
  n = nfr * 48000 / fps
  bus = f32[n * 2]
  mm = File.mmap(src)
  s24_bus(mm.as_u8, info[0], frames, n, bus)
  mm.close
  sub = 4800
  zs = f64[n / sub + 1]
  h = f64[48]
  tp_taps(h)
  lufs_in = lufs_of(bus, n, zs, sub)
  tp_in = dbtp(true_peak(bus, n, h, ~0.0))
  << "source " + src + " frames " + frames.to_s + " (" + fixed6(frames.to_f / ~48000.0) + " s), picture " + nfr.to_s + " frames = " + n.to_s + " samples (" + (n - frames).to_s + " padded)"
  << "loudness " + fixed6(lufs_in) + " LUFS, true peak " + fixed6(tp_in) + " dBTP"
  if !level
    write_exact(src, info, out, n)
    << "samples copied unchanged -> " + out + " (" + (clock_ms() - t0).to_s + " ms)"
    return 0
  ceil = db_lin(tp_db - margin)
  src_bus = f32[n * 2]
  copy_bus(bus, src_bus, n * 2)
  g = f32[n]
  gain_db = target - lufs_in
  after = lufs_in
  passes = 0
  while passes < 4
    copy_bus(src_bus, bus, n * 2)
    bus_scale(bus, n * 2, db_lin(gain_db))
    tp_gain(bus, n, h, ceil, g)
    limit_apply(bus, n, g, 96, ~1.0 - Math.exp((~0.0 - ~1.0) / (~0.1 * ~48000.0)))
    after = lufs_of(bus, n, zs, sub)
    passes += 1
    break if (after - target).abs <= ~0.02
    gain_db = gain_db + (target - after)
  tp = dbtp(true_peak(bus, n, h, ceil * ~0.5))
  write_wav_s24(out, bus, n, 48000)
  << "leveled: gain " + fixed6(gain_db) + " dB, " + passes.to_s + " passes -> " + fixed6(after) + " LUFS, true peak " + fixed6(tp) + " dBTP -> " + out + " (" + (clock_ms() - t0).to_s + " ms)"
  0

main(argv())
