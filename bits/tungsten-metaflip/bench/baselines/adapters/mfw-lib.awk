# Shared functions of the scheme converters (POSIX awk; bit vectors are arrays, so word width is unbounded).
# Use as:  awk -f mfw-lib.awk -f CONVERTER.awk ...   with  LC_ALL=C.
#
# MFW1 conventions (bench/README.md): bit i*m+j of u is A[i][j], bit j*p+k of v is B[j][k], bit i*p+k of w is C[i][k].
# Kauers-Moosbauer and Perminov store the third factor transposed: c[j][i] of a p x n matrix.

function fail(msg) {
  print "convert: " msg > "/dev/stderr"
  failed = 1
  exit 2
}

function hexval(c) { return index("0123456789abcdef", c) - 1 }

# bits_from_hex(hex, bit): bit[i] = 1 for every set bit i (bit 0 = least significant) of the hex word.
function bits_from_hex(hex, bit,    len, d, v, k) {
  delete bit
  len = length(hex)
  for (d = 0; d < len; d++) {
    v = hexval(substr(hex, len - d, 1))
    if (v < 0) fail("bad hexadecimal digit in '" hex "'")
    if (v % 2 == 1) bit[4 * d] = 1
    if (int(v / 2) % 2 == 1) bit[4 * d + 1] = 1
    if (int(v / 4) % 2 == 1) bit[4 * d + 2] = 1
    if (int(v / 8) % 2 == 1) bit[4 * d + 3] = 1
  }
}

# hex_from_bits(bit, width): the canonical word (lowercase, no leading zeros) of bits 0..width-1; "" for zero.
function hex_from_bits(bit, width,    d, v, out, started) {
  out = ""
  started = 0
  for (d = int((width + 3) / 4) - 1; d >= 0; d--) {
    v = 0
    if ((4 * d) in bit) v += 1
    if ((4 * d + 1) in bit) v += 2
    if ((4 * d + 2) in bit) v += 4
    if ((4 * d + 3) in bit) v += 8
    if (v != 0 || started) {
      out = out substr("0123456789abcdef", v + 1, 1)
      started = 1
    }
  }
  return out
}

# ---- canonical MFW1 output: terms are collected, equal terms cancel in pairs, the rest is sorted by (u, v, w) ----

function init_mfw(n, m, p) {
  MFW_N = n; MFW_M = m; MFW_P = p
  MFW_DU = int((n * m + 3) / 4)
  MFW_DV = int((m * p + 3) / 4)
  MFW_DW = int((n * p + 3) / 4)
  delete MFW_PAR
}

function padhex(h, digits) {
  while (length(h) < digits) h = "0" h
  return h
}

function add_term(hu, hv, hw,    key) {
  if (hu == "" || hv == "" || hw == "") return
  key = padhex(hu, MFW_DU) " " padhex(hv, MFW_DV) " " padhex(hw, MFW_DW)
  if (key in MFW_PAR) delete MFW_PAR[key]
  else MFW_PAR[key] = 1
}

function heap_sift(a, root, size,    child, t) {
  while (2 * root <= size) {
    child = 2 * root
    if (child + 1 <= size && a[child] < a[child + 1]) child++
    if (a[root] >= a[child]) break
    t = a[root]; a[root] = a[child]; a[child] = t
    root = child
  }
}

function heap_sort(a, size,    i, t) {
  for (i = int(size / 2); i >= 1; i--) heap_sift(a, i, size)
  for (i = size; i > 1; i--) {
    t = a[1]; a[1] = a[i]; a[i] = t
    heap_sift(a, 1, i - 1)
  }
}

function strip0(h) { sub(/^0+/, "", h); return h }

function emit_mfw(    key, rank, keys, i, f) {
  rank = 0
  for (key in MFW_PAR) keys[++rank] = key
  heap_sort(keys, rank)
  print "MFW1 " MFW_N " " MFW_M " " MFW_P " " rank
  for (i = 1; i <= rank; i++) {
    split(keys[i], f, " ")
    print strip0(f[1]) " " strip0(f[2]) " " strip0(f[3])
  }
}

# Read a canonical or non-canonical MFW1 line stream: sets MFW_N, MFW_M, MFW_P, MFW_RANK from the header.
function read_header(    ) {
  if ($1 != "MFW1" || NF != 5) fail("not an MFW1 header: " $0)
  MFW_N = $2 + 0; MFW_M = $3 + 0; MFW_P = $4 + 0; MFW_RANK = $5 + 0
}
