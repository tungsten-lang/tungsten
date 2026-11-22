# core/codec/audio/mp3 — an MPEG-1/2/2.5 audio decoder (Layer I, II and III) for
# Blade's media pipeline.
#
#   acodec_register("mp3 ", …): cfg.extra is nil; one MPEG audio frame per
#   MediaSample (the layer, rate and channels come from each frame header).
#   decode(sample) -> AudioBlock of f32 interleaved samples (1152 / 576 / 384
#   frames). The Layer III bit reservoir is carried across samples on the
#   decoder; reset clears it (and the IMDCT / synthesis history).
#   mp3_es_parse(bytes) splits an .mp3 file into frames: {cfg:, samples:,
#   duration:} — ID3v2 / ID3v1 / APEv2 tags skipped, frame sync checked
#   against the following header, a Xing/Info or VBRI frame dropped (and used
#   for the duration), and the LAME encoder delay (+ the 529-sample decoder
#   delay, as ffmpeg) put into the pts so the pipeline trims the priming.
#
# The decoding pipeline follows minimp3 (https://github.com/lieff/minimp3,
# CC0): side info, scalefactors (MPEG-1 with scfsi, MPEG-2 LSF incl. the
# intensity-stereo variants), its packed Huffman tables, mid/side and
# intensity stereo, short / mixed block reordering, alias reduction, IMDCT
# 36/12 with overlap, frequency inversion and the polyphase synthesis
# (DCT-II + windowing with the ISO window scaled by 2^16). Arithmetic is f64
# here, with exact x^(4/3) and 2^(x/4) tables and trigonometric constants
# computed at load, so the output sits within float rounding of ffmpeg.
# All decoder state is on the Mp3Dec instance; the module tables are
# read-only after load.

use core/codec/media
use mp3_tables

-> mp_i64(a)
  t = i64[a.size]
  i = 0
  while i < a.size
    t[i] = a[i]
    i += 1
  t

-> mp_f64(a)
  t = f64[a.size]
  i = 0
  while i < a.size
    t[i] = a[i] * ~1.0
    i += 1
  t

MP_TABS = mp_i64(MP_TABS_SRC)
MP_TAB32 = mp_i64(MP_TAB32_SRC)
MP_TAB33 = mp_i64(MP_TAB33_SRC)
MP_TABINDEX = mp_i64(MP_TABINDEX_SRC)
MP_LINBITS = mp_i64(MP_LINBITS_SRC)
MP_SFB = mp_i64(MP_SFB_SRC)
MP_SCF_PART = mp_i64(MP_SCF_PART_SRC)
MP_WIN = mp_f64(MP_WIN_SRC)
MP_BA_CODE = mp_i64(MP_BA_CODE_SRC)
MP_HALFRATE = mp_i64(MP_HALFRATE_SRC)
MP_SCFC_DECODE = mp_i64([0, 1, 2, 3, 12, 5, 6, 7, 9, 10, 11, 13, 14, 15, 18, 19])
MP_MOD = mp_i64([5, 5, 4, 4, 5, 5, 4, 1, 4, 3, 1, 1, 5, 6, 6, 1, 4, 4, 4, 1, 4, 3, 1, 1])
MP_PREAMP = mp_i64([1, 1, 1, 1, 2, 2, 3, 3, 3, 2])
# Layer I/II subband allocation: (code table offset, code width, band count)
# triples: L1 at 0, L2 MPEG-2 at 3, L2 MPEG-1 at 12, L2 MPEG-1 low rate at 24
MP_ALLOC = mp_i64([76, 4, 32, 60, 4, 4, 44, 3, 7, 44, 2, 19, 0, 4, 3, 16, 4, 8, 32, 3, 12, 40, 2, 7, 44, 4, 2, 44, 3, 10])

-> mp_deg(d) (f64) f64
  d * ~3.14159265358979323846 / ~180.0

-> mp_mk_pow43
  t = f64[8208]
  i = 0
  while i < 8208
    x = i * ~1.0
    t[i] = x * Math.cbrt(x)
    i += 1
  t

# 2^(-e/4) for e = 0 .. 1023
-> mp_mk_pow2q
  t = f64[1024]
  q = [~1.0, Math.exp(~-0.25 * Math.log(~2.0)), Math.exp(~-0.5 * Math.log(~2.0)), Math.exp(~-0.75 * Math.log(~2.0))]
  p = ~1.0
  e = 0
  while e < 1024
    t[e] = p * q[e % 4]
    p = p * ~0.5 if e % 4 == 3
    e += 1
  t

-> mp_mk_consts
  # 0..7 alias cs, 8..15 alias ca, 16..33 twid9, 34..39 twid3, 40..75 mdct windows (normal, stop),
  # 76..99 DCT-II secants, 100..113 MPEG-1 intensity pans, 114..122 dct3_9 / dct constants
  t = f64[128]
  ci = [~-0.6, ~-0.535, ~-0.33, ~-0.185, ~-0.095, ~-0.041, ~-0.0142, ~-0.0037]
  i = 0
  while i < 8
    c = ci[i]
    sq = Math.sqrt(~1.0 + c * c)
    t[i] = ~1.0 / sq
    t[8 + i] = (~0.0 - c) / sq
    i += 1
  i = 0
  while i < 9
    a = mp_deg(~42.5 - ~5.0 * i)
    t[16 + i] = Math.cos(a)
    t[25 + i] = Math.sin(a)
    i += 1
  t[34] = Math.cos(mp_deg(~37.5))
  t[35] = Math.cos(mp_deg(~22.5))
  t[36] = Math.cos(mp_deg(~7.5))
  t[37] = Math.sin(mp_deg(~37.5))
  t[38] = Math.sin(mp_deg(~22.5))
  t[39] = Math.sin(mp_deg(~7.5))
  i = 0
  while i < 9
    a = mp_deg(~2.5 * (2 * i + 1))
    t[40 + i] = Math.cos(a)
    t[49 + i] = Math.sin(a)
    i += 1
  i = 0
  while i < 6
    t[58 + i] = ~1.0
    t[67 + i] = ~0.0
    i += 1
  i = 0
  while i < 3
    a = mp_deg(~7.5 * (2 * i + 1))
    t[64 + i] = Math.cos(a)
    t[73 + i] = Math.sin(a)
    i += 1
  pi = ~3.14159265358979323846
  i = 0
  while i < 8
    t[76 + 3 * i] = ~1.0 / (~2.0 * Math.cos((31 - 2 * i) * pi / ~64.0))
    t[77 + 3 * i] = ~1.0 / (~2.0 * Math.cos((2 * i + 1) * pi / ~64.0))
    t[78 + 3 * i] = ~1.0 / (~2.0 * Math.cos((4 * i + 2) * pi / ~64.0))
    i += 1
  i = 0
  while i < 7
    k = Math.tan(i * pi / ~12.0)
    if i == 6
      t[100 + 2 * i] = ~1.0
      t[101 + 2 * i] = ~0.0
    else
      t[100 + 2 * i] = k / (~1.0 + k)
      t[101 + 2 * i] = ~1.0 / (~1.0 + k)
    i += 1
  t[114] = Math.cos(mp_deg(~20.0))
  t[115] = Math.cos(mp_deg(~40.0))
  t[116] = Math.cos(mp_deg(~80.0))
  t[117] = Math.cos(mp_deg(~30.0))
  t[118] = Math.cos(mp_deg(~10.0))
  t[119] = Math.cos(mp_deg(~70.0))
  t[120] = Math.cos(mp_deg(~50.0))
  t[121] = Math.sqrt(~0.5)
  t[122] = Math.tan(pi / ~16.0)
  t[123] = Math.sin(pi / ~8.0)
  t[124] = Math.sqrt(~2.0)
  t

# DCT-II butterfly output scales 1 / (2 cos(k pi / 16)), k = 1 .. 7
-> mp_mk_dsc
  t = f64[8]
  pi = ~3.14159265358979323846
  k = 1
  while k < 8
    t[k] = ~1.0 / (~2.0 * Math.cos(k * pi / ~16.0))
    k += 1
  t

