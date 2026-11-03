# apps/studio/lib/ncw.w: Kontakt NCW decoding and the PCM WAV writer behind `studio ncw2wav`.
# The NCW images here are built by a small encoder in this spec (the format notes are in ncw.w's header), so every block type
# and width the Kirk Hunter Diamond library uses is exercised without shipping any sample data: delta blocks (widths 1..25),
# raw blocks (width -16, -24), mid/side blocks (flags 1, also with one channel raw), a partial last block, mono and stereo,
# 16 and 24 bits, both header versions; then the WAV bytes, determinism, and every malformed-file error.

use ../../apps/studio/lib/ncw

-> fail_check(name, detail)
  << "FAIL: " + name + " " + detail
  exit(1)

-> check(name, got, want)
  if got != want
    fail_check(name, "got=" + got.to_s + " want=" + want.to_s)

# ---- a minimal encoder (test only) ----------------------------------------------------------------------------------------
-> le(out, v, n)
  i = 0
  while i < n
    out.push((v >> (8 * i)) & 255)
    i += 1
  out

# 512 signed values, w bits each, packed LSB first
-> pack(out, vals, w)
  acc = 0
  na = 0
  mask = (1 << w) - 1
  i = 0
  while i < 512
    acc = acc | ((vals[i] & mask) << na)
    na += w
    while na >= 8
      out.push(acc & 255)
      acc = acc >> 8
      na -= 8
    i += 1
  out

# one channel block: w > 0 deltas (s[i+1] - s[i], the last 0), w < 0 the samples in |w| bits
-> chan_block(out, s, w, flags)
  le(out, 0x3E9A0C16, 4)
  le(out, s[0], 4)
  le(out, w, 2)
  le(out, flags, 2)
  le(out, 0, 4)
  vals = []
  if w > 0
    i = 0
    while i < 511
      vals.push(s[i + 1] - s[i])
      i += 1
    vals.push(0)
    pack(out, vals, w)
  else
    pack(out, s, 0 - w)
  out

# blocks: one spec per block, [mode, w0, w1]: mode 0 plain, 1 mid/side (stereo); chans: per channel 512·nblk values
-> make_ncw(chans, bits, frames, blocks, version)
  ch = chans.size
  nb = blocks.size
  data = []
  offs = []
  k = 0
  while k < nb
    offs.push(data.size)
    sp = blocks[k]
    seg = []
    c = 0
    while c < ch
      seg.push(chans[c].slice(k * 512, 512))
      c += 1
    if sp[0] == 1
      m = []
      sd = []
      i = 0
      while i < 512
        m.push((seg[0][i] + seg[1][i]) / 2)
        sd.push((seg[0][i] - seg[1][i]) / 2)
        i += 1
      seg = [m, sd]
    c = 0
    while c < ch
      chan_block(data, seg[c], sp[1 + c], sp[0])
      c += 1
    k += 1
  offs.push(data.size)
  tab = 120
  dat = tab + 4 * offs.size
  h = []
  le(h, 0xD69EA801, 4)
  le(h, version, 4)
  le(h, ch, 2)
  le(h, bits, 2)
  le(h, 44100, 4)
  le(h, frames, 4)
  le(h, tab, 4)
  le(h, dat, 4)
  le(h, data.size, 4)
  while h.size < 120
    h.push(0xA5)
  i = 0
  while i < offs.size
    le(h, offs[i], 4)
    i += 1
  all = h + data
  b = u8[all.size]
  i = 0
  while i < all.size
    b[i] = all[i]
    i += 1
  b

# a smooth test signal whose 512-sample steps stay inside w-bit deltas
-> wave(n, amp, per, ph)
  out = []
  i = 0
  while i < n
    out.push((amp * Math.sin(~6.283185307179586 * i.to_f / per + ph)).round.to_i)
    i += 1
  out

-> expect_raise(name, b, text)
  got = ""
  begin
    ncw_decode(b)
  rescue e
    got = e.to_s
  if !got.include?(text)
    fail_check(name, "expected an error with '" + text + "', got '" + got + "'")

