# studio/ncw — Native Instruments NCW (Kontakt's lossless "compressed wave") decoded to integer PCM, and PCM WAV / FLAC
# writers for `studio ncw2wav` (2026-11-03, for the Kirk Hunter Diamond library: 58,263 .ncw samples, no WAV twins).
#
# The format, as read from the files themselves (every field below was checked against the whole Diamond library:
# `studio ncw2wav --check`), all integers little-endian:
#
#   file header, 120 bytes
#     0  u32  magic 0xD69EA801 (bytes 01 A8 9E D6)
#     4  u32  version (0x130 and 0x131 met; the same layout)
#     8  u16  channels
#    10  u16  bits per sample (16 and 24 met)
#    12  u32  sample rate
#    16  u32  frames
#    20  u32  offset of the block table
#    24  u32  offset of the block data
#    28  u32  size of the block data
#    32  88 bytes not used here (writer's scratch: pointers, garbage)
#   block table: u32 offsets into the block data, one per block of 512 frames, plus one (= the data size)
#   a block: for each channel, a 16-byte header then 512 values of |w| bits packed LSB first (64·|w| bytes)
#     0  u32  magic 0x3E9A0C16
#     4  i32  base
#     8  i16  w: > 0 delta coding (s[0] = base, s[i] = s[i−1] + d[i−1]; d[511] is padding, always 0),
#                < 0 the samples themselves in |w| bits; 0 is not met and is rejected
#    10  u16  flags: 0 plain, 1 mid/side (stereo only; both channels carry it): L = M + S, R = M − S
#    12  u32  0
#   the last block holds frames mod 512 frames (the rest is padding).
#
# Checks behind the reading (Diamond library, 2026-11-03): `studio ncw2wav --check` over all 58,263 files (44.7 GB; 16- and
# 24-bit, mono and stereo, versions 0x130 and 0x131; 13.36 billion frames) decodes every one with every block valid: magic,
# widths 1..25 and raw -16/-24 (2,132 raw channel blocks), flags 0 or 1 on both channels (18.2 million mid/side blocks), every
# sample inside its bit depth, d[511] = 0 in every delta block (633 s, 234 MB peak). The second difference at block boundaries
# has the same median as inside blocks (no seam). At the 20,656 switches between plain and mid/side blocks in the English horn
# set, the reconstruction continues smoothly only with L = M + S, R = M - S (median jump 0.23 local steps against 0.76-1.7 for
# the other mid/side conventions). The library has no WAV or AIFF twin of any .ncw, so no bit-exact external reference exists;
# a mid/side block can only carry L and R of one parity, so this is the format's own reading, not a guess between equals.
# Decoded pitch and level agree with the file names (the Diamond maps measure every file: engine/tools/diamond_sfz.py).

NCW_MAGIC = 0xD69EA801
NCW_BLOCK_MAGIC = 0x3E9A0C16
NCW_HEADER = 120

-> ncw_u16(b, at) (u8[] i64) i64
  b[at] + b[at + 1] * 256

-> ncw_u32(b, at) (u8[] i64) i64
  b[at] + b[at + 1] * 256 + b[at + 2] * 65536 + b[at + 3] * 16777216

# [channels, bits, rate, frames, table offset, data offset, data size, version] of an NCW image; raises on anything else.
-> ncw_header(b)
  raise "ncw: too short for a header ([b.size] bytes)" if b.size < NCW_HEADER
  raise "ncw: not an NCW file (magic [ncw_u32(b, 0)])" if ncw_u32(b, 0) != NCW_MAGIC
  ch = ncw_u16(b, 8)
  bits = ncw_u16(b, 10)
  rate = ncw_u32(b, 12)
  frames = ncw_u32(b, 16)
  tab = ncw_u32(b, 20)
  dat = ncw_u32(b, 24)
  dsz = ncw_u32(b, 28)
  raise "ncw: [ch] channels" if ch < 1 || ch > 8
  raise "ncw: unsupported sample size [bits] bits" if bits != 16 && bits != 24
  raise "ncw: sample rate [rate]" if rate < 1
  nblk = (frames + 511) / 512
  raise "ncw: block table at [tab]..[dat] holds fewer than [nblk] blocks" if tab < NCW_HEADER || dat < tab + 4 * nblk
  raise "ncw: block data ([dat] + [dsz]) runs past the end ([b.size])" if dat + dsz > b.size
  [ch, bits, rate, frames, tab, dat, dsz, ncw_u32(b, 4)]

