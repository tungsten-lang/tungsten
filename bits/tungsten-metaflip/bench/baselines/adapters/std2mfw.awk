# The standard algorithm as canonical MFW1.  awk -v n=N -v m=M -v p=P -f mfw-lib.awk -f std2mfw.awk
BEGIN {
  init_mfw(n, m, p)
  for (i = 0; i < n; i++) for (k = 0; k < m; k++) for (j = 0; j < p; j++) {
    delete ba; delete bb; delete bc
    ba[i * m + k] = 1; bb[k * p + j] = 1; bc[i * p + j] = 1
    add_term(hex_from_bits(ba, n * m), hex_from_bits(bb, m * p), hex_from_bits(bc, n * p))
  }
  emit_mfw()
}
