# Export the open <2,5,2> psi-quotient cells as DIMACS for an external
# solver.  Usage: flipfleet_psi252_export <out_dir>
# Writes psi252_r<rank>_c<c>f<f>.cnf per open cell (SBPs included: sound
# for class certification).  Variable numbering matches ffpsi_* exactly,
# so a SAT model's positive primary literals decode with the lane's maps.

use flipfleet_psi_quotient

args = argv()
if args.size() < 1
  << "usage: flipfleet_psi252_export <out_dir>"
  exit(2)
out_dir = args[0]

-> ffpe_export(c, f, rank, out_dir) (i64 i64 i64 String) i64
  sat = i64[ffcdcl_state_size(60000, 3000000)]
  if ffcdcl_init(sat, 60000, 424201) != 1
    return 0 - 1
  if ffpsi_encode(sat, 2, 5, c, f) != 1
    return 0 - 1
  if ffpsi_encode_matmul_sbps(sat, 2, 5, c, f) != 1
    return 0 - 1
  path = out_dir + "/psi252_r" + rank.to_s() + "_c" + c.to_s() + "f" + f.to_s() + ".cnf" ## String
  written = ffcdcl_dump_dimacs(sat, path) ## i64
  << "PSI252_EXPORT cell=(" + c.to_s() + "," + f.to_s() + ") rank=" + rank.to_s() + " clauses=" + written.to_s() + " path=" + path
  written

c = 7 ## i64
while c >= 3
  z = ffpe_export(c, 17 - 2 * c, 17, out_dir)
  c -= 1
c = 8
while c >= 5
  z = ffpe_export(c, 18 - 2 * c, 18, out_dir)
  c -= 1
<< "PSI252_EXPORT_DONE"
