# Kauers-Moosbauer .exp -> canonical MFW1.  awk -v n=N -v m=M -v p=P -f mfw-lib.awk -f exp2mfw.awk FILE.exp
# Terms whose factor is zero are dropped and equal terms cancel in pairs (characteristic two).
function parse_factor(s, letter, rows, cols, bit, transposed,    i, j, idx) {
  delete bit
  while (match(s, letter "[0-9][0-9]")) {
    i = substr(s, RSTART + 1, 1) + 0
    j = substr(s, RSTART + 2, 1) + 0
    if (i < 1 || i > rows || j < 1 || j > cols) fail("index out of range in " substr(s, RSTART, 3))
    # rows x cols is the shape of the matrix as the tool writes it; c is stored p x n, MFW1 wants n x p
    idx = transposed ? (j - 1) * rows + (i - 1) : (i - 1) * cols + (j - 1)
    bit[idx] = 1
    s = substr(s, RSTART + RLENGTH)
  }
}
BEGIN {
  if (n < 1 || m < 1 || p < 1) fail("set -v n= -v m= -v p=")
  init_mfw(n, m, p)
}
/^#/ { next }
{
  line = $0
  gsub(/[ \t\r]/, "", line)
  if (line == "") next
  if (split(line, part, "*") != 3) fail("malformed term: " $0)
  parse_factor(part[1], "a", n, m, ba, 0)
  parse_factor(part[2], "b", m, p, bb, 0)
  parse_factor(part[3], "c", p, n, bc, 1)
  add_term(hex_from_bits(ba, n * m), hex_from_bits(bb, m * p), hex_from_bits(bc, n * p))
}
END {
  if (failed) exit 2
  emit_mfw()
}
