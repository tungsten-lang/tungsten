# studio/flac — FLAC (the Free Lossless Audio Codec) decoded to integer PCM, our own reader, and `studio flaccheck`, which
# decodes files, checks them against their STREAMINFO MD5 and, given the WAV tree they came from, against the WAVs sample for
# sample (2026-11-04, for the WAV instrument libraries kept as `flac -8 --keep-foreign-metadata` in ~/studio/instruments-flac).
#
# The format (RFC 9639), as read here; integers are big-endian, frames are bit-packed most significant bit first:
#
#   "fLaC" (an ID3v2 tag in front is skipped), then metadata blocks: 1 bit last-block flag, 7 bits type, 24 bits length, body.
#     STREAMINFO (type 0, first, 34 bytes): 16 min block size, 16 max block size, 24 min frame size, 24 max frame size, 20 sample
#     rate, 3 channels − 1, 5 bits per sample − 1, 36 total samples per channel, 128 MD5 of the PCM (the samples interleaved,
#     little-endian, signed, ceil(bits/8) bytes each). Every other block is skipped (PADDING, SEEKTABLE, VORBIS_COMMENT, CUESHEET,
#     PICTURE, APPLICATION: `flac --keep-foreign-metadata` keeps a WAV's other chunks in APPLICATION "riff" blocks); 127 is invalid.
#   frames:
#     header: 14-bit sync 0x3FFE, 1 reserved (0), 1 blocking strategy (0 fixed, 1 variable), 4 block size code (1: 192; 2..5:
#       576·2^(n−2); 6, 7: an 8- or 16-bit block size − 1 at the end of the header; 8..15: 256·2^(n−8); 0 reserved), 4 sample rate
#       code (0 STREAMINFO's, 1..11 the fixed rates, 12 an 8-bit kHz, 13 a 16-bit Hz, 14 a 16-bit tens of Hz value at the end of
#       the header; 15 invalid), 4 channel assignment (0..7: 1..8 independent channels; 8 left/side, 9 side/right, 10 mid/side;
#       11..15 reserved), 3 sample size code (0 STREAMINFO's; 1 8, 2 12, 4 16, 5 20, 6 24, 7 32 bits; 3 reserved), 1 reserved (0),
#       the frame number (fixed) or first sample number (variable) coded like UTF-8 in 1..7 bytes, the block size and rate
#       extensions, CRC-8 (x^8 + x^2 + x + 1, from the sync code).
#     one subframe per channel: 1 zero bit, 6 type bits (0 CONSTANT, 1 VERBATIM, 8..12 FIXED order 0..4, 32..63 LPC order 1..32;
#       the rest reserved), 1 wasted-bits flag (then k − 1 zero bits and a one: every sample was shifted left by k). A side
#       channel (left/side: the second; side/right: the first; mid/side: the second) carries one bit more than the frame.
#       CONSTANT: one sample. VERBATIM: every sample. FIXED: `order` warm-up samples, then the residual. LPC: `order` warm-up
#       samples, 4-bit coefficient precision − 1 (15 invalid), 5-bit signed shift (negative invalid), `order` signed coefficients,
#       the residual. Prediction: s[i] = r[i] + (sum over j < order of c[j]·s[i − 1 − j]) >> shift; FIXED uses c = (1), (2, −1),
#       (3, −3, 1), (4, −6, 4, −1) and shift 0.
#       residual: 2-bit method (0: 4-bit Rice parameters, escape 15; 1: 5-bit parameters, escape 31; 2, 3 reserved), 4-bit partition
#       order p; 2^p partitions of (block size >> p) samples (the block size a multiple of 2^p; the first partition is shorter by
#       the predictor order), each a Rice parameter k then its values (a unary quotient q, k low bits; v = q·2^k + low, the sample
#       (v >> 1) xor −(v and 1)) or, after the escape, a 5-bit width and the samples raw in that many bits.
#     zero bits to the next byte, then CRC-16 (x^16 + x^15 + x^2 + 1) of the whole frame.
#   Stereo decorrelation: left/side R = L − S; side/right L = S + R; mid/side M = 2M + (S and 1), L = (M + S) >> 1, R = (M − S) >> 1.
#
# All samples are kept in 64-bit integers until they are written out (a 32-bit stream's side channel has 33 bits), so the
# prediction sums are exact. Bit depths 4..32, 1..8 channels, block sizes up to 65,535, fixed and variable blocking. Streams
# without a total sample count in STREAMINFO are rejected (nothing here writes them). The bit reading, the Rice and raw sample
# loops, the predictor, the CRCs and the output conversion are embedded-IR loops (plain 64-bit arithmetic; compiled only, as
# ncw.w's unpacking): everything else, headers and subframe parsing, is ordinary Tungsten.
#
# Checks behind it (2026-11-04): all 206,368 WAV instrument-library files converted with `flac 1.5.0 -8 --keep-foreign-metadata`
# (16/24-bit, mono/stereo, 44.1/48/64/96 kHz; 47.7 billion frames, 84.6 billion samples, 281 hours) decode here to exactly the
# WAVs' samples, byte for byte, and to their STREAMINFO MD5 (`studio flaccheck --wav`, six processes, 9.4 minutes);
# spec/apps/studio_flac_spec.w encodes every subframe type, predictor order, channel assignment, Rice method, escape and header
# variant with a small encoder of its own and checks the decoded samples, the MD5 and every malformed-stream error.

FLAC_MAGIC = 0x664C6143

# ---------------------------------------------------------------------------------------------- kernels (embedded IR)

# n (0..57) bits at bit position pos (0 = the most significant bit of b[0]), as an unsigned number; bytes at or past nb read as 0.
fn flac_bits(b, nb, pos, n) (u8[] i64 i64 i64) i64
  ll <<~IR
  entry:
    %pb = inttoptr i64 %b to ptr
    %acc = alloca i64
    %j = alloca i64
    %q = lshr i64 %pos, 3
    %sh = and i64 %pos, 7
    %nz = icmp eq i64 %n, 0
    br i1 %nz, label %zero, label %start
  start:
    %q8 = add i64 %q, 8
    %fast = icmp sle i64 %q8, %nb
    br i1 %fast, label %quick, label %slow
  quick:
    %p = getelementptr i8, ptr %pb, i64 %q
    %w0 = load i64, ptr %p, align 1
    %w = call i64 @llvm.bswap.i64(i64 %w0)
    br label %fin
  slow:
    store i64 0, ptr %acc
    store i64 0, ptr %j
    br label %sl
  sl:
    %jv = load i64, ptr %j
    %more = icmp slt i64 %jv, 8
    br i1 %more, label %sb, label %sdone
  sb:
    %idx = add i64 %q, %jv
    %in = icmp slt i64 %idx, %nb
    %a0 = load i64, ptr %acc
    %a1 = shl i64 %a0, 8
    store i64 %a1, ptr %acc
    br i1 %in, label %sld, label %snext
  sld:
    %bp = getelementptr i8, ptr %pb, i64 %idx
    %by = load i8, ptr %bp, align 1
    %bz = zext i8 %by to i64
    %a2 = or i64 %a1, %bz
    store i64 %a2, ptr %acc
    br label %snext
  snext:
    %j1 = add i64 %jv, 1
    store i64 %j1, ptr %j
    br label %sl
  sdone:
    %ws = load i64, ptr %acc
    br label %fin
  fin:
    %wv = phi i64 [%w, %quick], [%ws, %sdone]
    %x = shl i64 %wv, %sh
    %rs = sub i64 64, %n
    %v = lshr i64 %x, %rs
    ret i64 %v
  zero:
    ret i64 0
  IR

# cnt signed n-bit samples (n 0..57) from bit position pos into out[o0 ..]; returns the bit position after them, −1 when they
# run past byte nb.
fn flac_raw(b, nb, pos, n, out, o0, cnt) (u8[] i64 i64 i64 i64[] i64 i64) i64
  ll <<~IR
  entry:
    %pb = inttoptr i64 %b to ptr
    %po = inttoptr i64 %out to ptr
    %i = alloca i64
    %acc = alloca i64
    %j = alloca i64
    %tot = mul i64 %n, %cnt
    %end = add i64 %pos, %tot
    %lim = shl i64 %nb, 3
    %over = icmp sgt i64 %end, %lim
    br i1 %over, label %fail, label %init
  init:
    store i64 0, ptr %i
    %nz = icmp eq i64 %n, 0
    %rs = sub i64 64, %n
    br label %top
  top:
    %iv = load i64, ptr %i
    %more = icmp slt i64 %iv, %cnt
    br i1 %more, label %one, label %exit
  one:
    %off = mul i64 %iv, %n
    %p = add i64 %pos, %off
    %q = lshr i64 %p, 3
    %sh = and i64 %p, 7
    %q8 = add i64 %q, 8
    %fast = icmp sle i64 %q8, %nb
    br i1 %fast, label %quick, label %slow
  quick:
    %pp = getelementptr i8, ptr %pb, i64 %q
    %w0 = load i64, ptr %pp, align 1
    %w = call i64 @llvm.bswap.i64(i64 %w0)
    br label %fin
  slow:
    store i64 0, ptr %acc
    store i64 0, ptr %j
    br label %sl
  sl:
    %jv = load i64, ptr %j
    %jm = icmp slt i64 %jv, 8
    br i1 %jm, label %sb, label %sdone
  sb:
    %idx = add i64 %q, %jv
    %in = icmp slt i64 %idx, %nb
    %a0 = load i64, ptr %acc
    %a1 = shl i64 %a0, 8
    store i64 %a1, ptr %acc
    br i1 %in, label %sld, label %snext
  sld:
    %bp = getelementptr i8, ptr %pb, i64 %idx
    %by = load i8, ptr %bp, align 1
    %bz = zext i8 %by to i64
    %a2 = or i64 %a1, %bz
    store i64 %a2, ptr %acc
    br label %snext
  snext:
    %j1 = add i64 %jv, 1
    store i64 %j1, ptr %j
    br label %sl
  sdone:
    %ws = load i64, ptr %acc
    br label %fin
  fin:
    %wv = phi i64 [%w, %quick], [%ws, %sdone]
    %x = shl i64 %wv, %sh
    %v0 = ashr i64 %x, %rs
    %v = select i1 %nz, i64 0, i64 %v0
    %oi = add i64 %o0, %iv
    %op = getelementptr i64, ptr %po, i64 %oi
    store i64 %v, ptr %op
    %i1 = add i64 %iv, 1
    store i64 %i1, ptr %i
    br label %top
  exit:
    ret i64 %end
  fail:
    ret i64 -1
  IR