# Layer I/II dequantisation: 2^-20 * 2^(-k/3) / (2^n - 1) like minimp3's g_deq_L12
-> mp_mk_deq12
  t = f64[54]
  den = [3, 7, 15, 31, 63, 127, 255, 511, 1023, 2047, 4095, 8191, 16383, 32767, 65535, 3, 5, 9]
  b = Math.exp(~-20.0 * Math.log(~2.0))
  i = 0
  while i < 18
    k = 0
    while k < 3
      t[i * 3 + k] = b * Math.exp((~0.0 - k) / ~3.0 * Math.log(~2.0)) / den[i]
      k += 1
    i += 1
  t

MP_POW43 = mp_mk_pow43()
MP_POW2Q = mp_mk_pow2q()
MP_C = mp_mk_consts()
MP_DSC = mp_mk_dsc()
MP_DEQ12 = mp_mk_deq12()

# ---- bit reading (st[0] position, st[1] limit, both in bits) ----

-> mp_bits(b, st, n) (u8[] i64[] i64) i64
  pos = st[0]
  st[0] = pos + n
  if pos + n > st[1]
    return 0
  s = pos & 7
  p = pos >> 3
  nxt = b[p] & (255 >> s)
  p += 1
  shl = n + s - 8
  cache = 0 ## i64
  while shl > 0
    cache = cache | (nxt << shl)
    nxt = b[p]
    p += 1
    shl -= 8
  cache | (nxt >> (0 - shl))

# ---- header ----

-> mp_hv(b, p) (u8[] i64) bool
  h0 = b[p] ## i64
  h1 = b[p + 1] ## i64
  h2 = b[p + 2] ## i64
  h0 == 255 && ((h1 & 240) == 240 || (h1 & 254) == 226) && ((h1 >> 1) & 3) != 0 && (h2 >> 4) != 15 && ((h2 >> 2) & 3) != 3

-> mp_hdr_kbps(h1, h2, hr) (i64 i64 i64[]) i64
  m1 = (h1 >> 3) & 1
  layer = (h1 >> 1) & 3
  2 * hr[m1 * 45 + (layer - 1) * 15 + (h2 >> 4)]

-> mp_hdr_rate(h1, h2) (i64 i64) i64
  r = 44100
  si = (h2 >> 2) & 3
  r = 48000 if si == 1
  r = 32000 if si == 2
  r = r >> 1 if (h1 & 8) == 0
  r = r >> 1 if (h1 & 16) == 0
  r

-> mp_hdr_spf(h1) (i64) i64
  return 384 if (h1 & 6) == 6
  return 576 if (h1 & 14) == 2
  1152

# frame length in bytes including padding; 0 for free format
-> mp_hdr_bytes(h1, h2, hr) (i64 i64 i64[]) i64
  kb = mp_hdr_kbps(h1, h2, hr)
  return 0 if kb == 0
  fb = mp_hdr_spf(h1) * kb * 125 / mp_hdr_rate(h1, h2)
  if (h1 & 6) == 6
    fb = fb & (0 - 4)
    fb += 4 if (h2 & 2) != 0
  else
    fb += 1 if (h2 & 2) != 0
  fb

# ---- Layer III side info ----
# gr record (24 i64 per granule/channel): 0 sfb table offset, 1 part2_3_length, 2 big_values,
# 3 scalefac_compress, 4 global_gain, 5 block_type, 6 mixed, 7 n_long_sfb, 8 n_short_sfb,
# 9..11 table_select, 12..14 region_count, 15..17 subblock_gain, 18 preflag, 19 scalefac_scale,
# 20 count1_table, 21 scfsi

-> mp_side_info(b, st, h1, h2, h3, gr) (u8[] i64[] i64 i64 i64 i64[]) i64
  mono = (h3 & 192) == 192
  nch = 2
  nch = 1 if mono
  mpeg1 = (h1 & 8) != 0
  istereo = (h3 & 208) == 80
  srx = ((h2 >> 2) & 3) + (((h1 >> 3) & 1) + ((h1 >> 4) & 1)) * 3
  srx -= 1 if srx != 0
  ngr = 1
  scfsi_all = 0 ## i64
  mdb = 0 ## i64
  if mpeg1
    ngr = 2
    mdb = mp_bits(b, st, 9)
    if mono
      mp_bits(b, st, 5)
    else
      mp_bits(b, st, 3)
    scfsi_all = mp_bits(b, st, 4 * nch)
  else
    mdb = mp_bits(b, st, 8 + nch) >> nch
  part_sum = 0 ## i64
  igr = 0 ## i64
  while igr < ngr
    ch = 0 ## i64
    while ch < nch
      g = (igr * nch + ch) * 24
      p23 = mp_bits(b, st, 12)
      part_sum += p23
      bv = mp_bits(b, st, 9)
      return -1 if bv > 288
      gg = mp_bits(b, st, 8)
      sfc = 0 ## i64
      if mpeg1
        sfc = mp_bits(b, st, 4)
      else
        sfc = mp_bits(b, st, 9)
      sfbt = srx * 23
      nl = 22 ## i64
      ns = 0 ## i64
      bt = 0 ## i64
      mixed = 0 ## i64
      rc0 = 0 ## i64
      rc1 = 0 ## i64
      tables = 0 ## i64
      sg0 = 0 ## i64
      sg1 = 0 ## i64
      sg2 = 0 ## i64
      if mp_bits(b, st, 1) == 1
        bt = mp_bits(b, st, 2)
        return -1 if bt == 0
        mixed = mp_bits(b, st, 1)
        rc0 = 7
        rc1 = 255
        if bt == 2
          if mixed == 0
            rc0 = 8
            sfbt = 184 + srx * 40
            nl = 0
            ns = 39
          else
            sfbt = 504 + srx * 40
            nl = 6
            nl = 8 if mpeg1
            ns = 30
        tables = mp_bits(b, st, 10) << 5
        sg0 = mp_bits(b, st, 3)
        sg1 = mp_bits(b, st, 3)
        sg2 = mp_bits(b, st, 3)
      else
        tables = mp_bits(b, st, 15)
        rc0 = mp_bits(b, st, 4)
        rc1 = mp_bits(b, st, 3)
      pre = 0 ## i64
      if mpeg1
        pre = mp_bits(b, st, 1)
      elsif sfc >= 500 && !(istereo && ch == 1)
        pre = 1
      ss = mp_bits(b, st, 1)
      c1 = mp_bits(b, st, 1)
      scfsi = 0 ## i64
      if mpeg1 && igr == 1 && bt != 2
        scfsi = (scfsi_all >> (4 * (nch - 1 - ch))) & 15
      gr[g] = sfbt
      gr[g + 1] = p23
      gr[g + 2] = bv
      gr[g + 3] = sfc
      gr[g + 4] = gg
      gr[g + 5] = bt
      gr[g + 6] = mixed
      gr[g + 7] = nl
      gr[g + 8] = ns
      gr[g + 9] = tables >> 10
      gr[g + 10] = (tables >> 5) & 31
      gr[g + 11] = tables & 31
      gr[g + 12] = rc0
      gr[g + 13] = rc1
      gr[g + 14] = 255
      gr[g + 15] = sg0
      gr[g + 16] = sg1
      gr[g + 17] = sg2
      gr[g + 18] = pre
      gr[g + 19] = ss
      gr[g + 20] = c1
      gr[g + 21] = scfsi
      ch += 1
    igr += 1
  return -1 if part_sum + st[0] > st[1] + mdb * 8
  mdb

# ---- Layer III scalefactors -> scf[i] (gain per sfb entry) ----