# The 512 values of one channel block, |w| = n bits each (1..32), packed LSB first from byte p of b, sign-extended (v >= 2^(n-1):
# v - 2^n), into vals[v0 .. v0 + 511]; reads exactly 64·n bytes and returns the byte after them. (2026-11-04, AV pipeline batch 1)
# It is ncw_chan's former Tungsten loop, the same integer arithmetic (`acc = acc + b[p] * (1 << na)`, `v = acc & mask`,
# `acc = acc >> n`) as one embedded-IR loop: profiled, that loop spent its time in boxed integer calls (w_add, w_bigint_*); here
# it is plain 64-bit arithmetic (the accumulator stays below 2^39). All 27,315 .ncw files the sfz maps name (12.4 billion
# samples) decode to the same samples; 41 -> 227 Msamples/s a process. Compiled only (as is the engine).
fn ncw_unpack(b, p, n, vals, v0) (u8[] i64 i64 i64[] i64) i64
  ll <<~IR
  entry:
    %pb = inttoptr i64 %b to ptr
    %pv = inttoptr i64 %vals to ptr
    %full = shl i64 1, %n
    %nm1 = sub i64 %n, 1
    %half = shl i64 1, %nm1
    %mask = sub i64 %full, 1
    br label %outer
  outer:
    %i = phi i64 [0, %entry], [%i1, %emit]
    %acc0 = phi i64 [0, %entry], [%acc2, %emit]
    %na0 = phi i64 [0, %entry], [%na2, %emit]
    %q0 = phi i64 [%p, %entry], [%q, %emit]
    br label %fill
  fill:
    %acc = phi i64 [%acc0, %outer], [%accn, %load]
    %na = phi i64 [%na0, %outer], [%nan, %load]
    %q = phi i64 [%q0, %outer], [%qn, %load]
    %need = icmp slt i64 %na, %n
    br i1 %need, label %load, label %emit
  load:
    %bp = getelementptr i8, ptr %pb, i64 %q
    %byte = load i8, ptr %bp, align 1
    %bz = zext i8 %byte to i64
    %sh = shl i64 %bz, %na
    %accn = add i64 %acc, %sh
    %qn = add i64 %q, 1
    %nan = add i64 %na, 8
    br label %fill
  emit:
    %v = and i64 %acc, %mask
    %acc2 = lshr i64 %acc, %n
    %na2 = sub i64 %na, %n
    %neg = icmp sge i64 %v, %half
    %vs = sub i64 %v, %full
    %vv = select i1 %neg, i64 %vs, i64 %v
    %idx = add i64 %v0, %i
    %vp = getelementptr i64, ptr %pv, i64 %idx
    store i64 %vv, ptr %vp, align 8
    %i1 = add i64 %i, 1
    %more = icmp slt i64 %i1, 512
    br i1 %more, label %outer, label %done
  done:
    ret i64 %q
  IR

# One channel's block at byte `at` (data ends at `fin`) into vals[v0 .. v0 + 511]. Returns the byte after it, or a negative
# code: −1 bad block magic, −2 bad width, −3 truncated. meta[0] = flags; meta[1] += 1 when a delta block's pad is non-zero,
# meta[2] += 1 for a raw (w < 0) block.
-> ncw_chan(b, at, fin, vals, v0, meta) (u8[] i64 i64 i64[] i64 i64[]) i64
  if at < 0 || at + 16 > fin
    return -3
  if ncw_u32(b, at) != 0x3E9A0C16
    return -1
  base = ncw_u32(b, at + 4)
  if base >= 2147483648
    base = base - 4294967296
  w = ncw_u16(b, at + 8)
  if w >= 32768
    w = w - 65536
  meta[0] = ncw_u16(b, at + 10)
  n = w
  if n < 0
    n = 0 - n
    meta[2] = meta[2] + 1
  if n == 0 || n > 32
    return -2
  p = at + 16
  q = p + 64 * n
  if q > fin
    return -3
  ncw_unpack(b, p, n, vals, v0)
  if w > 0
    if vals[v0 + 511] != 0
      meta[1] = meta[1] + 1
    s = base
    i = 0
    while i < 512
      d = vals[v0 + i]
      vals[v0 + i] = s
      s = s + d
      i += 1
  q