# cnt Rice-coded values with parameter k (0..30) from bit position pos into out[o0 ..] (unary quotient, k low bits, zigzag sign);
# returns the bit position after them, −1 when the data ends first. A 64-bit cache holds the next nc bits of the stream at its
# top (bits [8q − nc, 8q)); it is topped up 8 bytes at a time, byte by byte in the last 8 bytes of the buffer.
fn flac_rice(b, nb, pos, k, out, o0, cnt) (u8[] i64 i64 i64 i64[] i64 i64) i64
  ll <<~IR
  entry:
    %pb = inttoptr i64 %b to ptr
    %po = inttoptr i64 %out to ptr
    %c = alloca i64
    %nc = alloca i64
    %q = alloca i64
    %i = alloca i64
    %z = alloca i64
    %rt = alloca i64
    %q0 = lshr i64 %pos, 3
    store i64 0, ptr %c
    store i64 0, ptr %nc
    store i64 %q0, ptr %q
    store i64 0, ptr %i
    store i64 0, ptr %z
    store i64 0, ptr %rt
    %kz = icmp eq i64 %k, 0
    %ksh = sub i64 64, %k
    br label %refill
  start:
    %r0 = and i64 %pos, 7
    %c1 = load i64, ptr %c
    %n1 = load i64, ptr %nc
    %okst = icmp sge i64 %n1, %r0
    br i1 %okst, label %start2, label %fail
  start2:
    %c2 = shl i64 %c1, %r0
    %n2 = sub i64 %n1, %r0
    store i64 %c2, ptr %c
    store i64 %n2, ptr %nc
    br label %top
  top:
    %iv = load i64, ptr %i
    %more = icmp slt i64 %iv, %cnt
    br i1 %more, label %val, label %exit
  val:
    store i64 0, ptr %z
    %nv = load i64, ptr %nc
    %low32 = icmp slt i64 %nv, 32
    br i1 %low32, label %val_refill, label %unary
  val_refill:
    store i64 1, ptr %rt
    br label %refill
  unary:
    %uc = load i64, ptr %c
    %un = load i64, ptr %nc
    %lz = call i64 @llvm.ctlz.i64(i64 %uc, i1 false)
    %hit = icmp slt i64 %lz, %un
    br i1 %hit, label %one, label %empty
  empty:
    %z0 = load i64, ptr %z
    %z1 = add i64 %z0, %un
    store i64 %z1, ptr %z
    store i64 0, ptr %c
    store i64 0, ptr %nc
    store i64 2, ptr %rt
    br label %refill
  after_empty:
    %ne = load i64, ptr %nc
    %eof = icmp eq i64 %ne, 0
    br i1 %eof, label %fail, label %unary
  one:
    %z2 = load i64, ptr %z
    %zt = add i64 %z2, %lz
    %s1 = shl i64 %uc, %lz
    %s2 = shl i64 %s1, 1
    %lz1 = add i64 %lz, 1
    %n3 = sub i64 %un, %lz1
    store i64 %s2, ptr %c
    store i64 %n3, ptr %nc
    store i64 %zt, ptr %z
    %need = icmp slt i64 %n3, %k
    br i1 %need, label %k_refill, label %kbits
  k_refill:
    store i64 3, ptr %rt
    br label %refill
  after_k:
    %n4 = load i64, ptr %nc
    %short = icmp slt i64 %n4, %k
    br i1 %short, label %fail, label %kbits
  kbits:
    %kc = load i64, ptr %c
    %kn = load i64, ptr %nc
    %lowr = lshr i64 %kc, %ksh
    %low = select i1 %kz, i64 0, i64 %lowr
    %kc2 = shl i64 %kc, %k
    %kn2 = sub i64 %kn, %k
    store i64 %kc2, ptr %c
    store i64 %kn2, ptr %nc
    %zz = load i64, ptr %z
    %hi = shl i64 %zz, %k
    %v = or i64 %hi, %low
    %vs = lshr i64 %v, 1
    %vb = and i64 %v, 1
    %vn = sub i64 0, %vb
    %sv = xor i64 %vs, %vn
    %ik = load i64, ptr %i
    %oi = add i64 %o0, %ik
    %op = getelementptr i64, ptr %po, i64 %oi
    store i64 %sv, ptr %op
    %i2 = add i64 %ik, 1
    store i64 %i2, ptr %i
    br label %top
  refill:
    %rn = load i64, ptr %nc
    %full = icmp sgt i64 %rn, 56
    br i1 %full, label %rdone, label %rgo
  rgo:
    %rq = load i64, ptr %q
    %rq8 = add i64 %rq, 8
    %rfast = icmp sle i64 %rq8, %nb
    br i1 %rfast, label %rquick, label %rslow
  rquick:
    %rp = getelementptr i8, ptr %pb, i64 %rq
    %rw0 = load i64, ptr %rp, align 1
    %rw = call i64 @llvm.bswap.i64(i64 %rw0)
    %rsh = lshr i64 %rw, %rn
    %rc0 = load i64, ptr %c
    %rc1 = or i64 %rc0, %rsh
    store i64 %rc1, ptr %c
    %rfree = sub i64 64, %rn
    %rnb = lshr i64 %rfree, 3
    %rq2 = add i64 %rq, %rnb
    store i64 %rq2, ptr %q
    %rnb8 = shl i64 %rnb, 3
    %rn2 = add i64 %rn, %rnb8
    store i64 %rn2, ptr %nc
    br label %rdone
  rslow:
    %sq = load i64, ptr %q
    %sn = load i64, ptr %nc
    %sroom = icmp sle i64 %sn, 56
    %sin = icmp slt i64 %sq, %nb
    %sgo = and i1 %sroom, %sin
    br i1 %sgo, label %sbyte, label %rdone
  sbyte:
    %sp = getelementptr i8, ptr %pb, i64 %sq
    %sby = load i8, ptr %sp, align 1
    %sbz = zext i8 %sby to i64
    %ssh = sub i64 56, %sn
    %sbs = shl i64 %sbz, %ssh
    %sc0 = load i64, ptr %c
    %sc1 = or i64 %sc0, %sbs
    store i64 %sc1, ptr %c
    %sn2 = add i64 %sn, 8
    store i64 %sn2, ptr %nc
    %sq2 = add i64 %sq, 1
    store i64 %sq2, ptr %q
    br label %rslow
  rdone:
    %rtv = load i64, ptr %rt
    switch i64 %rtv, label %start [ i64 1, label %unary
                                    i64 2, label %after_empty
                                    i64 3, label %after_k ]
  exit:
    %eq = load i64, ptr %q
    %en = load i64, ptr %nc
    %eb = shl i64 %eq, 3
    %ep = sub i64 %eb, %en
    ret i64 %ep
  fail:
    ret i64 -1
  IR