-> mp_scalefactors(b, st, gr, g, ch, h1, h3, ist, io, scf, iscf, part_t, scfc, modt, preamp, p2q) (u8[] i64[] i64[] i64 i64 i64 i64 i64[] i64 f64[] i64[] i64[] i64[] i64[] i64[] f64[]) i64
  nl = gr[g + 7]
  ns = gr[g + 8]
  pidx = 0 ## i64
  pidx += 1 if ns != 0
  pidx += 1 if nl == 0
  part = pidx * 28
  shift = gr[g + 19] + 1
  scfsi = gr[g + 21]
  sz0 = 0 ## i64
  sz1 = 0 ## i64
  sz2 = 0 ## i64
  sz3 = 0 ## i64
  if (h1 & 8) != 0
    pt = scfc[gr[g + 3]]
    sz0 = pt >> 2
    sz1 = sz0
    sz2 = pt & 3
    sz3 = sz2
  else
    ist_on = 0 ## i64
    ist_on = 1 if (h3 & 208) == 80 && ch != 0
    sfc = gr[g + 3] >> ist_on
    k = ist_on * 12
    while sfc >= 0
      modprod = 1 ## i64
      i = 3 ## i64
      while i >= 0
        v = (sfc / modprod) % modt[k + i]
        sz3 = v if i == 3
        sz2 = v if i == 2
        sz1 = v if i == 1
        sz0 = v if i == 0
        modprod = modprod * modt[k + i]
        i -= 1
      sfc -= modprod
      k += 4
    part += k
    scfsi = -16
  # read the scalefactors
  si = 0 ## i64
  i = 0 ## i64
  while i < 4 && part_t[part + i] != 0
    cnt = part_t[part + i]
    if (scfsi & 8) != 0
      k = 0 ## i64
      while k < cnt
        iscf[si + k] = ist[io + si + k]
        k += 1
    else
      bits = sz0
      bits = sz1 if i == 1
      bits = sz2 if i == 2
      bits = sz3 if i == 3
      if bits == 0
        k = 0 ## i64
        while k < cnt
          iscf[si + k] = 0
          ist[io + si + k] = 0
          k += 1
      else
        k = 0 ## i64
        while k < cnt
          s = mp_bits(b, st, bits)
          ist[io + si + k] = s
          iscf[si + k] = s
          k += 1
    si += cnt
    scfsi = scfsi * 2
    i += 1
  iscf[si] = 0
  iscf[si + 1] = 0
  iscf[si + 2] = 0
  if ns != 0
    sh = 3 - shift
    i = 0
    while i < ns
      iscf[nl + i] = iscf[nl + i] + (gr[g + 15] << sh)
      iscf[nl + i + 1] = iscf[nl + i + 1] + (gr[g + 16] << sh)
      iscf[nl + i + 2] = iscf[nl + i + 2] + (gr[g + 17] << sh)
      i += 3
  elsif gr[g + 18] != 0
    i = 0
    while i < 10
      iscf[11 + i] = iscf[11 + i] + preamp[i]
      i += 1
  gain_exp = gr[g + 4] - 4 - 210
  gain_exp -= 2 if (h3 & 224) == 96
  # gain = 2^11 * 2^(-(44 - gain_exp)/4) = 2^(gain_exp/4)
  ge = 44 - gain_exp
  gain = ~2048.0
  if ge > 0
    ge = 1023 if ge > 1023
    gain = gain * p2q[ge]
  else
    gain = gain / p2q[0 - ge]
  n = nl + ns
  i = 0
  while i < n
    e = iscf[i] << shift
    e = 1023 if e > 1023
    scf[i] = gain * p2q[e]
    i += 1
  0

# ---- Layer III Huffman decoding + dequantisation into dst[d0 .. d0+576) ----

-> mp_byte(b, cap, p) (u8[] i64 i64) i64
  return b[p] if p < cap
  0

-> mp_huffman(dst, d0, b, cap, st, gr, g, scf, limit, tabs, t32, t33, tidx, lbt, sfbt, p43) (f64[] i64 u8[] i64 i64[] i64[] i64 f64[] i64 i64[] i64[] i64[] i64[] i64[] i64[] f64[]) i64
  m32 = 4294967295
  sgn = 2147483648
  one = ~0.0
  ireg = 0 ## i64
  bvc = gr[g + 2]
  sfb = gr[g]
  sc = 0 ## i64
  pos = st[0]
  ptr = pos >> 3
  cache = (((mp_byte(b, cap, ptr) << 24) | (mp_byte(b, cap, ptr + 1) << 16) | (mp_byte(b, cap, ptr + 2) << 8) | mp_byte(b, cap, ptr + 3)) << (pos & 7)) & m32
  sh = (pos & 7) - 8
  ptr += 4
  d = d0
  while bvc > 0 && ireg < 3
    tn = gr[g + 9 + ireg]
    sfbcnt = gr[g + 12 + ireg]
    ireg += 1
    cb = tidx[tn]
    linb = lbt[tn]
    going = true
    while going
      np = sfbt[sfb] >> 1
      sfb += 1
      if np == 0
        bvc = 0
        going = false
      else
        pairs = bvc
        pairs = np if np < pairs
        one = scf[sc]
        sc += 1
        while pairs > 0
          w = 5 ## i64
          leaf = tabs[cb + (cache >> (32 - w))]
          while leaf < 0
            cache = (cache << w) & m32
            sh += w
            w = leaf & 7
            leaf = tabs[cb + (cache >> (32 - w)) - (leaf >> 3)]
          fl = leaf >> 8
          cache = (cache << fl) & m32
          sh += fl
          j = 0 ## i64
          while j < 2
            lsb = leaf & 15
            if lsb == 15 && linb > 0
              lsb += cache >> (32 - linb)
              cache = (cache << linb) & m32
              sh += linb
              while sh >= 0
                cache = cache | (mp_byte(b, cap, ptr) << sh)
                ptr += 1
                sh -= 8
            v = p43[lsb] * one
            v = ~0.0 - v if cache >= sgn
            dst[d] = v
            if lsb != 0
              cache = (cache << 1) & m32
              sh += 1
            d += 1
            leaf = leaf >> 4
            j += 1
          while sh >= 0
            cache = cache | (mp_byte(b, cap, ptr) << sh)
            ptr += 1
            sh -= 8
          pairs -= 1
        bvc -= np
        sfbcnt -= 1
        going = bvc > 0 && sfbcnt >= 0
  # count1 region
  np = 1 - bvc
  going = true
  while going
    leaf = 0 ## i64
    if gr[g + 20] != 0
      leaf = t33[cache >> 28]
    else
      leaf = t32[cache >> 28]
      if (leaf & 8) == 0
        leaf = t32[(leaf >> 3) + (((cache << 4) & m32) >> (32 - (leaf & 3)))]
    fl = leaf & 7
    cache = (cache << fl) & m32
    sh += fl
    if ptr * 8 - 24 + sh > limit
      going = false
    else
      np -= 1
      if np == 0
        np = sfbt[sfb] >> 1
        sfb += 1
        if np == 0
          going = false
        else
          one = scf[sc]
          sc += 1
      if going
        if (leaf & 128) != 0
          if cache >= sgn
            dst[d] = ~0.0 - one
          else
            dst[d] = one
          cache = (cache << 1) & m32
          sh += 1
        if (leaf & 64) != 0
          if cache >= sgn
            dst[d + 1] = ~0.0 - one
          else
            dst[d + 1] = one
          cache = (cache << 1) & m32
          sh += 1
        np -= 1
        if np == 0
          np = sfbt[sfb] >> 1
          sfb += 1
          if np == 0
            going = false
          else
            one = scf[sc]
            sc += 1
        if going
          if (leaf & 32) != 0
            if cache >= sgn
              dst[d + 2] = ~0.0 - one
            else
              dst[d + 2] = one
            cache = (cache << 1) & m32
            sh += 1
          if (leaf & 16) != 0
            if cache >= sgn
              dst[d + 3] = ~0.0 - one
            else
              dst[d + 3] = one
            cache = (cache << 1) & m32
            sh += 1
          while sh >= 0
            cache = cache | (mp_byte(b, cap, ptr) << sh)
            ptr += 1
            sh -= 8
          d += 4
          going = false if d >= d0 + 576
  st[0] = limit
  0

# ---- stereo ----

-> mp_midside(g, o, n) (f64[] i64 i64) i64
  i = 0 ## i64
  while i < n
    a = g[o + i]
    c = g[o + 576 + i]
    g[o + i] = a + c
    g[o + 576 + i] = a - c
    i += 1
  0

