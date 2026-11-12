# MFW1 -> Kauers-Moosbauer .exp text.  awk -f mfw-lib.awk -f mfw2exp.awk FILE.mfw
# Term:  (a11+a12)*(b21)*(c11+c21)   a[i][k], b[k][j], c[j][i]  (indices are single digits, i.e. dimensions <= 9;
# the programs keep every factor in one 64-bit word, so n*m, m*p and n*p must be at most 64).
/^#/ || NF == 0 { next }
NR == 1 || !header {
  read_header()
  header = 1
  if (MFW_N > 9 || MFW_M > 9 || MFW_P > 9) fail("dimensions above 9 are not representable in .exp")
  if (MFW_N * MFW_M > 64 || MFW_M * MFW_P > 64 || MFW_N * MFW_P > 64) fail("a factor needs more than 64 bits")
  if (MFW_RANK > MFW_N * MFW_M * MFW_P) fail("rank above n*m*p: the programs allocate n*m*p terms")
  next
}
NF == 3 {
  terms++
  bits_from_hex($1, ba); bits_from_hex($2, bb); bits_from_hex($3, bc)
  s = ""
  for (i = 0; i < MFW_N; i++) for (k = 0; k < MFW_M; k++) if ((i * MFW_M + k) in ba) s = s (s == "" ? "" : "+") "a" (i + 1) (k + 1)
  out = "(" s ")*("
  s = ""
  for (k = 0; k < MFW_M; k++) for (j = 0; j < MFW_P; j++) if ((k * MFW_P + j) in bb) s = s (s == "" ? "" : "+") "b" (k + 1) (j + 1)
  out = out s ")*("
  s = ""
  for (j = 0; j < MFW_P; j++) for (i = 0; i < MFW_N; i++) if ((i * MFW_P + j) in bc) s = s (s == "" ? "" : "+") "c" (j + 1) (i + 1)
  print out s ")"
  next
}
{ fail("malformed line: " $0) }
END {
  if (failed) exit 2
  if (terms != MFW_RANK) fail("header rank " MFW_RANK " but " terms " terms")
}