# The predictor, in place: s[o0 .. o0 + order) are the warm-up samples, s[o0 + order .. o0 + n) the residual; each becomes
# r[i] + (sum over j < order of c[j]·s[i − 1 − j]) >> shift (arithmetic shift). Returns n.
fn flac_lpc(s, o0, n, order, c, shift) (i64[] i64 i64 i64 i64[] i64) i64
  ll <<~IR
  entry:
    %ps = inttoptr i64 %s to ptr
    %pc = inttoptr i64 %c to ptr
    %i = alloca i64
    %j = alloca i64
    %acc = alloca i64
    store i64 %order, ptr %i
    br label %outer
  outer:
    %iv = load i64, ptr %i
    %more = icmp slt i64 %iv, %n
    br i1 %more, label %ostart, label %done
  ostart:
    store i64 0, ptr %j
    store i64 0, ptr %acc
    %base = add i64 %o0, %iv
    br label %inner
  inner:
    %jv = load i64, ptr %j
    %jm = icmp slt i64 %jv, %order
    br i1 %jm, label %ibody, label %iend
  ibody:
    %cp = getelementptr i64, ptr %pc, i64 %jv
    %cv = load i64, ptr %cp
    %b1 = sub i64 %base, 1
    %si = sub i64 %b1, %jv
    %sp = getelementptr i64, ptr %ps, i64 %si
    %sv = load i64, ptr %sp
    %pr = mul i64 %cv, %sv
    %a0 = load i64, ptr %acc
    %a1 = add i64 %a0, %pr
    store i64 %a1, ptr %acc
    %j1 = add i64 %jv, 1
    store i64 %j1, ptr %j
    br label %inner
  iend:
    %sum = load i64, ptr %acc
    %pred = ashr i64 %sum, %shift
    %rp = getelementptr i64, ptr %ps, i64 %base
    %rv = load i64, ptr %rp
    %nv = add i64 %rv, %pred
    store i64 %nv, ptr %rp
    %i1 = add i64 %iv, 1
    store i64 %i1, ptr %i
    br label %outer
  done:
    ret i64 %n
  IR

# s[o0 .. o0 + n) <<= w (wasted bits); returns n.
fn flac_shl(s, o0, n, w) (i64[] i64 i64 i64) i64
  ll <<~IR
  entry:
    %ps = inttoptr i64 %s to ptr
    %i = alloca i64
    store i64 0, ptr %i
    br label %loop
  loop:
    %iv = load i64, ptr %i
    %more = icmp slt i64 %iv, %n
    br i1 %more, label %body, label %done
  body:
    %k = add i64 %o0, %iv
    %p = getelementptr i64, ptr %ps, i64 %k
    %v = load i64, ptr %p
    %v2 = shl i64 %v, %w
    store i64 %v2, ptr %p
    %i1 = add i64 %iv, 1
    store i64 %i1, ptr %i
    br label %loop
  done:
    ret i64 %n
  IR

# s[o0 .. o0 + n) = v; returns n.
fn flac_fill(s, o0, n, v) (i64[] i64 i64 i64) i64
  ll <<~IR
  entry:
    %ps = inttoptr i64 %s to ptr
    %i = alloca i64
    store i64 0, ptr %i
    br label %loop
  loop:
    %iv = load i64, ptr %i
    %more = icmp slt i64 %iv, %n
    br i1 %more, label %body, label %done
  body:
    %k = add i64 %o0, %iv
    %p = getelementptr i64, ptr %ps, i64 %k
    store i64 %v, ptr %p
    %i1 = add i64 %iv, 1
    store i64 %i1, ptr %i
    br label %loop
  done:
    ret i64 %n
  IR

# Stereo decorrelation in place on s[0 .. n) (channel 0) and s[st .. st + n) (channel 1): mode 8 left/side, 9 side/right,
# 10 mid/side (anything else: nothing). Returns n.
fn flac_decorr(s, st, n, mode) (i64[] i64 i64 i64) i64
  ll <<~IR
  entry:
    %empty = icmp sle i64 %n, 0
    br i1 %empty, label %done, label %init
  init:
    %ps0 = inttoptr i64 %s to ptr
    %ps1 = getelementptr i64, ptr %ps0, i64 %st
    %n4 = and i64 %n, -4
    switch i64 %mode, label %done [ i64 8, label %ls_pre
                                    i64 9, label %sr_pre
                                    i64 10, label %ms_pre ]
  ls_pre:
    %ls_has4 = icmp sgt i64 %n4, 0
    br i1 %ls_has4, label %ls_vloop, label %ls_tail_chk
  ls_vloop:
    %iv8 = phi i64 [ 0, %ls_pre ], [ %iv8_next, %ls_vloop ]
    %p0_8 = getelementptr i64, ptr %ps0, i64 %iv8
    %p1_8 = getelementptr i64, ptr %ps1, i64 %iv8
    %va8 = load <4 x i64>, ptr %p0_8, align 8
    %vb8 = load <4 x i64>, ptr %p1_8, align 8
    %vr8 = sub <4 x i64> %va8, %vb8
    store <4 x i64> %vr8, ptr %p1_8, align 8
    %iv8_next = add i64 %iv8, 4
    %ls_vmore = icmp slt i64 %iv8_next, %n4
    br i1 %ls_vmore, label %ls_vloop, label %ls_tail_chk
  ls_tail_chk:
    %ls_tmore0 = icmp slt i64 %n4, %n
    br i1 %ls_tmore0, label %ls_tloop, label %done
  ls_tloop:
    %it8 = phi i64 [ %n4, %ls_tail_chk ], [ %it8_next, %ls_tloop ]
    %tp0_8 = getelementptr i64, ptr %ps0, i64 %it8
    %tp1_8 = getelementptr i64, ptr %ps1, i64 %it8
    %ta8 = load i64, ptr %tp0_8, align 8
    %tb8 = load i64, ptr %tp1_8, align 8
    %tr8 = sub i64 %ta8, %tb8
    store i64 %tr8, ptr %tp1_8, align 8
    %it8_next = add i64 %it8, 1
    %ls_tmore = icmp slt i64 %it8_next, %n
    br i1 %ls_tmore, label %ls_tloop, label %done

  sr_pre:
    %sr_has4 = icmp sgt i64 %n4, 0
    br i1 %sr_has4, label %sr_vloop, label %sr_tail_chk
  sr_vloop:
    %iv9 = phi i64 [ 0, %sr_pre ], [ %iv9_next, %sr_vloop ]
    %p0_9 = getelementptr i64, ptr %ps0, i64 %iv9
    %p1_9 = getelementptr i64, ptr %ps1, i64 %iv9
    %va9 = load <4 x i64>, ptr %p0_9, align 8
    %vb9 = load <4 x i64>, ptr %p1_9, align 8
    %vl9 = add <4 x i64> %va9, %vb9
    store <4 x i64> %vl9, ptr %p0_9, align 8
    %iv9_next = add i64 %iv9, 4
    %sr_vmore = icmp slt i64 %iv9_next, %n4
    br i1 %sr_vmore, label %sr_vloop, label %sr_tail_chk
  sr_tail_chk:
    %sr_tmore0 = icmp slt i64 %n4, %n
    br i1 %sr_tmore0, label %sr_tloop, label %done
  sr_tloop:
    %it9 = phi i64 [ %n4, %sr_tail_chk ], [ %it9_next, %sr_tloop ]
    %tp0_9 = getelementptr i64, ptr %ps0, i64 %it9
    %tp1_9 = getelementptr i64, ptr %ps1, i64 %it9
    %ta9 = load i64, ptr %tp0_9, align 8
    %tb9 = load i64, ptr %tp1_9, align 8
    %tl9 = add i64 %ta9, %tb9
    store i64 %tl9, ptr %tp0_9, align 8
    %it9_next = add i64 %it9, 1
    %sr_tmore = icmp slt i64 %it9_next, %n
    br i1 %sr_tmore, label %sr_tloop, label %done

  ms_pre:
    %ms_has4 = icmp sgt i64 %n4, 0
    br i1 %ms_has4, label %ms_vloop, label %ms_tail_chk
  ms_vloop:
    %iv10 = phi i64 [ 0, %ms_pre ], [ %iv10_next, %ms_vloop ]
    %p0_10 = getelementptr i64, ptr %ps0, i64 %iv10
    %p1_10 = getelementptr i64, ptr %ps1, i64 %iv10
    %va10 = load <4 x i64>, ptr %p0_10, align 8
    %vb10 = load <4 x i64>, ptr %p1_10, align 8
    %vm2 = shl <4 x i64> %va10, <i64 1, i64 1, i64 1, i64 1>
    %vsb = and <4 x i64> %vb10, <i64 1, i64 1, i64 1, i64 1>
    %vm = or <4 x i64> %vm2, %vsb
    %vlsum = add <4 x i64> %vm, %vb10
    %vl10 = ashr <4 x i64> %vlsum, <i64 1, i64 1, i64 1, i64 1>
    %vrdif = sub <4 x i64> %vm, %vb10
    %vr10 = ashr <4 x i64> %vrdif, <i64 1, i64 1, i64 1, i64 1>
    store <4 x i64> %vl10, ptr %p0_10, align 8
    store <4 x i64> %vr10, ptr %p1_10, align 8
    %iv10_next = add i64 %iv10, 4
    %ms_vmore = icmp slt i64 %iv10_next, %n4
    br i1 %ms_vmore, label %ms_vloop, label %ms_tail_chk
  ms_tail_chk:
    %ms_tmore0 = icmp slt i64 %n4, %n
    br i1 %ms_tmore0, label %ms_tloop, label %done
  ms_tloop:
    %it10 = phi i64 [ %n4, %ms_tail_chk ], [ %it10_next, %ms_tloop ]
    %tp0_10 = getelementptr i64, ptr %ps0, i64 %it10
    %tp1_10 = getelementptr i64, ptr %ps1, i64 %it10
    %a = load i64, ptr %tp0_10, align 8
    %b = load i64, ptr %tp1_10, align 8
    %m2 = shl i64 %a, 1
    %sb = and i64 %b, 1
    %m = or i64 %m2, %sb
    %lsum = add i64 %m, %b
    %l10 = ashr i64 %lsum, 1
    %rdif = sub i64 %m, %b
    %r10 = ashr i64 %rdif, 1
    store i64 %l10, ptr %tp0_10, align 8
    store i64 %r10, ptr %tp1_10, align 8
    %it10_next = add i64 %it10, 1
    %ms_tmore = icmp slt i64 %it10_next, %n
    br i1 %ms_tmore, label %ms_tloop, label %done
  done:
    ret i64 %n
  IR

