# Perminov ternary_flip_graph text -> canonical MFW1 over GF(2) (a coefficient c counts as abs(c) mod 2, as the tool reads it).
# awk -f mfw-lib.awk -f tfg2mfw.awk FILE.txt
{ for (f = 1; f <= NF; f++) tok[++count] = $f }
END {
  if (failed) exit 2
  n = tok[1] + 0; m = tok[2] + 0; p = tok[3] + 0; rank = tok[4] + 0
  eu = n * m; ev = m * p; ew = p * n
  if (count != 4 + rank * (eu + ev + ew)) fail("expected " (4 + rank * (eu + ev + ew)) " numbers, found " count)
  init_mfw(n, m, p)
  for (t = 0; t < rank; t++) {
    delete ba; delete bb; delete bc
    for (j = 0; j < eu; j++) if (odd(tok[5 + t * eu + j])) ba[j] = 1
    for (j = 0; j < ev; j++) if (odd(tok[5 + rank * eu + t * ev + j])) bb[j] = 1
    for (j = 0; j < p; j++) for (i = 0; i < n; i++)
      if (odd(tok[5 + rank * (eu + ev) + t * ew + j * n + i])) bc[i * p + j] = 1
    add_term(hex_from_bits(ba, eu), hex_from_bits(bb, ev), hex_from_bits(bc, ew))
  }
  emit_mfw()
}
function odd(x) { x += 0; if (x < 0) x = -x; return x % 2 == 1 }