# Decode every block into interleaved samples out[frame · ch + c]. Returns 0, or a negative code with err[0] = the code,
# err[1] = the block, err[2] = the channel: −1..−3 as ncw_chan, −4 unknown flags, −5 a sample outside the bit depth.
# err[3] counts delta blocks with a non-zero pad value, err[4] mid/side blocks, err[5] raw (w < 0) channel blocks.
-> ncw_decode_into(b, ch, bits, frames, tab, dat, fin, out, err) (u8[] i64 i64 i64 i64 i64 i64 i32[] i64[]) i64
  vals = i64[512 * ch]
  meta = i64[3]
  ncw_decode_scratch(b, ch, bits, frames, tab, dat, fin, out, err, vals, meta)

# the same with the caller's scratch: vals (≥ 512 · ch values) and meta (3), for batches that must not allocate per file
-> ncw_decode_scratch(b, ch, bits, frames, tab, dat, fin, out, err, vals, meta) (u8[] i64 i64 i64 i64 i64 i64 i32[] i64[] i64[] i64[]) i64
  nblk = (frames + 511) / 512
  meta[0] = 0
  meta[1] = 0
  meta[2] = 0
  lim = 1 << (bits - 1)
  k = 0
  while k < nblk
    at = dat + ncw_u32(b, tab + 4 * k)
    fl = 0
    c = 0
    while c < ch
      at = ncw_chan(b, at, fin, vals, c * 512, meta)
      if at < 0
        err[0] = at
        err[1] = k
        err[2] = c
        return at
      if c == 0
        fl = meta[0]
      elsif meta[0] != fl
        err[0] = -4
        err[1] = k
        err[2] = c
        return -4
      c += 1
    if fl == 1 && ch == 2
      err[4] = err[4] + 1
      i = 0
      while i < 512
        m = vals[i]
        s = vals[512 + i]
        vals[i] = m + s
        vals[512 + i] = m - s
        i += 1
    elsif fl != 0
      err[0] = -4
      err[1] = k
      err[2] = 0
      return -4
    cnt = frames - k * 512
    if cnt > 512
      cnt = 512
    i = 0
    while i < cnt
      c = 0
      while c < ch
        v = vals[c * 512 + i]
        if v >= lim || v < 0 - lim
          err[0] = -5
          err[1] = k
          err[2] = c
          return -5
        out[(k * 512 + i) * ch + c] = v
        c += 1
      i += 1
    k += 1
  err[3] = err[3] + meta[1]
  err[5] = err[5] + meta[2]
  0

-> ncw_error_text(code)
  return "bad block magic" if code == -1
  return "bad block bit width" if code == -2
  return "truncated block" if code == -3
  return "unknown block flags" if code == -4
  return "sample outside the bit depth" if code == -5
  "error " + code.to_s

# Decode an NCW image: {ch, bits, rate, frames, version, pcm (i32[] interleaved), pads, ms_blocks, raw_blocks}. Raises on a
# malformed file, naming the block.
-> ncw_decode(b)
  h = ncw_header(b)
  ch = h[0]
  frames = h[3]
  out = i32[frames * ch]
  err = i64[6]
  r = ncw_decode_into(b, ch, h[1], frames, h[4], h[5], h[5] + h[6], out, err)
  raise "ncw: " + ncw_error_text(r) + " (block [err[1]], channel [err[2]])" if r != 0
  {ch: ch, bits: h[1], rate: h[2], frames: frames, version: h[7], pcm: out, pads: err[3], ms_blocks: err[4], raw_blocks: err[5]}

-> ncw_read(path)
  ncw_decode(File.read_bytes(path))

# Batches (studio ncw2wav over a directory): one state reused for every file, so memory stays flat. ncw_decode_batch fills
# st[:pcm] (grown when a file needs more; valid until the next call) and returns the same fields as ncw_decode.
-> ncw_batch_new
  {pcm: i32[1], vals: i64[4096], meta: i64[3], err: i64[6], wr: ncw_writer_new()}