# Channel c of a block, s[s0 .. s0 + n), into interleaved out[(f0 + i)·ch + c] (32-bit). Returns n.
fn flac_put_i32(out, f0, ch, c, s, s0, n) (i32[] i64 i64 i64 i64[] i64 i64) i64
  ll <<~IR
  entry:
    %po = inttoptr i64 %out to ptr
    %ps = inttoptr i64 %s to ptr
    %i = alloca i64
    store i64 0, ptr %i
    br label %loop
  loop:
    %iv = load i64, ptr %i
    %more = icmp slt i64 %iv, %n
    br i1 %more, label %body, label %done
  body:
    %k = add i64 %s0, %iv
    %sp = getelementptr i64, ptr %ps, i64 %k
    %v = load i64, ptr %sp
    %v32 = trunc i64 %v to i32
    %f = add i64 %f0, %iv
    %fc = mul i64 %f, %ch
    %o = add i64 %fc, %c
    %op = getelementptr i32, ptr %po, i64 %o
    store i32 %v32, ptr %op
    %i1 = add i64 %iv, 1
    store i64 %i1, ptr %i
    br label %loop
  done:
    ret i64 %n
  IR

# s[s0 .. s0 + n) as floats into dst[f0 ..], each divided by 2^(bits − 1) (exactly what a WAV reader does with the same integer
# sample: 16 bits / 32768, 24 bits / 8388608). Returns n.
fn flac_put_f64(dst, f0, s, s0, n, bits) (f64[] i64 i64[] i64 i64 i64) i64
  ll <<~IR
  entry:
    %empty = icmp sle i64 %n, 0
    br i1 %empty, label %done, label %init
  init:
    %pd0 = inttoptr i64 %dst to ptr
    %pd = getelementptr double, ptr %pd0, i64 %f0
    %ps0 = inttoptr i64 %s to ptr
    %ps = getelementptr i64, ptr %ps0, i64 %s0
    %b1 = sub i64 %bits, 1
    %one = shl i64 1, %b1
    %sc = sitofp i64 %one to double
    %inv = fdiv double 1.0, %sc
    %vinv0 = insertelement <2 x double> poison, double %inv, i32 0
    %vinv = shufflevector <2 x double> %vinv0, <2 x double> poison, <2 x i32> zeroinitializer
    %n2 = and i64 %n, -2
    %has2 = icmp sgt i64 %n2, 0
    br i1 %has2, label %vloop, label %tail_chk
  vloop:
    %iv = phi i64 [ 0, %init ], [ %iv_next, %vloop ]
    %sp = getelementptr i64, ptr %ps, i64 %iv
    %vi = load <2 x i64>, ptr %sp, align 8
    %vf = sitofp <2 x i64> %vi to <2 x double>
    %vx = fmul <2 x double> %vf, %vinv
    %dp = getelementptr double, ptr %pd, i64 %iv
    store <2 x double> %vx, ptr %dp, align 8
    %iv_next = add i64 %iv, 2
    %vmore = icmp slt i64 %iv_next, %n2
    br i1 %vmore, label %vloop, label %tail_chk
  tail_chk:
    %tmore0 = icmp slt i64 %n2, %n
    br i1 %tmore0, label %tloop, label %done
  tloop:
    %it = phi i64 [ %n2, %tail_chk ], [ %it_next, %tloop ]
    %tsp = getelementptr i64, ptr %ps, i64 %it
    %tv = load i64, ptr %tsp, align 8
    %tfv = sitofp i64 %tv to double
    %tx = fmul double %tfv, %inv
    %tdp = getelementptr double, ptr %pd, i64 %it
    store double %tx, ptr %tdp, align 8
    %it_next = add i64 %it, 1
    %tmore = icmp slt i64 %it_next, %n
    br i1 %tmore, label %tloop, label %done
  done:
    ret i64 %n
  IR

# n interleaved samples pcm[p0 .. p0 + n) as little-endian bps-byte integers (1..4) into buf[0 ..]; returns the bytes written.
fn flac_pack_at(pcm, p0, n, bps, buf) (i32[] i64 i64 i64 u8[]) i64
  ll <<~IR
  entry:
    %pp = inttoptr i64 %pcm to ptr
    %pb = inttoptr i64 %buf to ptr
    %i = alloca i64
    %j = alloca i64
    store i64 0, ptr %i
    br label %loop
  loop:
    %iv = load i64, ptr %i
    %more = icmp slt i64 %iv, %n
    br i1 %more, label %body, label %done
  body:
    %si = add i64 %p0, %iv
    %sp = getelementptr i32, ptr %pp, i64 %si
    %v = load i32, ptr %sp
    %o = mul i64 %iv, %bps
    store i64 0, ptr %j
    br label %bl
  bl:
    %jv = load i64, ptr %j
    %jm = icmp slt i64 %jv, %bps
    br i1 %jm, label %bb, label %bend
  bb:
    %j8 = mul i64 %jv, 8
    %j32 = trunc i64 %j8 to i32
    %vs = lshr i32 %v, %j32
    %by = trunc i32 %vs to i8
    %oj = add i64 %o, %jv
    %bp = getelementptr i8, ptr %pb, i64 %oj
    store i8 %by, ptr %bp
    %j1 = add i64 %jv, 1
    store i64 %j1, ptr %j
    br label %bl
  bend:
    %i1 = add i64 %iv, 1
    store i64 %i1, ptr %i
    br label %loop
  done:
    %tot = mul i64 %n, %bps
    ret i64 %tot
  IR

# The first index i < n where a[a0 + i] != b[b0 + i], or −1 when the ranges are equal.
fn flac_cmp(a, a0, b, b0, n) (u8[] i64 u8[] i64 i64) i64
  ll <<~IR
  entry:
    %pa = inttoptr i64 %a to ptr
    %pb = inttoptr i64 %b to ptr
    %i = alloca i64
    store i64 0, ptr %i
    br label %loop
  loop:
    %iv = load i64, ptr %i
    %more = icmp slt i64 %iv, %n
    br i1 %more, label %body, label %same
  body:
    %ka = add i64 %a0, %iv
    %kb = add i64 %b0, %iv
    %xa = getelementptr i8, ptr %pa, i64 %ka
    %xb = getelementptr i8, ptr %pb, i64 %kb
    %va = load i8, ptr %xa
    %vb = load i8, ptr %xb
    %ne = icmp ne i8 %va, %vb
    br i1 %ne, label %diff, label %next
  next:
    %i1 = add i64 %iv, 1
    store i64 %i1, ptr %i
    br label %loop
  diff:
    ret i64 %iv
  same:
    ret i64 -1
  IR