-> same_pcm(name, d, chans, frames)
  ch = chans.size
  check(name + " frames", d[:frames], frames)
  check(name + " channels", d[:ch], ch)
  i = 0
  while i < frames
    c = 0
    while c < ch
      if d[:pcm][i * ch + c] != chans[c][i]
        fail_check(name, "frame " + i.to_s + " channel " + c.to_s + ": got " + d[:pcm][i * ch + c].to_s + " want " + chans[c][i].to_s)
      c += 1
    i += 1

# ---- 1. mono 16-bit: delta widths 1, 3, 9, 16, 17, a raw block, a partial last block -----------------------------------
frames = 512 * 5 + 100
# block 0: a slow ramp (deltas 0 and -1 only: width 1)
mono = []
i = 0
while i < 512
  mono.push(0 - i / 2)
  i += 1
mono = mono + wave(512, ~2.5, ~512.0, ~0.0)
mono = mono + wave(512, ~20000.0, ~4000.0, ~0.3)
mono = mono + wave(512, ~32000.0, ~40.0, ~0.0)
mono = mono + wave(512, ~32767.0, ~4.0, ~0.7)
mono = mono + wave(512, ~30000.0, ~7.0, ~0.1)
b1 = make_ncw([mono], 16, frames, [[0, 1], [0, 3], [0, 9], [0, 16], [0, 17], [0, -16]], 0x131)
h1 = ncw_header(b1)
check("mono header", [h1[0], h1[1], h1[2], h1[3], h1[7]], [1, 16, 44100, frames, 0x131])
d1 = ncw_decode(b1)
same_pcm("mono 16-bit blocks", d1, [mono], frames)
check("mono raw block count", d1[:raw_blocks], 1)
check("mono pads", d1[:pads], 0)

# ---- 2. stereo 24-bit: plain, mid/side, mid/side with a raw channel, wide deltas; header version 0x130 --------------------
fr2 = 512 * 4
lt = wave(fr2, ~3000000.0, ~300.0, ~0.0)
rt = wave(fr2, ~2500000.0, ~250.0, ~1.0)
# mid/side blocks need L and R of one parity (M = (L+R)/2, S = (L-R)/2 exactly)
i = 512
while i < 512 * 3
  rt[i] = rt[i] - ((rt[i] - lt[i]) % 2)
  i += 1
# block 3: full-scale square steps (deltas need 25 bits)
i = 512 * 3
while i < fr2
  v = 8388607
  v = -8388608 if (i / 3) % 2 == 1
  lt[i] = v
  rt[i] = 0 - v - 1
  i += 1
b2 = make_ncw([lt, rt], 24, fr2, [[0, 20, 20], [1, 20, 18], [1, -24, 19], [0, 25, 25]], 0x130)
d2 = ncw_decode(b2)
same_pcm("stereo 24-bit blocks", d2, [lt, rt], fr2)
check("stereo version", d2[:version], 0x130)
check("stereo bits", d2[:bits], 24)
check("stereo mid/side block count", d2[:ms_blocks], 2)
check("stereo raw block count", d2[:raw_blocks], 1)

# ---- 3. the WAV writer: header fields, payload, the RIFF pad byte, determinism -------------------------------------------
tmp = Tempfile.new("tungsten-ncw-spec")
base = tmp.path
tmp.close!()
pa = base + "-a.wav"
pb = base + "-b.wav"
write_wav_pcm(pa, d2[:pcm], d2[:frames], 2, 44100, 24)
write_wav_pcm(pb, d2[:pcm], d2[:frames], 2, 44100, 24)
wa = File.read_bytes(pa)
wb = File.read_bytes(pb)
check("wav size", wa.size, 44 + fr2 * 6)
same = wa.size == wb.size
i = 0
while same && i < wa.size
  same = wa[i] == wb[i]
  i += 1