-> ncw_decode_batch(st, b)
  h = ncw_header(b)
  ch = h[0]
  frames = h[3]
  if st[:pcm].size < frames * ch
    st[:pcm] = i32[frames * ch + frames * ch / 4]
  err = st[:err]
  k = 0
  while k < 6
    err[k] = 0
    k += 1
  r = ncw_decode_scratch(b, ch, h[1], frames, h[4], h[5], h[5] + h[6], st[:pcm], err, st[:vals], st[:meta])
  raise "ncw: " + ncw_error_text(r) + " (block [err[1]], channel [err[2]])" if r != 0
  {ch: ch, bits: h[1], rate: h[2], frames: frames, version: h[7], pcm: st[:pcm], pads: err[3], ms_blocks: err[4], raw_blocks: err[5]}

# ---------------------------------------------------------------------------------------------- WAV

-> ncw_le(buf, at, v, n) (u8[] i64 i64 i64) i64
  i = 0
  while i < n
    buf[at + i] = (v >> (8 * i)) & 255
    i += 1
  at + n

# Samples pcm[s0 .. s0 + n) as little-endian (bits / 8)-byte integers into buf.
-> ncw_pack(pcm, s0, n, bps, buf) (i32[] i64 i64 i64 u8[]) i64
  i = 0
  o = 0
  while i < n
    v = pcm[s0 + i]
    buf[o] = v & 255
    buf[o + 1] = (v >> 8) & 255
    if bps == 3
      buf[o + 2] = (v >> 16) & 255
    o += bps
    i += 1
  o

-> ncw_put(buf, at, xs)
  i = 0
  while i < xs.size
    buf[at + i] = xs[i]
    i += 1
  at + xs.size

-> ncw_wav_header(ch, rate, bits, data)
  bps = bits / 8
  pad = data % 2
  h = u8[44]
  ncw_put(h, 0, [82, 73, 70, 70])
  ncw_le(h, 4, 36 + data + pad, 4)
  ncw_put(h, 8, [87, 65, 86, 69, 102, 109, 116, 32])
  ncw_le(h, 16, 16, 4)
  ncw_le(h, 20, 1, 2)
  ncw_le(h, 22, ch, 2)
  ncw_le(h, 24, rate, 4)
  ncw_le(h, 28, rate * ch * bps, 4)
  ncw_le(h, 32, ch * bps, 2)
  ncw_le(h, 34, bits, 2)
  ncw_put(h, 36, [100, 97, 116, 97])
  ncw_le(h, 40, data, 4)
  h

# Pack buffers for the WAV writer: for 2- and 3-byte samples, one buffer of 2^k samples for each k = 0..18, allocated on first
# use and reused, so a file of any length is written as full 2^18-sample blocks plus one block per set bit of the rest.
-> ncw_writer_new
  {b2: [], b3: [], pad: u8[1]}

-> ncw_writer_buf(wr, bps, k)
  key = :b2
  key = :b3 if bps == 3
  if wr[key].size == 0
    j = 0
    while j <= 18
      wr[key].push(u8[(1 << j) * bps])
      j += 1
  wr[key][k]

# A PCM WAV (format 1, 16- or 24-bit, the decoded channels interleaved as they are) written to path + ".part", then renamed.
-> write_wav_pcm(path, pcm, frames, ch, rate, bits)
  write_wav_pcm_w(ncw_writer_new(), path, pcm, frames, ch, rate, bits)

-> write_wav_pcm_w(wr, path, pcm, frames, ch, rate, bits)
  bps = bits / 8
  data = frames * ch * bps
  tmp = path + ".part"
  fh = FileHandle.new(tmp, "wb")
  fh.write(ncw_wav_header(ch, rate, bits, data))
  total = frames * ch
  s = 0
  full = 1 << 18
  while total - s >= full
    buf = ncw_writer_buf(wr, bps, 18)
    ncw_pack(pcm, s, full, bps, buf)
    fh.write(buf)
    s += full
  k = 17
  while k >= 0
    if ((total - s) >> k) & 1 == 1
      buf = ncw_writer_buf(wr, bps, k)
      ncw_pack(pcm, s, 1 << k, bps, buf)
      fh.write(buf)
      s += 1 << k
    k -= 1
  if data % 2 == 1
    fh.write(wr[:pad])
  fh.close
  File.rename(tmp, path)
  path