# MD5 (RFC 1321) of nblk 64-byte blocks at buf[at ..], into the state st[0..3] (32-bit words in 64-bit slots); kt holds the 64
# sine constants, sh the 64 rotations. Message words are read little-endian (the targets are little-endian). Returns nblk.
fn flac_md5_blocks(buf, at, nblk, st, kt, sh) (u8[] i64 i64 i64[] i64[] i64[]) i64
  ll <<~IR
  entry:
    %pb = inttoptr i64 %buf to ptr
    %ps = inttoptr i64 %st to ptr
    %pk = inttoptr i64 %kt to ptr
    %pr = inttoptr i64 %sh to ptr
    %blk = alloca i64
    %i = alloca i64
    %a = alloca i32
    %b = alloca i32
    %c = alloca i32
    %d = alloca i32
    %p1 = getelementptr i64, ptr %ps, i64 1
    %p2 = getelementptr i64, ptr %ps, i64 2
    %p3 = getelementptr i64, ptr %ps, i64 3
    store i64 0, ptr %blk
    br label %bloop
  bloop:
    %bk = load i64, ptr %blk
    %bm = icmp slt i64 %bk, %nblk
    br i1 %bm, label %bstart, label %done
  bstart:
    %s0 = load i64, ptr %ps
    %s1 = load i64, ptr %p1
    %s2 = load i64, ptr %p2
    %s3 = load i64, ptr %p3
    %a0 = trunc i64 %s0 to i32
    %b0 = trunc i64 %s1 to i32
    %c0 = trunc i64 %s2 to i32
    %d0 = trunc i64 %s3 to i32
    store i32 %a0, ptr %a
    store i32 %b0, ptr %b
    store i32 %c0, ptr %c
    store i32 %d0, ptr %d
    store i64 0, ptr %i
    br label %rloop
  rloop:
    %iv = load i64, ptr %i
    %rm = icmp slt i64 %iv, 64
    br i1 %rm, label %round, label %bend
  round:
    %av = load i32, ptr %a
    %bv = load i32, ptr %b
    %cv = load i32, ptr %c
    %dv = load i32, ptr %d
    %q = lshr i64 %iv, 4
    switch i64 %q, label %r3 [ i64 0, label %r0
                               i64 1, label %r1
                               i64 2, label %r2 ]
  r0:
    %f0a = and i32 %bv, %cv
    %nb0 = xor i32 %bv, -1
    %f0b = and i32 %nb0, %dv
    %f0 = or i32 %f0a, %f0b
    br label %rjoin
  r1:
    %f1a = and i32 %dv, %bv
    %nd1 = xor i32 %dv, -1
    %f1b = and i32 %nd1, %cv
    %f1 = or i32 %f1a, %f1b
    %g1a = mul i64 %iv, 5
    %g1b = add i64 %g1a, 1
    %g1 = and i64 %g1b, 15
    br label %rjoin
  r2:
    %f2a = xor i32 %bv, %cv
    %f2 = xor i32 %f2a, %dv
    %g2a = mul i64 %iv, 3
    %g2b = add i64 %g2a, 5
    %g2 = and i64 %g2b, 15
    br label %rjoin
  r3:
    %nd3 = xor i32 %dv, -1
    %f3a = or i32 %bv, %nd3
    %f3 = xor i32 %cv, %f3a
    %g3a = mul i64 %iv, 7
    %g3 = and i64 %g3a, 15
    br label %rjoin
  rjoin:
    %f = phi i32 [%f0, %r0], [%f1, %r1], [%f2, %r2], [%f3, %r3]
    %g = phi i64 [%iv, %r0], [%g1, %r1], [%g2, %r2], [%g3, %r3]
    %bo = mul i64 %bk, 64
    %bo2 = add i64 %at, %bo
    %g4 = mul i64 %g, 4
    %mo = add i64 %bo2, %g4
    %mp = getelementptr i8, ptr %pb, i64 %mo
    %m = load i32, ptr %mp, align 1
    %kp = getelementptr i64, ptr %pk, i64 %iv
    %k64 = load i64, ptr %kp
    %k = trunc i64 %k64 to i32
    %rp = getelementptr i64, ptr %pr, i64 %iv
    %r64 = load i64, ptr %rp
    %r = trunc i64 %r64 to i32
    %t1 = add i32 %f, %av
    %t2 = add i32 %t1, %k
    %t3 = add i32 %t2, %m
    %rot = call i32 @llvm.fshl.i32(i32 %t3, i32 %t3, i32 %r)
    %nb = add i32 %bv, %rot
    store i32 %dv, ptr %a
    store i32 %cv, ptr %d
    store i32 %bv, ptr %c
    store i32 %nb, ptr %b
    %i1 = add i64 %iv, 1
    store i64 %i1, ptr %i
    br label %rloop
  bend:
    %ea = load i32, ptr %a
    %eb = load i32, ptr %b
    %ec = load i32, ptr %c
    %ed = load i32, ptr %d
    %o0 = load i64, ptr %ps
    %o1 = load i64, ptr %p1
    %o2 = load i64, ptr %p2
    %o3 = load i64, ptr %p3
    %oa = trunc i64 %o0 to i32
    %ob = trunc i64 %o1 to i32
    %oc = trunc i64 %o2 to i32
    %od = trunc i64 %o3 to i32
    %na = add i32 %oa, %ea
    %nbb = add i32 %ob, %eb
    %nc = add i32 %oc, %ec
    %nd = add i32 %od, %ed
    %za = zext i32 %na to i64
    %zb = zext i32 %nbb to i64
    %zc = zext i32 %nc to i64
    %zd = zext i32 %nd to i64
    store i64 %za, ptr %ps
    store i64 %zb, ptr %p1
    store i64 %zc, ptr %p2
    store i64 %zd, ptr %p3
    %bk1 = add i64 %bk, 1
    store i64 %bk1, ptr %blk
    br label %bloop
  done:
    ret i64 %nblk
  IR

# CRC-8 (tab = flac_crc8_table) or CRC-16 (wide = 1, tab = flac_crc16_table) of b[from .. to).
fn flac_crc(b, from, to, tab, wide) (u8[] i64 i64 i64[] i64) i64
  ll <<~IR
  entry:
    %pb = inttoptr i64 %b to ptr
    %pt = inttoptr i64 %tab to ptr
    %i = alloca i64
    %c = alloca i64
    store i64 %from, ptr %i
    store i64 0, ptr %c
    %w = icmp eq i64 %wide, 1
    br label %loop
  loop:
    %iv = load i64, ptr %i
    %more = icmp slt i64 %iv, %to
    br i1 %more, label %body, label %done
  body:
    %bp = getelementptr i8, ptr %pb, i64 %iv
    %by = load i8, ptr %bp
    %bz = zext i8 %by to i64
    %cv = load i64, ptr %c
    br i1 %w, label %c16, label %c8
  c8:
    %x8 = xor i64 %cv, %bz
    %t8p = getelementptr i64, ptr %pt, i64 %x8
    %n8 = load i64, ptr %t8p
    store i64 %n8, ptr %c
    br label %next
  c16:
    %hi = lshr i64 %cv, 8
    %x16 = xor i64 %hi, %bz
    %t16p = getelementptr i64, ptr %pt, i64 %x16
    %t16 = load i64, ptr %t16p
    %sh = shl i64 %cv, 8
    %sm = and i64 %sh, 65535
    %n16 = xor i64 %sm, %t16
    store i64 %n16, ptr %c
    br label %next
  next:
    %i1 = add i64 %iv, 1
    store i64 %i1, ptr %i
    br label %loop
  done:
    %r = load i64, ptr %c
    ret i64 %r
  IR

# ---------------------------------------------------------------------------------------------- tables

-> flac_crc_table(poly, width) (i64 i64) i64[]
  t = i64[256]
  top = 1 << (width - 1)
  mask = (1 << width) - 1
  i = 0
  while i < 256
    c = i << (width - 8)
    k = 0
    while k < 8
      if (c & top) != 0
        c = ((c << 1) ^ poly) & mask
      else
        c = (c << 1) & mask
      k += 1
    t[i] = c
    i += 1
  t

# ---------------------------------------------------------------------------------------------- metadata

# hi (i64[16]) from the metadata: [0] channels, [1] bits per sample, [2] sample rate, [3] total samples (per channel), [4] byte
# offset of the first frame, [5] min block size, [6] max block size, [7] min frame size, [8] max frame size, [9] STREAMINFO's
# offset (its MD5 at [9] + 18). Raises on anything that is not a FLAC stream this reader can decode.
-> flac_header_into(b, hi)
  nb = b.size
  at = 0
  # an ID3v2 tag in front: "ID3", version (2), flags, a 28-bit syncsafe size (+ a 10-byte footer when flagged)
  if nb >= 10 && b[0] == 73 && b[1] == 68 && b[2] == 51
    at = 10 + (b[6] & 127) * 2097152 + (b[7] & 127) * 16384 + (b[8] & 127) * 128 + (b[9] & 127)
    at += 10 if (b[5] & 16) != 0
  raise "flac: too short for a header ([nb] bytes)" if at + 8 > nb
  raise "flac: not a FLAC stream (no fLaC marker)" if b[at] != 102 || b[at + 1] != 76 || b[at + 2] != 97 || b[at + 3] != 67
  at += 4
  last = 0
  seen = 0
  while last == 0
    raise "flac: metadata runs past the end ([nb] bytes)" if at + 4 > nb
    last = b[at] >> 7
    typ = b[at] & 127
    ln = b[at + 1] * 65536 + b[at + 2] * 256 + b[at + 3]
    at += 4
    raise "flac: metadata block of type [typ] runs past the end" if at + ln > nb
    raise "flac: invalid metadata block type 127" if typ == 127
    if seen == 0
      raise "flac: the first metadata block is not STREAMINFO (type [typ])" if typ != 0
      raise "flac: STREAMINFO is [ln] bytes, not 34" if ln != 34
      hi[5] = b[at] * 256 + b[at + 1]
      hi[6] = b[at + 2] * 256 + b[at + 3]
      hi[7] = b[at + 4] * 65536 + b[at + 5] * 256 + b[at + 6]
      hi[8] = b[at + 7] * 65536 + b[at + 8] * 256 + b[at + 9]
      hi[2] = b[at + 10] * 4096 + b[at + 11] * 16 + (b[at + 12] >> 4)
      hi[0] = ((b[at + 12] >> 1) & 7) + 1
      hi[1] = (b[at + 12] & 1) * 16 + (b[at + 13] >> 4) + 1
      hi[3] = (b[at + 13] & 15) * 4294967296 + b[at + 14] * 16777216 + b[at + 15] * 65536 + b[at + 16] * 256 + b[at + 17]
      hi[9] = at
    elsif typ == 0
      raise "flac: a second STREAMINFO block"
    seen += 1
    at += ln
  raise "flac: [hi[1]] bits per sample (4..32 decoded)" if hi[1] < 4 || hi[1] > 32
  raise "flac: sample rate 0" if hi[2] < 1
  raise "flac: block sizes [hi[5]]..[hi[6]]" if hi[5] < 16 || hi[6] < hi[5]
  raise "flac: no total sample count in STREAMINFO (not supported)" if hi[3] < 1
  hi[4] = at
  hi