# Intensity stereo (with mid/side on the other bands when enabled) the way
# ffmpeg's compute_stereo does it, which is what the output is checked
# against: bands are scanned from the top; per short window, IS applies down
# to the highest band where the right channel is non-zero; the IS position
# is the right channel's raw scalefactor (>= 7 MPEG-1 / >= 16 MPEG-2: no
# IS); the last long band uses band 20's, the last short band band 11's.
-> mp_is_band(g, st, len, ipos, mpeg1, ish, cst, p2q) (f64[] i64 i64 i64 bool i64 f64[] f64[]) i64
  kl = ~1.0
  kr = ~1.0
  if mpeg1
    kl = cst[100 + 2 * ipos]
    kr = cst[101 + 2 * ipos]
  else
    kr = p2q[((ipos + 1) >> 1) << ish]
    if (ipos & 1) != 0
      kl = kr
      kr = ~1.0
  k = 0 ## i64
  while k < len
    v = g[st + k]
    g[st + k] = v * kl
    g[576 + st + k] = v * kr
    k += 1
  0

-> mp_nonzero(g, st, len) (f64[] i64 i64) bool
  k = 0 ## i64
  while k < len
    return true if g[576 + st + k] != ~0.0
    k += 1
  false

-> mp_intensity(g, ist, io, gr, g0, g1, h1, h3, sfbt, cst, p2q, pos) (f64[] i64[] i64 i64[] i64 i64 i64 i64 i64[] f64[] f64[] i64[]) i64
  nl = gr[g1 + 7]
  ns = gr[g1 + 8]
  sfb = gr[g1]
  mpeg1 = (h1 & 8) != 0
  ms = (h3 & 224) == 96
  sfmax = 16 ## i64
  sfmax = 7 if mpeg1
  ish = gr[g1 + 3] & 1
  # IS bands carry no 1/sqrt(2) (it is folded into the MS gain)
  msf = ~1.0
  msf = cst[124] if ms
  n = nl + ns
  acc = 0 ## i64
  e = 0 ## i64
  while e < n
    pos[e] = acc
    acc += sfbt[sfb + e]
    e += 1
  nz0 = false
  nz1 = false
  nz2 = false
  nsb = ns / 3
  b = nsb - 1
  while b >= 0
    sb = b
    sb = b - 1 if b == nsb - 1 && b > 0
    l = 2 ## i64
    while l >= 0
      e = nl + 3 * b + l
      len = sfbt[sfb + e]
      st0 = pos[e]
      nz = nz0
      nz = nz1 if l == 1
      nz = nz2 if l == 2
      done = false
      if !nz
        if mp_nonzero(g, st0, len)
          nz0 = true if l == 0
          nz1 = true if l == 1
          nz2 = true if l == 2
        else
          sf = ist[io + nl + 3 * sb + l]
          if sf < sfmax
            mp_is_band(g, st0, len, sf, mpeg1, ish, cst, p2q)
            k = 0 ## i64
            while k < len
              g[st0 + k] = g[st0 + k] * msf
              g[576 + st0 + k] = g[576 + st0 + k] * msf
              k += 1
            done = true
      mp_midside(g, st0, len) if !done && ms
      l -= 1
    b -= 1
  nzl = nz0 || nz1 || nz2
  e = nl - 1
  while e >= 0
    len = sfbt[sfb + e]
    st0 = pos[e]
    done = false
    if !nzl
      if mp_nonzero(g, st0, len)
        nzl = true
      else
        kk = e
        kk = 20 if e == 21
        sf = ist[io + kk]
        if sf < sfmax
          mp_is_band(g, st0, len, sf, mpeg1, ish, cst, p2q)
          k = 0 ## i64
          while k < len
            g[st0 + k] = g[st0 + k] * msf
            g[576 + st0 + k] = g[576 + st0 + k] * msf
            k += 1
          done = true
    mp_midside(g, st0, len) if !done && ms
    e -= 1
  0

# ---- reorder / antialias / IMDCT ----

-> mp_reorder(g, o, scratch, sfbt, sfb) (f64[] i64 f64[] i64[] i64) i64
  src = o
  d = 0 ## i64
  p = sfb
  while sfbt[p] != 0
    len = sfbt[p]
    i = 0 ## i64
    while i < len
      scratch[d] = g[src + i]
      scratch[d + 1] = g[src + len + i]
      scratch[d + 2] = g[src + 2 * len + i]
      d += 3
      i += 1
    src += 3 * len
    p += 3
  i = 0
  while i < d
    g[o + i] = scratch[i]
    i += 1
  0

-> mp_antialias(g, o, nb, c) (f64[] i64 i64 f64[]) i64
  b = o
  n = nb
  while n > 0
    i = 0 ## i64
    while i < 8
      u = g[b + 18 + i]
      dd = g[b + 17 - i]
      g[b + 18 + i] = u * c[i] - dd * c[8 + i]
      g[b + 17 - i] = u * c[8 + i] + dd * c[i]
      i += 1
    b += 18
    n -= 1
  0

-> mp_dct3_9(y, c) (f64[] f64[]) i64
  s0 = y[0]
  s2 = y[2]
  s4 = y[4]
  s6 = y[6]
  s8 = y[8]
  t0 = s0 + s6 * ~0.5
  s0 = s0 - s6
  t4 = (s4 + s2) * c[114]
  t2 = (s8 + s2) * c[115]
  s6 = (s4 - s8) * c[116]
  s4 = s4 + s8 - s2
  s2 = s0 - s4 * ~0.5
  y[4] = s4 + s0
  s8 = t0 - t2 + s6
  s0 = t0 - t4 + t2
  s4 = t0 + t4 - s6
  s1 = y[1]
  s3 = y[3]
  s5 = y[5]
  s7 = y[7]
  s3 = s3 * c[117]
  t0 = (s5 + s1) * c[118]
  t4 = (s5 - s7) * c[119]
  t2 = (s1 + s7) * c[120]
  s1 = (s1 - s5 - s7) * c[117]
  s5 = t0 - s3 - t2
  s7 = t4 - s3 - t0
  s3 = t4 + s3 - t2
  y[0] = s4 - s7
  y[1] = s2 + s1
  y[2] = s0 - s3
  y[3] = s8 + s5
  y[5] = s8 - s5
  y[6] = s0 + s3
  y[7] = s2 - s1
  y[8] = s4 + s7
  0

# window at c[wo ..]: 18 values (9 cos, 9 sin)
-> mp_imdct36(g, gofs, ov, oo, c, wo, nb, co, si) (f64[] i64 f64[] i64 f64[] i64 i64 f64[] f64[]) i64
  gb = gofs
  ob = oo
  j = 0 ## i64
  while j < nb
    co[0] = ~0.0 - g[gb]
    si[0] = g[gb + 17]
    i = 0 ## i64
    while i < 4
      si[8 - 2 * i] = g[gb + 4 * i + 1] - g[gb + 4 * i + 2]
      co[1 + 2 * i] = g[gb + 4 * i + 1] + g[gb + 4 * i + 2]
      si[7 - 2 * i] = g[gb + 4 * i + 4] - g[gb + 4 * i + 3]
      co[2 + 2 * i] = ~0.0 - (g[gb + 4 * i + 3] + g[gb + 4 * i + 4])
      i += 1
    mp_dct3_9(co, c)
    mp_dct3_9(si, c)
    si[1] = ~0.0 - si[1]
    si[3] = ~0.0 - si[3]
    si[5] = ~0.0 - si[5]
    si[7] = ~0.0 - si[7]
    i = 0
    while i < 9
      ovl = ov[ob + i]
      sum = co[i] * c[25 + i] + si[i] * c[16 + i]
      ov[ob + i] = co[i] * c[16 + i] - si[i] * c[25 + i]
      g[gb + i] = ovl * c[wo + i] - sum * c[wo + 9 + i]
      g[gb + 17 - i] = ovl * c[wo + 9 + i] + sum * c[wo + i]
      i += 1
    gb += 18
    ob += 9
    j += 1
  0