# ---------------------------------------------------------------------------------------------- `studio ncw2wav`

-> ncw_strip_slash(p)
  while p.size > 1 && p.ends_with?("/")
    p = p.slice(0, p.size - 1)
  p

# every .ncw under dir (depth first, names sorted; symbolic links to directories not followed)
-> ncw_find(dir, out)
  ents = File.children(dir).sort
  i = 0
  while i < ents.size
    e = ents[i]
    if e != "." && e != ".."
      p = dir + "/" + e
      if File.directory?(p) && !File.symlink?(p)
        ncw_find(p, out)
      elsif e.ends_with?(".ncw") && File.file?(p)
        out.push(p)
    i += 1
  out

# studio ncw2wav <in.ncw | dir> <out.wav | dir> [--check] [--force]
# One file, or a directory walked depth-first and mirrored under the output directory (x/y.ncw → out/x/y.wav). The WAV keeps the
# NCW's sample rate, bit depth and channels; outputs that exist are skipped (resumable; --force rewrites them), each is written to
# <name>.wav.part and renamed. --check decodes every file and writes nothing. Prints one line per failure and a summary; returns
# 1 when any file failed.
-> ncw2wav_cli(args)
  check = args.include?("--check")
  force = args.include?("--force")
  pos = []
  i = 1
  while i < args.size
    pos.push(args[i]) if !args[i].starts_with?("--")
    i += 1
  if pos.size < 1 || (pos.size < 2 && !check)
    << "usage: studio ncw2wav <in.ncw|dir> <out.wav|dir> \[--force]   |   studio ncw2wav <in.ncw|dir> --check"
    return 2
  src = ncw_strip_slash(pos[0])
  dst = ""
  dst = ncw_strip_slash(pos[1]) if pos.size >= 2
  files = []
  single = !File.directory?(src)
  if single
    files.push(src)
  else
    files = ncw_find(src, [])
  done = 0
  skipped = 0
  failed = 0
  frames = 0
  bytes_in = 0
  bytes_out = 0
  ms = 0
  raw = 0
  pads = 0
  kinds = {}
  made = {}
  st = ncw_batch_new()
  k = 0
  while k < files.size
    p = files[k]
    out = dst
    if !single
      rel = p.slice(src.size + 1, p.size - src.size - 1)
      out = dst + "/" + rel.slice(0, rel.size - 4) + ".wav"
    if !check && !force && File.exist?(out)
      skipped += 1
    else
      mm = nil
      begin
        mm = File.mmap(p)
        b = mm.as_u8
        d = ncw_decode_batch(st, b)
        bytes_in += b.size
        frames += d[:frames]
        ms += d[:ms_blocks]
        raw += d[:raw_blocks]
        pads += d[:pads]
        kk = d[:ch].to_s + "ch/" + d[:bits].to_s + "bit/" + d[:rate].to_s + "Hz/v" + d[:version].to_s
        if kinds.has_key?(kk)
          kinds[kk] = kinds[kk] + 1
        else
          kinds[kk] = 1
        if !check
          od = File.dirname(out)
          if !made.has_key?(od)
            File.mkdir_p(od)
            made[od] = 1
          write_wav_pcm_w(st[:wr], out, d[:pcm], d[:frames], d[:ch], d[:rate], d[:bits])
          bytes_out += File.size(out)
        mm.close
        done += 1
      rescue e
        mm.close if mm != nil
        failed += 1
        << "FAILED " + p + ": " + e.to_s
    k += 1
  ks = kinds.keys.sort
  desc = []
  i = 0
  while i < ks.size
    desc.push(ks[i] + " " + kinds[ks[i]].to_s)
    i += 1
  verb = "wrote"
  verb = "decoded" if check
  << "ncw2wav: [files.size] files: [verb] [done], skipped [skipped] (output exists), failed [failed]; [frames] frames; NCW [bytes_in] bytes -> WAV [bytes_out] bytes; mid/side blocks [ms], raw blocks [raw], non-zero delta pads [pads]; " + desc.join(", ")
  return 1 if failed > 0
  0