# STREAMINFO's MD5 as 32 lowercase hex digits
-> flac_md5_hex_of(b, hi)
  hx = "0123456789abcdef"
  s = ""
  k = 0
  while k < 16
    v = b[hi[9] + 18 + k]
    s = s + hx.slice(v >> 4, 1) + hx.slice(v & 15, 1)
    k += 1
  s

# ---------------------------------------------------------------------------------------------- frames

# The residual of one subframe after `order` warm-up samples, into s[s0 + order .. s0 + bs). Returns the bit position after it or
# a negative code (−5 bad residual coding, −7 truncated).
-> flac_residual(b, nb, pos, bs, order, s, s0) (u8[] i64 i64 i64 i64 i64[] i64) i64
  m = flac_bits(b, nb, pos, 2)
  pos += 2
  if m > 1
    return -5
  pw = 4 + m
  esc = (1 << pw) - 1
  po = flac_bits(b, nb, pos, 4)
  pos += 4
  np = 1 << po
  psz = bs >> po
  if psz * np != bs || psz < order
    return -5
  o = s0 + order
  p = 0
  while p < np
    cnt = psz
    if p == 0
      cnt = psz - order
    k = flac_bits(b, nb, pos, pw)
    pos += pw
    if k == esc
      n = flac_bits(b, nb, pos, 5)
      pos += 5
      pos = flac_raw(b, nb, pos, n, s, o, cnt)
    elsif cnt > 0
      pos = flac_rice(b, nb, pos, k, s, o, cnt)
    if pos < 0 || pos > nb * 8
      return -7
    o += cnt
    p += 1
  pos

# One subframe of bs samples of sbps bits into s[s0 .. s0 + bs). Returns the bit position after it or a negative code (−4 bad
# subframe header, −5 bad residual, −7 truncated, −9 bad LPC precision or shift).
-> flac_subframe(b, nb, pos, sbps, bs, s, s0, coef) (u8[] i64 i64 i64 i64 i64[] i64 i64[]) i64
  if pos + 8 > nb * 8
    return -7
  h = flac_bits(b, nb, pos, 8)
  pos += 8
  if (h >> 7) != 0
    return -4
  t = (h >> 1) & 63
  w = 0
  if (h & 1) == 1
    w = 1
    while flac_bits(b, nb, pos, 1) == 0
      w += 1
      pos += 1
      if pos >= nb * 8
        return -7
    pos += 1
    if w >= sbps
      return -4
  eb = sbps - w
  if t == 0
    pos = flac_raw(b, nb, pos, eb, s, s0, 1)
    if pos < 0
      return -7
    flac_fill(s, s0 + 1, bs - 1, s[s0])
  elsif t == 1
    pos = flac_raw(b, nb, pos, eb, s, s0, bs)
    if pos < 0
      return -7
  elsif t >= 8 && t <= 12
    order = t - 8
    if order > bs
      return -4
    pos = flac_raw(b, nb, pos, eb, s, s0, order)
    if pos < 0
      return -7
    pos = flac_residual(b, nb, pos, bs, order, s, s0)
    if pos < 0
      return pos
    if order == 1
      coef[0] = 1
    elsif order == 2
      coef[0] = 2
      coef[1] = -1
    elsif order == 3
      coef[0] = 3
      coef[1] = -3
      coef[2] = 1
    elsif order == 4
      coef[0] = 4
      coef[1] = -6
      coef[2] = 4
      coef[3] = -1
    if order > 0
      flac_lpc(s, s0, bs, order, coef, 0)
  elsif t >= 32
    order = (t & 31) + 1
    if order > bs
      return -4
    pos = flac_raw(b, nb, pos, eb, s, s0, order)
    if pos < 0
      return -7
    prec = flac_bits(b, nb, pos, 4) + 1
    pos += 4
    if prec == 16
      return -9
    sh = flac_bits(b, nb, pos, 5)
    pos += 5
    if sh >= 16
      return -9
    pos = flac_raw(b, nb, pos, prec, coef, 0, order)
    if pos < 0
      return -7
    pos = flac_residual(b, nb, pos, bs, order, s, s0)
    if pos < 0
      return pos
    flac_lpc(s, s0, bs, order, coef, sh)
  else
    return -4
  if w > 0
    flac_shl(s, s0, bs, w)
  pos

# One frame at byte `at`: its subframes into s (channel c at c·stride), decorrelated. Returns the byte after the frame or a
# negative code (−1 no frame sync, −2 bad or reserved header field, −3 header CRC, −4..−9 as the subframes, −6 frame CRC,
# −7 truncated, −8 a frame that does not fit STREAMINFO: its channels, or a block larger than s holds). fr receives [0] block size, [1] channel assignment, [2] bits,
# [3] sample rate, [4] channels, [5] the coded frame/sample number, [6] blocking strategy, [7] the failing subframe.
-> flac_frame(b, nb, at, hi, s, stride, coef, fr, t8, t16) (u8[] i64 i64 i64[] i64[] i64 i64[] i64[] i64[] i64[]) i64
  if at + 6 > nb
    return -7
  x = flac_bits(b, nb, at * 8, 32)
  if (x >> 18) != 16382
    return -1
  if ((x >> 17) & 1) != 0 || (x & 1) != 0
    return -2
  strat = (x >> 16) & 1
  bsc = (x >> 12) & 15
  src = (x >> 8) & 15
  cha = (x >> 4) & 15
  ssc = (x >> 1) & 7
  p = at + 4
  c0 = b[p]
  ln = 0
  num = 0
  if c0 < 128
    num = c0
    ln = 1
  elsif (c0 & 224) == 192
    num = c0 & 31
    ln = 2
  elsif (c0 & 240) == 224
    num = c0 & 15
    ln = 3
  elsif (c0 & 248) == 240
    num = c0 & 7
    ln = 4
  elsif (c0 & 252) == 248
    num = c0 & 3
    ln = 5
  elsif (c0 & 254) == 252
    num = c0 & 1
    ln = 6
  elsif c0 == 254
    ln = 7
  else
    return -2
  if p + ln + 4 > nb
    return -7
  j = 1
  while j < ln
    cb = b[p + j]
    if (cb & 192) != 128
      return -2
    num = num * 64 + (cb & 63)
    j += 1
  p += ln
  bs = 0
  if bsc == 0
    return -2
  elsif bsc == 1
    bs = 192
  elsif bsc <= 5
    bs = 576 << (bsc - 2)
  elsif bsc == 6
    bs = b[p] + 1
    p += 1
  elsif bsc == 7
    bs = b[p] * 256 + b[p + 1] + 1
    p += 2
  else
    bs = 256 << (bsc - 8)
  rate = 0
  if src == 0
    rate = hi[2]
  elsif src == 1
    rate = 88200
  elsif src == 2
    rate = 176400
  elsif src == 3
    rate = 192000
  elsif src == 4
    rate = 8000
  elsif src == 5
    rate = 16000
  elsif src == 6
    rate = 22050
  elsif src == 7
    rate = 24000
  elsif src == 8
    rate = 32000
  elsif src == 9
    rate = 44100
  elsif src == 10
    rate = 48000
  elsif src == 11
    rate = 96000
  elsif src == 12
    rate = b[p] * 1000
    p += 1
  elsif src == 13
    rate = b[p] * 256 + b[p + 1]
    p += 2
  elsif src == 14
    rate = (b[p] * 256 + b[p + 1]) * 10
    p += 2
  else
    return -2
  bits = 0
  if ssc == 0
    bits = hi[1]
  elsif ssc == 1
    bits = 8
  elsif ssc == 2
    bits = 12
  elsif ssc == 3
    return -2
  elsif ssc == 4
    bits = 16
  elsif ssc == 5
    bits = 20
  elsif ssc == 6
    bits = 24
  else
    bits = 32
  nch = cha + 1
  if cha >= 8 && cha <= 10
    nch = 2
  elsif cha > 10
    return -2
  if p >= nb
    return -7
  if flac_crc(b, at, p, t8, 0) != b[p]
    return -3
  p += 1
  fr[0] = bs
  fr[1] = cha
  fr[2] = bits
  fr[3] = rate
  fr[4] = nch
  fr[5] = num
  fr[6] = strat
  if bs > stride || nch != hi[0]
    return -8
  pos = p * 8
  c = 0
  while c < nch
    sb = bits
    if (cha == 8 && c == 1) || (cha == 9 && c == 0) || (cha == 10 && c == 1)
      sb = bits + 1
    pos = flac_subframe(b, nb, pos, sb, bs, s, c * stride, coef)
    if pos < 0
      fr[7] = c
      return pos
    c += 1
  q = (pos + 7) / 8
  if q + 2 > nb
    return -7
  if t16.size > 0 && flac_crc(b, at, q, t16, 1) != b[q] * 256 + b[q + 1]
    return -6
  if cha >= 8
    flac_decorr(s, stride, bs, cha)
  q + 2