-> mp_imdct12(x, xo, dst, dso, ov, ovo, c) (f64[] i64 f64[] i64 f64[] i64 f64[]) i64
  # co = idct3(-x0, x6 + x3, x12 + x9); si = idct3(x15, x12 - x9, x6 - x3)
  a0 = ~0.0 - x[xo]
  a1 = x[xo + 6] + x[xo + 3]
  a2 = x[xo + 12] + x[xo + 9]
  m1 = a1 * c[117]
  q1 = a0 - a2 * ~0.5
  co1 = a0 + a2
  co0 = q1 + m1
  co2 = q1 - m1
  b0 = x[xo + 15]
  b1 = x[xo + 12] - x[xo + 9]
  b2 = x[xo + 6] - x[xo + 3]
  m1 = b1 * c[117]
  q1 = b0 - b2 * ~0.5
  si1 = ~0.0 - (b0 + b2)
  si0 = q1 + m1
  si2 = q1 - m1
  i = 0 ## i64
  while i < 3
    cv = co0
    sv = si0
    if i == 1
      cv = co1
      sv = si1
    elsif i == 2
      cv = co2
      sv = si2
    ovl = ov[ovo + i]
    sum = cv * c[37 + i] + sv * c[34 + i]
    ov[ovo + i] = cv * c[34 + i] - sv * c[37 + i]
    dst[dso + i] = ovl * c[36 - i] - sum * c[39 - i]
    dst[dso + 5 - i] = ovl * c[39 - i] + sum * c[36 - i]
    i += 1
  0

-> mp_imdct_short(g, gofs, ov, oo, nb, c, tmp) (f64[] i64 f64[] i64 i64 f64[] f64[]) i64
  gb = gofs
  ob = oo
  n = nb
  while n > 0
    i = 0 ## i64
    while i < 18
      tmp[i] = g[gb + i]
      i += 1
    i = 0
    while i < 6
      g[gb + i] = ov[ob + i]
      i += 1
    mp_imdct12(tmp, 0, g, gb + 6, ov, ob + 6, c)
    mp_imdct12(tmp, 1, g, gb + 12, ov, ob + 6, c)
    mp_imdct12(tmp, 2, ov, ob, ov, ob + 6, c)
    gb += 18
    ob += 9
    n -= 1
  0

-> mp_change_sign(g, o) (f64[] i64) i64
  b = 0 ## i64
  p = o + 18
  while b < 32
    i = 1 ## i64
    while i < 18
      g[p + i] = ~0.0 - g[p + i]
      i += 2
    b += 2
    p += 36
  0

-> mp_imdct_gr(g, gofs, ov, oo, bt, nlb, c, co, si, tmp) (f64[] i64 f64[] i64 i64 i64 f64[] f64[] f64[] f64[]) i64
  gb = gofs
  ob = oo
  if nlb > 0
    mp_imdct36(g, gb, ov, ob, c, 40, nlb, co, si)
    gb += 18 * nlb
    ob += 9 * nlb
  if bt == 2
    mp_imdct_short(g, gb, ov, ob, 32 - nlb, c, tmp)
  elsif bt == 3
    mp_imdct36(g, gb, ov, ob, c, 58, 32 - nlb, co, si)
  else
    mp_imdct36(g, gb, ov, ob, c, 40, 32 - nlb, co, si)
  0

# ---- polyphase synthesis ----

-> mp_dct2(g, gofs, n, c, ds, t) (f64[] i64 i64 f64[] f64[] f64[]) i64
  k = 0 ## i64
  while k < n
    y = gofs + k
    i = 0 ## i64
    while i < 8
      x0 = g[y + i * 18]
      x1 = g[y + (15 - i) * 18]
      x2 = g[y + (16 + i) * 18]
      x3 = g[y + (31 - i) * 18]
      t0 = x0 + x3
      t1 = x1 + x2
      t2 = (x1 - x2) * c[76 + 3 * i]
      t3 = (x0 - x3) * c[77 + 3 * i]
      t[i] = t0 + t1
      t[8 + i] = (t0 - t1) * c[78 + 3 * i]
      t[16 + i] = t3 + t2
      t[24 + i] = (t3 - t2) * c[78 + 3 * i]
      i += 1
    i = 0
    while i < 4
      xb = i * 8
      x0 = t[xb]
      x1 = t[xb + 1]
      x2 = t[xb + 2]
      x3 = t[xb + 3]
      x4 = t[xb + 4]
      x5 = t[xb + 5]
      x6 = t[xb + 6]
      x7 = t[xb + 7]
      xt = x0 - x7
      x0 = x0 + x7
      x7 = x1 - x6
      x1 = x1 + x6
      x6 = x2 - x5
      x2 = x2 + x5
      x5 = x3 - x4
      x3 = x3 + x4
      x4 = x0 - x3
      x0 = x0 + x3
      x3 = x1 - x2
      x1 = x1 + x2
      t[xb] = x0 + x1
      t[xb + 4] = (x0 - x1) * c[121]
      x5 = x5 + x6
      x6 = (x6 + x7) * c[121]
      x7 = x7 + xt
      x3 = (x3 + x4) * c[121]
      x5 = x5 - x7 * c[122]
      x7 = x7 + x5 * c[123]
      x5 = x5 - x7 * c[122]
      x0 = xt - x6
      xt = xt + x6
      t[xb + 1] = (xt + x7) * ds[1]
      t[xb + 2] = (x4 + x3) * ds[2]
      t[xb + 3] = (x0 - x5) * ds[3]
      t[xb + 5] = (x0 + x5) * ds[5]
      t[xb + 6] = (x4 - x3) * ds[6]
      t[xb + 7] = (xt - x7) * ds[7]
      i += 1
    yy = y
    i = 0
    while i < 7
      g[yy] = t[i]
      g[yy + 18] = t[16 + i] + t[24 + i] + t[24 + i + 1]
      g[yy + 36] = t[8 + i] + t[8 + i + 1]
      g[yy + 54] = t[16 + i + 1] + t[24 + i] + t[24 + i + 1]
      yy += 72
      i += 1
    g[yy] = t[7]
    g[yy + 18] = t[23] + t[31]
    g[yy + 36] = t[15]
    g[yy + 54] = t[31]
    k += 1
  0

-> mp_synth_pair(out, d, nch, z, zo) (f32[] i64 i64 f64[] i64) i64
  sc = ~1.0 / ~32768.0
  a = (z[zo + 896] - z[zo]) * ~29.0
  a += (z[zo + 64] + z[zo + 832]) * ~213.0
  a += (z[zo + 768] - z[zo + 128]) * ~459.0
  a += (z[zo + 192] + z[zo + 704]) * ~2037.0
  a += (z[zo + 640] - z[zo + 256]) * ~5153.0
  a += (z[zo + 320] + z[zo + 576]) * ~6574.0
  a += (z[zo + 512] - z[zo + 384]) * ~37489.0
  a += z[zo + 448] * ~75038.0
  out[d] = (a * sc) ## f32
  z2 = zo + 2
  a = z[z2 + 896] * ~104.0
  a += z[z2 + 768] * ~1567.0
  a += z[z2 + 640] * ~9727.0
  a += z[z2 + 512] * ~64019.0
  a += z[z2 + 384] * ~-9975.0
  a += z[z2 + 256] * ~-45.0
  a += z[z2 + 128] * ~146.0
  a += z[z2] * ~-5.0
  out[d + 16 * nch] = (a * sc) ## f32
  0

