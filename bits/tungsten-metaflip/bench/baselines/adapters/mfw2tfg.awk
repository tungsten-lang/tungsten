# MFW1 -> Perminov ternary_flip_graph text (coefficients 0/1).  awk -f mfw-lib.awk -f mfw2tfg.awk FILE.mfw
# Line 1: n1 n2 n3 rank.  Lines 2-4: the coefficients of U (n1 x n2), V (n2 x n3), W (n3 x n1), term by term, row-major.
/^#/ || NF == 0 { next }
!header {
  read_header()
  header = 1
  next
}
NF == 3 {
  terms++
  bits_from_hex($1, ba); bits_from_hex($2, bb); bits_from_hex($3, bc)
  cu = ""; cv = ""; cw = ""
  for (j = 0; j < MFW_N * MFW_M; j++) cu = cu ((j in ba) ? "1 " : "0 ")
  for (j = 0; j < MFW_M * MFW_P; j++) cv = cv ((j in bb) ? "1 " : "0 ")
  for (j = 0; j < MFW_P; j++) for (i = 0; i < MFW_N; i++) cw = cw (((i * MFW_P + j) in bc) ? "1 " : "0 ")
  u = u cu; v = v cv; w = w cw
  next
}
{ fail("malformed line: " $0) }
END {
  if (failed) exit 2
  if (terms != MFW_RANK) fail("header rank " MFW_RANK " but " terms " terms")
  print MFW_N, MFW_M, MFW_P, MFW_RANK
  print u
  print v
  print w
}