-> flac_error_text(code)
  return "lost frame sync" if code == -1
  return "bad frame header" if code == -2
  return "frame header CRC-8 mismatch" if code == -3
  return "bad subframe header" if code == -4
  return "bad residual coding" if code == -5
  return "frame CRC-16 mismatch" if code == -6
  return "truncated frame" if code == -7
  return "frame does not match STREAMINFO" if code == -8
  return "bad LPC precision or shift" if code == -9
  "error " + code.to_s

# Decode frames from hi[4] until `want` samples per channel are out (want <= hi[3]). mode 0: interleaved 32-bit pcm[f·ch + c];
# mode 1: planar floats (channel 0 into l, channel 1 into r; a mono stream into both), each sample / 2^(bits − 1).
# Returns the samples decoded per channel, or a negative code with fr[8] = the frame's byte offset, fr[9] = samples done.
-> flac_run(b, nb, hi, want, mode, pcm, l, r, s, stride, coef, fr, t8, t16) (u8[] i64 i64[] i64 i64 i32[] f64[] f64[] i64[] i64 i64[] i64[] i64[] i64[]) i64
  ch = hi[0]
  bits = hi[1]
  at = hi[4]
  done = 0
  while done < want
    nxt = flac_frame(b, nb, at, hi, s, stride, coef, fr, t8, t16)
    if nxt >= 0 && (fr[4] != ch || fr[2] != bits || fr[3] != hi[2])
      nxt = -8
    if nxt < 0
      fr[8] = at
      fr[9] = done
      return nxt
    n = fr[0]
    if done + n > want
      n = want - done
    if mode == 0
      c = 0
      while c < ch
        flac_put_i32(pcm, done, ch, c, s, c * stride, n)
        c += 1
    else
      flac_put_f64(l, done, s, 0, n, bits)
      if ch >= 2
        flac_put_f64(r, done, s, stride, n, bits)
      else
        flac_put_f64(r, done, s, 0, n, bits)
    done += n
    at = nxt
  hi[10] = at
  done

# ---------------------------------------------------------------------------------------------- API

# A decoder's buffers, reused across files (a batch keeps memory flat): sample blocks (8 channels × 65,536), coefficients,
# the CRC tables.
-> flac_state_new
  {s: i64[8 * 65536], coef: i64[32], fr: i64[10], hi: i64[16], t8: flac_crc_table(7, 8), t16: flac_crc_table(32773, 16), pcm: i32[1], pk: u8[65536], f1: f64[1]}

-> flac_raise(code, fr, what)
  raise "flac: " + flac_error_text(code) + " (frame at byte [fr[8]], after [fr[9]] samples, subframe [fr[7]])" + what

# Decode a FLAC image: {ch, bits, rate, frames, md5 (STREAMINFO's, hex), pcm (i32[] interleaved; in a batch valid until the next
# call)}. Raises on a malformed stream, naming the frame.
-> flac_decode_with(stt, b)
  hi = flac_header_into(b, stt[:hi])
  ch = hi[0]
  frames = hi[3]
  if stt[:pcm].size < frames * ch
    stt[:pcm] = i32[frames * ch + frames * ch / 4]
  got = flac_run(b, b.size, hi, frames, 0, stt[:pcm], stt[:f1], stt[:f1], stt[:s], 65536, stt[:coef], stt[:fr], stt[:t8], stt[:t16])
  flac_raise(got, stt[:fr], "") if got < 0
  {ch: ch, bits: hi[1], rate: hi[2], frames: frames, md5: flac_md5_hex_of(b, hi), pcm: stt[:pcm]}

-> flac_decode(b)
  flac_decode_with(flac_state_new(), b)

-> flac_read(path)
  flac_decode(File.read_bytes(path))

# The first maxf samples per channel (maxf <= 0: all) as planar floats: [rate, frames, l, r], the integer samples divided by
# 2^(bits − 1), a mono stream in both l and r, only channels 0 and 1 of a wider one; decodes only the frames those samples need.
# flac_read_planar sizes its block buffer from STREAMINFO (channels × max block size: 64 KB for `flac -8` stereo), for callers
# that read one file at a time (the sampler); flac_read_planar_with reuses a batch state.
-> flac_read_planar(b, maxf)
  hi = flac_header_into(b, i64[16])
  nf = hi[3]
  nf = maxf if maxf > 0 && maxf < nf
  l = f64[nf]
  r = f64[nf]
  fr = i64[10]
  got = flac_run(b, b.size, hi, nf, 1, i32[1], l, r, i64[hi[0] * hi[6]], hi[6], i64[32], fr, flac_crc_table(7, 8), flac_crc_table(32773, 16))
  flac_raise(got, fr, "") if got < 0
  [hi[2], nf, l, r]

-> flac_read_planar_with(stt, b, maxf)
  hi = flac_header_into(b, stt[:hi])
  nf = hi[3]
  nf = maxf if maxf > 0 && maxf < nf
  l = f64[nf]
  r = f64[nf]
  got = flac_run(b, b.size, hi, nf, 1, stt[:pcm], l, r, stt[:s], 65536, stt[:coef], stt[:fr], stt[:t8], stt[:t16])
  flac_raise(got, stt[:fr], "") if got < 0
  [hi[2], nf, l, r]

# The same from a file, read through a memory map (nothing of the file stays allocated after the call).
-> flac_read_planar_file(path, maxf)
  mm = File.mmap(path)
  w = nil
  begin
    w = flac_read_planar(mm.as_u8, maxf)
  rescue e
    mm.close
    raise e.to_s + " in " + path
  mm.close
  w

# ---------------------------------------------------------------------------------------------- MD5 (streaming, RFC 1321)

FLAC_MD5_K = [0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee, 0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501, 0x698098d8, 0x8b44f7af,
  0xffff5bb1, 0x895cd7be, 0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821, 0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa, 0xd62f105d,
  0x02441453, 0xd8a1e681, 0xe7d3fbc8, 0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed, 0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
  0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c, 0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70, 0x289b7ec6, 0xeaa127fa, 0xd4ef3085,
  0x04881d05, 0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665, 0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039, 0x655b59c3, 0x8f0ccc92,
  0xffeff47d, 0x85845dd1, 0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1, 0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391]
FLAC_MD5_S = [7, 12, 17, 22, 5, 9, 14, 20, 4, 11, 16, 23, 6, 10, 15, 21]

# a running MD5: {st, kt, sh, n (bytes fed), tail (u8[64]), tl (bytes in it)}
-> flac_md5_new
  kt = i64[64]
  sh = i64[64]
  i = 0
  while i < 64
    kt[i] = FLAC_MD5_K[i]
    sh[i] = FLAC_MD5_S[(i / 16) * 4 + i % 4]
    i += 1
  st = i64[4]
  st[0] = 0x67452301
  st[1] = 0xefcdab89
  st[2] = 0x98badcfe
  st[3] = 0x10325476
  {st: st, kt: kt, sh: sh, n: 0, tail: u8[64], tl: 0}

# feed buf[at .. at + len) (a u8[] or a memory map's bytes)
-> flac_md5_feed(md, buf, at, len)
  md[:n] = md[:n] + len
  tl = md[:tl]
  t = md[:tail]
  if tl > 0
    while tl < 64 && len > 0
      t[tl] = buf[at]
      tl += 1
      at += 1
      len -= 1
    if tl == 64
      flac_md5_blocks(t, 0, 1, md[:st], md[:kt], md[:sh])
      tl = 0
  nb = len / 64
  if nb > 0
    flac_md5_blocks(buf, at, nb, md[:st], md[:kt], md[:sh])
    at += nb * 64
    len -= nb * 64
  while len > 0
    t[tl] = buf[at]
    tl += 1
    at += 1
    len -= 1
  md[:tl] = tl
  md

# the digest, 32 lowercase hex digits (the state is spent)
-> flac_md5_hex(md)
  bits = md[:n] * 8
  pad = u8[72]
  pad[0] = 128
  k = (119 - md[:n] % 64) % 64
  i = 0
  while i < 8
    pad[k + 1 + i] = (bits >> (8 * i)) & 255
    i += 1
  flac_md5_feed(md, pad, 0, k + 9)
  hx = "0123456789abcdef"
  s = ""
  w = 0
  while w < 4
    v = md[:st][w]
    i = 0
    while i < 4
      by = (v >> (8 * i)) & 255
      s = s + hx.slice(by >> 4, 1) + hx.slice(by & 15, 1)
      i += 1
    w += 1
  s

# The MD5 of decoded samples as FLAC computes it (interleaved, little-endian, ceil(bits/8) bytes, signed), packed 16,384 samples
# at a time into pk (u8[] of at least 65,536 bytes, reused). With wav (a WAV image's bytes) the same packed bytes are compared
# with wav[at ..]: returns [hex, the first differing byte or −1].
-> flac_pcm_md5_cmp(pcm, frames, ch, bits, pk, wav, at)
  bps = (bits + 7) / 8
  n = frames * ch
  md = flac_md5_new()
  diff = -1
  o = 0
  while o < n
    c = 16384
    c = n - o if n - o < c
    nb = flac_pack_at(pcm, o, c, bps, pk)
    flac_md5_feed(md, pk, 0, nb)
    if wav != nil && diff < 0
      k = flac_cmp(pk, 0, wav, at + o * bps, nb)
      diff = o * bps + k if k >= 0
    o += c
  [flac_md5_hex(md), diff]