-> mp_synth(g, xl, xr, out, dl, dr, nch, lins, lo, win) (f64[] i64 i64 f32[] i64 i64 i64 f64[] i64 f64[]) i64
  sc = ~1.0 / ~32768.0
  zl = lo + 960
  lins[zl + 60] = g[xl + 288]
  lins[zl + 61] = g[xr + 288]
  lins[zl + 62] = g[xl]
  lins[zl + 63] = g[xr]
  lins[zl + 124] = g[xl + 289]
  lins[zl + 125] = g[xr + 289]
  lins[zl + 126] = g[xl + 1]
  lins[zl + 127] = g[xr + 1]
  mp_synth_pair(out, dr, nch, lins, lo + 61)
  mp_synth_pair(out, dr + 32 * nch, nch, lins, lo + 125)
  mp_synth_pair(out, dl, nch, lins, lo + 60)
  mp_synth_pair(out, dl + 32 * nch, nch, lins, lo + 124)
  w = 0 ## i64
  i = 14 ## i64
  while i >= 0
    lins[zl + 4 * i] = g[xl + 18 * (31 - i)]
    lins[zl + 4 * i + 1] = g[xr + 18 * (31 - i)]
    lins[zl + 4 * i + 2] = g[xl + 1 + 18 * (31 - i)]
    lins[zl + 4 * i + 3] = g[xr + 1 + 18 * (31 - i)]
    lins[zl + 4 * (i + 16)] = g[xl + 1 + 18 * (1 + i)]
    lins[zl + 4 * (i + 16) + 1] = g[xr + 1 + 18 * (1 + i)]
    lins[zl + 4 * (i - 16) + 2] = g[xl + 18 * (1 + i)]
    lins[zl + 4 * (i - 16) + 3] = g[xr + 18 * (1 + i)]
    a0 = ~0.0
    a1 = ~0.0
    a2 = ~0.0
    a3 = ~0.0
    b0 = ~0.0
    b1 = ~0.0
    b2 = ~0.0
    b3 = ~0.0
    k = 0 ## i64
    while k < 8
      w0 = win[w]
      w1 = win[w + 1]
      w += 2
      vz = zl + 4 * i - k * 64
      vy = zl + 4 * i - (15 - k) * 64
      z0 = lins[vz]
      z1 = lins[vz + 1]
      z2 = lins[vz + 2]
      z3 = lins[vz + 3]
      y0 = lins[vy]
      y1 = lins[vy + 1]
      y2 = lins[vy + 2]
      y3 = lins[vy + 3]
      b0 += z0 * w1 + y0 * w0
      b1 += z1 * w1 + y1 * w0
      b2 += z2 * w1 + y2 * w0
      b3 += z3 * w1 + y3 * w0
      if (k & 1) == 1
        a0 += y0 * w1 - z0 * w0
        a1 += y1 * w1 - z1 * w0
        a2 += y2 * w1 - z2 * w0
        a3 += y3 * w1 - z3 * w0
      else
        a0 += z0 * w0 - y0 * w1
        a1 += z1 * w0 - y1 * w1
        a2 += z2 * w0 - y2 * w1
        a3 += z3 * w0 - y3 * w1
      k += 1
    out[dr + (15 - i) * nch] = (a1 * sc) ## f32
    out[dr + (17 + i) * nch] = (b1 * sc) ## f32
    out[dl + (15 - i) * nch] = (a0 * sc) ## f32
    out[dl + (17 + i) * nch] = (b0 * sc) ## f32
    out[dr + (47 - i) * nch] = (a3 * sc) ## f32
    out[dr + (49 + i) * nch] = (b3 * sc) ## f32
    out[dl + (47 - i) * nch] = (a2 * sc) ## f32
    out[dl + (49 + i) * nch] = (b2 * sc) ## f32
    i -= 1
  0

-> mp_synth_granule(qmf, qo, g, nb, nch, out, oo, lins, win, c, ds, t) (f64[] i64 f64[] i64 i64 f32[] i64 f64[] f64[] f64[] f64[] f64[]) i64
  ch = 0 ## i64
  while ch < nch
    mp_dct2(g, ch * 576, nb, c, ds, t)
    ch += 1
  i = 0 ## i64
  while i < 960
    lins[i] = qmf[qo + i]
    i += 1
  e = 960 + 64 * nb
  while i < e
    lins[i] = ~0.0
    i += 1
  i = 0
  while i < nb
    dl = oo + 32 * nch * i
    mp_synth(g, i, i + 576 * (nch - 1), out, dl, dl + nch - 1, nch, lins, i * 64, win)
    i += 2
  # mono keeps the right channel's history untouched (as minimp3 / the ISO
  # reference: matters when a stream switches from mono to stereo)
  step = 1 ## i64
  step = 2 if nch == 1
  i = 0
  while i < 960
    qmf[qo + i] = lins[nb * 64 + i]
    i += step
  0

# ---- Layer I / II ----
# sci: 0 total bands, 1 stereo bands, 2.. bitalloc[64], 66.. scfcod[64]; scf f64[192]

-> mp_l12_scale_info(b, st, h1, h2, h3, sci, scf, code, alloc, deq, hr) (u8[] i64[] i64 i64 i64 i64[] f64[] i64[] i64[] f64[] i64[]) i64
  mode = (h3 >> 6) & 3
  sb = 32 ## i64
  if mode == 3
    sb = 0
  elsif mode == 1
    sb = ((h3 >> 4) & 3) * 4 + 4
  layer1 = (h1 & 6) == 6
  aoff = 0 ## i64
  nb = 32 ## i64
  if layer1
    aoff = 0
    nb = 32
  elsif (h1 & 8) == 0
    aoff = 3
    nb = 30
  else
    sri = (h2 >> 2) & 3
    kbps = mp_hdr_kbps(h1, h2, hr)
    kbps = kbps >> 1 if mode != 3
    kbps = 192 if kbps == 0
    aoff = 12
    nb = 27
    if kbps < 56
      aoff = 24
      nb = 8
      nb = 12 if sri == 2
    elsif kbps >= 96 && sri != 1
      nb = 30
  sb = nb if sb > nb
  sci[0] = nb
  sci[1] = sb
  k = 0 ## i64
  babits = 0 ## i64
  coff = 0 ## i64
  i = 0 ## i64
  while i < nb
    if i == k
      k += alloc[aoff + 2]
      babits = alloc[aoff + 1]
      coff = alloc[aoff]
      aoff += 3
    ba = code[coff + mp_bits(b, st, babits)]
    sci[2 + 2 * i] = ba
    if i < sb
      ba = code[coff + mp_bits(b, st, babits)]
    if sb != 0
      sci[3 + 2 * i] = ba
    else
      sci[3 + 2 * i] = 0
    i += 1
  i = 0
  while i < 2 * nb
    if sci[2 + i] != 0
      if layer1
        sci[66 + i] = 2
      else
        sci[66 + i] = mp_bits(b, st, 2)
    else
      sci[66 + i] = 6
    i += 1
  i = 0
  while i < 2 * nb
    s = ~0.0
    ba = sci[2 + i]
    mask = 0 ## i64
    mask = 4 + ((19 >> sci[66 + i]) & 3) if ba != 0
    m = 4 ## i64
    j = 0 ## i64
    while m > 0
      if (mask & m) != 0
        bb = mp_bits(b, st, 6)
        s = deq[ba * 3 - 6 + bb % 3] * ((1 << 21) >> (bb / 3))
      scf[i * 3 + j] = s
      j += 1
      m = m >> 1
    i += 1
  i = sb
  while i < nb
    sci[3 + 2 * i] = 0
    i += 1
  0

-> mp_l12_dequant(g, gofs, b, st, sci, gs) (f64[] i64 u8[] i64[] i64[] i64) i64
  nb = sci[0]
  j = 0 ## i64
  while j < 4
    i = 0 ## i64
    while i < 2 * nb
      ba = sci[2 + i]
      dst = gofs + gs * j + (i >> 1) * 18 + (i & 1) * 576
      if ba != 0
        if ba < 17
          half = (1 << (ba - 1)) - 1
          k = 0 ## i64
          while k < gs
            g[dst + k] = (mp_bits(b, st, ba) - half) * ~1.0
            k += 1
        else
          md = (2 << (ba - 17)) + 1
          code = mp_bits(b, st, md + 2 - (md >> 3))
          k = 0 ## i64
          while k < gs
            g[dst + k] = ((code % md) - (md / 2)) * ~1.0
            code = code / md
            k += 1
      i += 1
    j += 1
  gs * 4

-> mp_l12_apply_scf(sci, scf, so, g) (i64[] f64[] i64 f64[]) i64
  nb = sci[0]
  sb = sci[1]
  n = (nb - sb) * 18
  i = 0 ## i64
  while i < n
    g[576 + sb * 18 + i] = g[sb * 18 + i]
    i += 1
  i = 0
  while i < nb
    k = 0 ## i64
    l = scf[so + i * 6]
    r = scf[so + i * 6 + 3]
    while k < 12
      g[i * 18 + k] = g[i * 18 + k] * l
      g[i * 18 + k + 576] = g[i * 18 + k + 576] * r
      k += 1
    i += 1
  0