check("wav deterministic", same, true)
check("wav RIFF", [wa[0], wa[1], wa[2], wa[3], wa[8], wa[12], wa[36]], [82, 73, 70, 70, 87, 102, 100])
check("wav riff size", ncw_u32(wa, 4), 36 + fr2 * 6)
check("wav format", [ncw_u16(wa, 20), ncw_u16(wa, 22), ncw_u32(wa, 24), ncw_u32(wa, 28), ncw_u16(wa, 32), ncw_u16(wa, 34)], [1, 2, 44100, 44100 * 6, 6, 24])
check("wav data size", ncw_u32(wa, 40), fr2 * 6)
v0 = wa[44] + wa[45] * 256 + wa[46] * 65536
v0 = v0 - 16777216 if v0 >= 8388608
check("wav first sample", v0, lt[0])
v1 = wa[47] + wa[48] * 256 + wa[49] * 65536
v1 = v1 - 16777216 if v1 >= 8388608
check("wav second channel", v1, rt[0])
# 24-bit mono, odd frame count: odd data, one pad byte, RIFF size counts it
pm = base + "-m.wav"
odd = i32[3]
odd[0] = -1
odd[1] = 8388607
odd[2] = -8388608
write_wav_pcm(pm, odd, 3, 1, 48000, 24)
wm = File.read_bytes(pm)
check("odd wav size", wm.size, 44 + 9 + 1)
check("odd wav riff size", ncw_u32(wm, 4), 36 + 9 + 1)
check("odd wav data size", ncw_u32(wm, 40), 9)
check("odd wav bytes", [wm[44], wm[45], wm[46], wm[47], wm[48], wm[49], wm[50], wm[51], wm[52], wm[53]], [255, 255, 255, 255, 255, 127, 0, 0, 128, 0])
# 16-bit
p16 = base + "-16.wav"
write_wav_pcm(p16, d1[:pcm], d1[:frames], 1, 44100, 16)
w16 = File.read_bytes(p16)
check("16-bit wav size", w16.size, 44 + frames * 2)
s7 = w16[44 + 14] + w16[45 + 14] * 256
s7 = s7 - 65536 if s7 >= 32768
check("16-bit wav sample 7", s7, mono[7])
File.delete(pa)
File.delete(pb)
File.delete(pm)
File.delete(p16)

# ---- 4. malformed files ---------------------------------------------------------------------------------------------------
short = u8[60]
expect_raise("too short", short, "too short")
bad = u8[b1.size]
i = 0
while i < b1.size
  bad[i] = b1[i]
  i += 1
bad[0] = 0
expect_raise("bad magic", bad, "not an NCW file")
cut = u8[b1.size - 40]
i = 0
while i < cut.size
  cut[i] = b1[i]
  i += 1
expect_raise("truncated", cut, "runs past the end")
# a block's data cut short while the header claims less: shrink the data size to the bytes kept
cut2 = make_ncw([mono], 16, frames, [[0, 1], [0, 3], [0, 9], [0, 16], [0, 17], [0, -16]], 0x131)
dsz = ncw_u32(cut2, 28)
ncw_le(cut2, 28, dsz - 40, 4)
expect_raise("truncated block", cut2, "truncated block")
# block magic
bm = make_ncw([mono], 16, frames, [[0, 1], [0, 3], [0, 9], [0, 16], [0, 17], [0, -16]], 0x131)
at = ncw_u32(bm, 24) + ncw_u32(bm, 120 + 4 * 2)
bm[at] = 0
expect_raise("block magic", bm, "bad block magic (block 2, channel 0)")
# width 0
w0 = make_ncw([mono], 16, frames, [[0, 1], [0, 3], [0, 9], [0, 16], [0, 17], [0, -16]], 0x131)
at = ncw_u32(w0, 24) + ncw_u32(w0, 120 + 4 * 1)
w0[at + 8] = 0
w0[at + 9] = 0
expect_raise("width 0", w0, "bad block bit width")
# flags 2 (unknown), and channels that disagree
f2 = make_ncw([lt, rt], 24, fr2, [[0, 20, 20], [1, 20, 18], [1, -24, 19], [0, 25, 25]], 0x131)
at = ncw_u32(f2, 24) + ncw_u32(f2, 120)
f2[at + 10] = 2
expect_raise("unknown flags", f2, "unknown block flags")
# a 16-bit file whose deltas run out of range
big = []
i = 0
while i < 512
  big.push(i * 100)
  i += 1
ob = make_ncw([big], 16, 512, [[0, 9]], 0x131)
expect_raise("out of range", ob, "sample outside the bit depth")
# unsupported sample size
s8 = make_ncw([mono], 16, frames, [[0, 1], [0, 3], [0, 9], [0, 16], [0, 17], [0, -16]], 0x131)
s8[10] = 8
expect_raise("sample size", s8, "unsupported sample size 8 bits")

<< "ncw spec: all checks passed"