-> flac_pcm_md5(pcm, frames, ch, bits)
  flac_pcm_md5_cmp(pcm, frames, ch, bits, u8[65536], nil, 0)[0]

# ---------------------------------------------------------------------------------------------- `studio flaccheck`

# [format tag, channels, rate, bits, block align, data offset, data length] of a RIFF WAVE image (the last fmt and data chunks),
# or nil when it is not one.
-> flac_wav_info(b)
  return nil if b.size < 12 || b[0] != 82 || b[1] != 73 || b[2] != 70 || b[3] != 70 || b[8] != 87 || b[9] != 65 || b[10] != 86 || b[11] != 69
  pos = 12
  tag = -1
  ch = 0
  rate = 0
  bits = 0
  ba = 0
  dat = -1
  dlen = 0
  while pos + 8 <= b.size
    ln = b[pos + 4] + b[pos + 5] * 256 + b[pos + 6] * 65536 + b[pos + 7] * 16777216
    if b[pos] == 102 && b[pos + 1] == 109 && b[pos + 2] == 116 && b[pos + 3] == 32 && pos + 24 <= b.size
      tag = b[pos + 8] + b[pos + 9] * 256
      ch = b[pos + 10] + b[pos + 11] * 256
      rate = b[pos + 12] + b[pos + 13] * 256 + b[pos + 14] * 65536 + b[pos + 15] * 16777216
      ba = b[pos + 20] + b[pos + 21] * 256
      bits = b[pos + 22] + b[pos + 23] * 256
      if tag == 65534 && ln >= 26 && pos + 34 <= b.size
        tag = b[pos + 32] + b[pos + 33] * 256
    if b[pos] == 100 && b[pos + 1] == 97 && b[pos + 2] == 116 && b[pos + 3] == 97
      dat = pos + 8
      dlen = ln
      dlen = b.size - dat if dat + dlen > b.size
    pos = pos + 8 + ln + (ln % 2)
  return nil if tag < 0 || dat < 0
  [tag, ch, rate, bits, ba, dat, dlen]

# every .flac under dir (depth first, names sorted; symbolic links to directories not followed)
-> flac_find(dir, out)
  ents = File.children(dir).sort
  i = 0
  while i < ents.size
    e = ents[i]
    if e != "." && e != ".."
      p = dir + "/" + e
      if File.directory?(p) && !File.symlink?(p)
        flac_find(p, out)
      elsif e.ends_with?(".flac") && File.file?(p)
        out.push(p)
    i += 1
  out

-> flac_strip_slash(p)
  while p.size > 1 && p.ends_with?("/")
    p = p.slice(0, p.size - 1)
  p

# One file: decode, check the MD5, and with a WAV the format and every sample. Both files are read through memory maps and the
# buffers are the state's, so a run over any number of files stays flat in memory. Returns a TSV line:
#   rel  OK|FAIL  frames  channels  bits  rate  pcm-md5  wav-file-md5 (or -)  detail
-> flaccheck_one(stt, path, rel, wav)
  mm = File.mmap(path)
  st = "OK"
  why = []
  d = nil
  begin
    d = flac_decode_with(stt, mm.as_u8)
  rescue e
    mm.close
    raise e.to_s
  mm.close
  wm = nil
  wb = nil
  wi = nil
  wmd5 = "-"
  if wav != nil
    if !File.exist?(wav)
      st = "FAIL"
      why.push("no WAV")
    else
      wm = File.mmap(wav)
      wb = wm.as_u8
      md = flac_md5_new()
      flac_md5_feed(md, wb, 0, wb.size)
      wmd5 = flac_md5_hex(md)
      wi = flac_wav_info(wb)
      if wi == nil
        st = "FAIL"
        why.push("WAV unreadable")
  bps = (d[:bits] + 7) / 8
  nbytes = d[:frames] * d[:ch] * bps
  cmpw = nil
  if wi != nil
    if wi[0] != 1 || wi[1] != d[:ch] || wi[2] != d[:rate] || wi[3] != d[:bits] || wi[4] != d[:ch] * bps
      st = "FAIL"
      why.push("format: WAV tag [wi[0]] [wi[1]] ch [wi[2]] Hz [wi[3]] bits align [wi[4]]")
    elsif wi[6] / wi[4] != d[:frames]
      st = "FAIL"
      why.push("frames: WAV [wi[6] / wi[4]], FLAC [d[:frames]]")
    else
      cmpw = wb
      why.push("WAV data has [wi[6] - nbytes] trailing bytes") if wi[6] - nbytes != 0
  at = 0
  at = wi[5] if cmpw != nil
  mp = flac_pcm_md5_cmp(d[:pcm], d[:frames], d[:ch], d[:bits], stt[:pk], cmpw, at)
  wm.close if wm != nil
  if mp[0] != d[:md5]
    st = "FAIL"
    why.unshift("decoded MD5 [mp[0]] != STREAMINFO [d[:md5]]")
  if mp[1] >= 0
    st = "FAIL"
    why.unshift("sample bytes differ from byte [mp[1]] (frame [mp[1] / (d[:ch] * bps)])")
  wd = "-"
  wd = why.join("; ") if why.size > 0
  [rel, st, d[:frames].to_s, d[:ch].to_s, d[:bits].to_s, d[:rate].to_s, mp[0], wmd5, wd].join("\t")

# studio flaccheck <in.flac|dir> [--wav <dir>] [--list <file>] [--out <file>] [--shard k/n]
# Decodes every file (a directory walked depth-first), checks the decoded samples' MD5 against STREAMINFO and, with --wav, the
# WAV at the same relative path (x/y.flac -> <dir>/x/y.wav): format, length and every sample byte; prints (or appends to --out)
# one TSV line per file (flaccheck_one) and a summary. --list restricts it to the relative paths in a file (one a line);
# --shard k/n takes every n-th of them from the k-th (0-based); files already in --out are skipped (resumable). Returns 1 when
# any file failed.
-> flaccheck_cli(args)
  wavd = nil
  lst = nil
  outp = nil
  shk = 0
  shn = 1
  pos = []
  i = 1
  while i < args.size
    a = args[i]
    if a == "--wav" && i + 1 < args.size
      wavd = flac_strip_slash(args[i + 1])
      i += 1
    elsif a == "--list" && i + 1 < args.size
      lst = args[i + 1]
      i += 1
    elsif a == "--out" && i + 1 < args.size
      outp = args[i + 1]
      i += 1
    elsif a == "--shard" && i + 1 < args.size
      ks = args[i + 1].split("/")
      shk = ks[0].to_i
      shn = ks[1].to_i
      i += 1
    else
      pos.push(a)
    i += 1
  if pos.size < 1 || shn < 1
    << "usage: studio flaccheck <in.flac|dir> \[--wav <dir>] \[--list <file>] \[--out <file>] \[--shard k/n]"
    return 2
  src = flac_strip_slash(pos[0])
  single = !File.directory?(src)
  rels = []
  if single
    rels.push(src)
  elsif lst != nil
    ls = File.read(lst).split("\n")
    k = 0
    while k < ls.size
      rels.push(ls[k]) if ls[k].size > 0
      k += 1
  else
    fs = flac_find(src, [])
    k = 0
    while k < fs.size
      rels.push(fs[k].slice(src.size + 1, fs[k].size - src.size - 1))
      k += 1
  done = {}
  if outp != nil && File.exist?(outp)
    ol = File.read(outp).split("\n")
    k = 0
    while k < ol.size
      t = ol[k].index("\t")
      done[ol[k].slice(0, t)] = 1 if t != nil
      k += 1
  fh = nil
  fh = FileHandle.new(outp, "ab") if outp != nil
  stt = flac_state_new()
  nok = 0
  nfail = 0
  nskip = 0
  frames = 0
  t0 = clock_ms()
  k = 0
  while k < rels.size
    if k % shn == shk
      rel = rels[k]
      if done.has_key?(rel)
        nskip += 1
      else
        path = rel
        path = src + "/" + rel if !single
        wav = nil
        if wavd != nil
          stem = rel
          stem = rel.slice(0, rel.size - 5) if rel.ends_with?(".flac")
          wav = wavd + "/" + stem + ".wav"
        line = ""
        begin
          line = flaccheck_one(stt, path, rel, wav)
        rescue e
          line = [rel, "FAIL", "0", "0", "0", "0", "-", "-", e.to_s.gsub("\t", " ")].join("\t")
        if line.split("\t")[1] == "OK"
          nok += 1
          frames += line.split("\t")[2].to_i
        else
          nfail += 1
        if fh != nil
          fh.write(line + "\n")
          fh.flush
        else
          << line
    k += 1
  fh.close if fh != nil
  << "flaccheck: [nok] OK, [nfail] failed, [nskip] skipped (already checked); [frames] frames; [clock_ms() - t0] ms"
  return 1 if nfail > 0
  0