-> mp_zero(a, n) (f64[] i64) i64
  i = 0 ## i64
  while i < n
    a[i] = ~0.0
    i += 1
  0

-> mp_copy(src, so, dst, d0, n) (u8[] i64 u8[] i64 i64) i64
  i = 0 ## i64
  while i < n
    dst[d0 + i] = src[so + i]
    i += 1
  n

-> mp_bytes(d)
  if d.is_a?(String)
    return ccall("w_string_bytes_view", d) ## u8[]
  d

-> mp_err(msg)
  raise MediaError.new("mp3: " + msg)

+ Mp3Dec
  ro :rate, :channels, :bad_frames

  -> new(cfg)
    @rate = cfg.sample_rate
    @channels = cfg.channels
    @fbuf = u8[4096]
    @md = u8[511 + 4096 + 64]
    @reserv = u8[512]
    @reserv_n = 0
    @overlap = f64[2 * 288]
    @qmf = f64[960]
    @gb = f64[2 * 576]
    @scf = f64[40]
    @iscf = i64[48]
    @lins = f64[33 * 64]
    @ist = i64[2 * 39]
    @pos = i64[48]
    @gr = i64[4 * 24]
    @st = i64[2]
    @co = f64[9]
    @si = f64[9]
    @tmp = f64[32]
    @sci = i64[132]
    @scf12 = f64[192]
    @bad_frames = 0

  -> reset
    @reserv_n = 0
    mp_zero(@overlap, 576)
    mp_zero(@qmf, 960)

  -> flush
    nil

  -> decode(sample)
    b = mp_bytes(sample.data)
    n = b.size
    mp_err("short frame") if n < 4
    h1 = b[1]
    h2 = b[2]
    h3 = b[3]
    mp_err("bad frame header") if !mp_hv(b, 0)
    fsize = mp_hdr_bytes(h1, h2, MP_HALFRATE)
    fsize = n if fsize == 0
    rate = mp_hdr_rate(h1, h2)
    nch = 2
    nch = 1 if (h3 & 192) == 192
    spf = mp_hdr_spf(h1)
    out = f32[spf * nch]
    if @fbuf.size < fsize + 16
      @fbuf = u8[fsize + 16]
      @md = u8[511 + fsize + 64]
    fb = @fbuf
    m = n
    m = fsize if m > fsize
    mp_copy(b, 0, fb, 0, m)
    k = m
    while k < fsize + 16
      fb[k] = 0
      k += 1
    st = @st
    st[0] = 32
    st[1] = fsize * 8
    st[0] = 48 if (h1 & 1) == 0
    layer = 4 - ((h1 >> 1) & 3)
    ok = true
    if layer == 3
      ok = decode_l3(fb, h1, h2, h3, nch, out)
    else
      ok = decode_l12(fb, h1, h2, h3, nch, layer, out)
    if !ok
      @bad_frames += 1
      k = 0
      while k < spf * nch
        out[k] = (~0.0) ## f32
        k += 1
    @rate = rate
    @channels = nch
    AudioBlock.new(out, spf, nch, rate, sample.pts)

  -> decode_l3(fb, h1, h2, h3, nch, out)
    st = @st
    gr = @gr
    mdb = mp_side_info(fb, st, h1, h2, h3, gr)
    if mdb < 0 || st[0] > st[1]
      reset()
      return false
    # restore the reservoir: the last mdb bytes of earlier main data + this frame's
    md = @md
    fbytes = (st[1] - st[0]) >> 3
    have = mdb
    have = @reserv_n if @reserv_n < have
    mp_copy(@reserv, @reserv_n - have, md, 0, have) if have > 0
    mp_copy(fb, st[0] >> 3, md, have, fbytes)
    k = have + fbytes
    while k < have + fbytes + 64
      md[k] = 0
      k += 1
    mst = i64[2]
    mst[0] = 0
    mst[1] = (have + fbytes) * 8
    # Not enough reservoir (the first frames after a seek / cut): as ffmpeg,
    # granules whose data starts in the missing part decode as silence (their
    # IMDCT still runs, emptying the overlap), later ones from their offset.
    missing = (mdb - have) * 8
    cum = 0
    started = false
    ngr = 1
    ngr = 2 if (h1 & 8) != 0
    igr = 0
    while igr < ngr
      mp_zero(@gb, 1152)
      if cum < missing
        skip_granule(igr, h1, h2, nch)
        ch = 0
        while ch < nch
          cum += gr[(igr * nch + ch) * 24 + 1]
          ch += 1
      else
        if !started
          mst[0] = cum - missing
          started = true
        decode_granule(md, mst, igr, h1, h2, h3, nch)
      mp_synth_granule(@qmf, 0, @gb, 18, nch, out, igr * 576 * nch, @lins, MP_WIN, MP_C, MP_DSC, @tmp)
      igr += 1
    mst[0] = mst[1] if !started
    # save the reservoir
    pos = (mst[0] + 7) >> 3
    pos = 0 if missing > 0 && !started
    pos = mst[1] >> 3 if pos > (mst[1] >> 3)
    remains = (mst[1] >> 3) - pos
    if remains > 511
      pos += remains - 511
      remains = 511
    mp_copy(md, pos, @reserv, 0, remains) if remains > 0
    @reserv_n = remains
    true

  -> skip_granule(igr, h1, h2, nch)
    gr = @gr
    mysr = ((h2 >> 2) & 3) + (((h1 >> 3) & 1) + ((h1 >> 4) & 1)) * 3
    ch = 0
    while ch < nch
      g = (igr * nch + ch) * 24
      nlb = 0
      if gr[g + 6] != 0
        nlb = 2
        nlb = 4 if mysr == 2
      mp_imdct_gr(@gb, ch * 576, @overlap, ch * 288, gr[g + 5], nlb, MP_C, @co, @si, @tmp)
      mp_change_sign(@gb, ch * 576)
      ch += 1

  -> decode_granule(md, mst, igr, h1, h2, h3, nch)
    gr = @gr
    cap = md.size
    ch = 0
    while ch < nch
      g = (igr * nch + ch) * 24
      limit = mst[0] + gr[g + 1]
      mp_scalefactors(md, mst, gr, g, ch, h1, h3, @ist, ch * 39, @scf, @iscf, MP_SCF_PART, MP_SCFC_DECODE, MP_MOD, MP_PREAMP, MP_POW2Q)
      mp_huffman(@gb, ch * 576, md, cap, mst, gr, g, @scf, limit, MP_TABS, MP_TAB32, MP_TAB33, MP_TABINDEX, MP_LINBITS, MP_SFB, MP_POW43)
      ch += 1
    g0 = igr * nch * 24
    if nch == 2
      if (h3 & 208) == 80
        mp_intensity(@gb, @ist, 39, gr, g0, g0 + 24, h1, h3, MP_SFB, MP_C, MP_POW2Q, @pos)
      elsif (h3 & 224) == 96
        mp_midside(@gb, 0, 576)
    mysr = ((h2 >> 2) & 3) + (((h1 >> 3) & 1) + ((h1 >> 4) & 1)) * 3
    ch = 0
    while ch < nch
      g = g0 + ch * 24
      aa = 31
      nlb = 0
      if gr[g + 6] != 0
        nlb = 2
        nlb = 4 if mysr == 2
      if gr[g + 8] != 0
        aa = nlb - 1
        mp_reorder(@gb, ch * 576 + nlb * 18, @lins, MP_SFB, gr[g] + gr[g + 7])
      mp_antialias(@gb, ch * 576, aa, MP_C)
      mp_imdct_gr(@gb, ch * 576, @overlap, ch * 288, gr[g + 5], nlb, MP_C, @co, @si, @tmp)
      mp_change_sign(@gb, ch * 576)
      ch += 1

  -> decode_l12(fb, h1, h2, h3, nch, layer, out)
    st = @st
    sci = @sci
    mp_l12_scale_info(fb, st, h1, h2, h3, sci, @scf12, MP_BA_CODE, MP_ALLOC, MP_DEQ12, MP_HALFRATE)
    gb = @gb
    mp_zero(gb, 1152)
    i = 0
    igr = 0
    oo = 0
    gs = layer | 1
    while igr < 3
      i += mp_l12_dequant(gb, i, fb, st, sci, gs)
      if i == 12
        i = 0
        mp_l12_apply_scf(sci, @scf12, igr, gb)
        mp_synth_granule(@qmf, 0, gb, 12, nch, out, oo, @lins, MP_WIN, MP_C, MP_DSC, @tmp)
        mp_zero(gb, 1152)
        oo += 384 * nch
      # an overlong / truncated frame reads zeros past its end (as ffmpeg)
      igr += 1
    true

