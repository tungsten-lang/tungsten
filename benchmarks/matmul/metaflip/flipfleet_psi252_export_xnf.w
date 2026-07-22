# XNF export of the open <2,5,2> psi-quotient cells: CryptoMiniSat native
# XOR lines ("x <lits> 0", odd parity) instead of Tseitin chains.  Native
# rows preserve the parity structure, although the solver decides whether
# they form useful Gaussian matrices.  Sound lex-leader SBPs canonically orient
# every unordered {X, psi(X)} pair, then order interchangeable pair
# representatives and fixed generators.  An UNSAT result still certifies the
# whole psi-invariant cell.
#
# Usage: flipfleet_psi252_export_xnf <out_dir>
# Primary numbering matches ffpsi_* exactly.  Products are compacted over one
# representative of each induced coefficient-cell orbit (and paired products
# cancel directly on fixed cells); lex-prefix auxiliaries are above those
# compact products.  Decoding consumes the unchanged primary prefix only.

use flipfleet_psi_xnf_export_lib

args = argv()
if args.size() < 1
  << "usage: flipfleet_psi252_export_xnf <out_dir>"
  exit(2)
out_dir = args[0]
c = 7 ## i64
while c >= 4
  f = 17 - 2 * c ## i64
  path = out_dir + "/psi252_xnf_r17_c" + c.to_s() + "f" + f.to_s() + ".cnf" ## String
  text = ffpx_cell_text(2, 5, c, f)
  if write_file(path, text)
    << "PSI252_XNF cell=(" + c.to_s() + "," + f.to_s() + ") path=" + path
  else
    << "PSI252_XNF_ERROR cell=(" + c.to_s() + "," + f.to_s() + ")"
  c -= 1
<< "PSI252_XNF_DONE"