acodec_register("mp3 ", ->(cfg) Mp3Dec.new(cfg))

# ---- elementary stream parsing ----

# Do headers at a and c describe the same stream (version, layer, rate, free format)?
-> mp_hdr_compat(b, a, c) (u8[] i64 i64) bool
  mp_hv(b, c) && ((b[a + 1] ^ b[c + 1]) & 254) == 0 && ((b[a + 2] ^ b[c + 2]) & 12) == 0 && (((b[a + 2] & 240) == 0) == ((b[c + 2] & 240) == 0))

# frame size at p (free format: the distance to the next compatible header, searched), 0 if none
-> mp_frame_size_at(b, p, e, ff) (u8[] i64 i64 i64) i64
  fs = mp_hdr_bytes((b[p + 1] ## i64), (b[p + 2] ## i64), MP_HALFRATE)
  return fs if fs > 0
  if ff > 0
    pad = 0
    pad = 1 if (b[p + 2] & 2) != 0
    pad = 4 if pad == 1 && (b[p + 1] & 6) == 6
    return ff + pad
  k = 24
  while k < 2400 && p + k + 4 <= e
    if b[p + k] == 255 && mp_hdr_compat(b, p, p + k)
      return k
    k += 1
  0

# a frame at p that is followed by a compatible header (or the end)
-> mp_sync_ok(b, p, e, ff)
  return false if p + 4 > e
  return false if !mp_hv(b, p)
  fs = mp_frame_size_at(b, p, e, ff)
  return false if fs <= 0
  q = p + fs
  return true if q == e || (q < e && q + 4 > e)
  return false if q + 4 > e
  mp_hdr_compat(b, p, q)

-> mp_be32(b, p)
  (b[p] << 24) | (b[p + 1] << 16) | (b[p + 2] << 8) | b[p + 3]

# Xing / Info / VBRI in the first frame at p -> {frames:, delay:, padding:} or nil
-> mp_vbr_info(b, p, fs)
  h1 = b[p + 1]
  h3 = b[p + 3]
  mono = (h3 & 192) == 192
  off = 0
  if (h1 & 8) != 0
    off = 32
    off = 17 if mono
  else
    off = 17
    off = 9 if mono
  x = p + 4 + off
  r = nil
  if x + 8 <= p + fs
    tag = mp_be32(b, x)
    if tag == 1483304551 || tag == 1231971951
      flags = mp_be32(b, x + 4)
      q = x + 8
      frames = -1
      if (flags & 1) != 0
        frames = mp_be32(b, q)
        q += 4
      q += 4 if (flags & 2) != 0
      q += 100 if (flags & 4) != 0
      q += 4 if (flags & 8) != 0
      r = {frames: frames, delay: -1, padding: 0}
      if q + 24 <= p + fs
        # LAME-style extension: 9-byte encoder string, … delay/padding at +21
        if b[q] == 76 && (b[q + 1] == 65 || b[q + 1] == 97)
          d = q + 21
          r[:delay] = (b[d] << 4) | (b[d + 1] >> 4)
          r[:padding] = ((b[d + 1] & 15) << 8) | b[d + 2]
  v = p + 4 + 32
  if r == nil && v + 18 <= p + fs && mp_be32(b, v) == 1447186505
    r = {frames: mp_be32(b, v + 14), delay: -1, padding: 0}
  r

-> mp3_es_parse(bytes)
  b = mp_bytes(bytes)
  nb = b.size
  p = 0
  while p + 10 <= nb && b[p] == 73 && b[p + 1] == 68 && b[p + 2] == 51
    sz = ((b[p + 6] & 127) << 21) | ((b[p + 7] & 127) << 14) | ((b[p + 8] & 127) << 7) | (b[p + 9] & 127)
    foot = 0
    foot = 10 if (b[p + 5] & 16) != 0
    p += 10 + sz + foot
  e = nb
  # ID3v1 / APEv2 at the end
  if e - 128 >= p && b[e - 128] == 84 && b[e - 127] == 65 && b[e - 126] == 71
    e -= 128
  if e - 32 >= p && b[e - 32] == 65 && b[e - 31] == 80 && b[e - 30] == 69 && b[e - 29] == 84 && b[e - 28] == 65 && b[e - 27] == 71 && b[e - 26] == 69 && b[e - 25] == 88
    asz = b[e - 20] | (b[e - 19] << 8) | (b[e - 18] << 16) | (b[e - 17] << 24)
    hdr = 0
    hdr = 32 if (b[e - 9] & 128) != 0
    e2 = e - asz - hdr
    e = e2 if e2 >= p && asz > 0
  if e - 128 >= p && b[e - 128] == 84 && b[e - 127] == 65 && b[e - 126] == 71
    e -= 128
  # first frame
  ff = 0
  while p + 4 <= e && !mp_sync_ok(b, p, e, 0)
    p += 1
  mp_err("no MPEG audio frame") if p + 4 > e
  first = p
  if mp_hdr_bytes(b[p + 1], b[p + 2], MP_HALFRATE) == 0
    fs0 = mp_frame_size_at(b, p, e, 0)
    pad = 0
    pad = 1 if (b[p + 2] & 2) != 0
    ff = fs0 - pad
  h1 = b[p + 1]
  h2 = b[p + 2]
  rate = mp_hdr_rate(h1, h2)
  spf = mp_hdr_spf(h1)
  nch = 2
  nch = 1 if (b[p + 3] & 192) == 192
  cfg = CodecConfig.new("mp3 ", nil)
  cfg.sample_rate = rate
  cfg.channels = nch
  vbr = mp_vbr_info(b, p, mp_frame_size_at(b, p, e, ff))
  if vbr != nil
    p += mp_frame_size_at(b, p, e, ff)
  delay = 0
  trim = 0
  if vbr != nil && vbr[:delay] >= 0
    # as ffmpeg: skip the encoder delay plus the 529-sample decoder delay,
    # and keep frames * spf - delay - padding samples
    delay = vbr[:delay] + 529
    trim = vbr[:delay] + vbr[:padding]
  samples = []
  idx = 0
  fdur = spf / (rate * ~1.0)
  while p + 4 <= e
    ok = mp_hv(b, p) && mp_hdr_compat(b, first, p)
    fs = 0
    fs = mp_frame_size_at(b, p, e, ff) if ok
    if ok && fs > 0 && p + fs <= e && (p + fs + 4 > e || mp_hdr_compat(b, first, p + fs))
      d = u8[fs]
      mp_copy(b, p, d, 0, fs)
      t = (idx * spf - delay) / (rate * ~1.0)
      samples.push(MediaSample.new(d, t, t, fdur, true))
      idx += 1
      p += fs
    elsif ok && fs > 0 && p + fs > e && e - p >= 4
      # a truncated last frame: decode what is there
      d = u8[e - p]
      mp_copy(b, p, d, 0, e - p)
      t = (idx * spf - delay) / (rate * ~1.0)
      samples.push(MediaSample.new(d, t, t, fdur, true))
      idx += 1
      p = e
    else
      p += 1
      while p + 4 <= e && !(mp_hv(b, p) && mp_hdr_compat(b, first, p) && mp_sync_ok(b, p, e, ff))
        p += 1
  total = idx * spf
  if vbr != nil && vbr[:frames] > 0 && vbr[:delay] >= 0
    total = vbr[:frames] * spf
  total = total - trim
  total = 0 if total < 0 || idx == 0
  {cfg: cfg, samples: samples, duration: total / (rate * ~1.0)}

# Raw elementary-stream files (.mp3 / .aac ADTS / .flac) go through this parser.
es_parser_register(:mp3, ->(b) mp3_es_parse(b))
