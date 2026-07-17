# psi-equivariant descent surgery campaign driver (move 4 follow-on).
# Usage: flipfleet_psi252_descent <witness> <max_pairs> <max_fixed>
#          <budget> <seed> <out_path>
# Mechanics and certificates: see flipfleet_psi252_descent_lib.w.

use flipfleet_psi252_descent_lib

args = argv()
if args.size() < 6
  << "usage: flipfleet_psi252_descent <witness> <max_pairs> <max_fixed> <budget> <seed> <out_path>"
  exit(2)
witness_path = args[0]
max_pairs = args[1].to_i() ## i64
max_fixed = args[2].to_i() ## i64
budget = args[3].to_i() ## i64
seed = args[4].to_i() ## i64
out_path = args[5]
if max_pairs < 0 || max_fixed < 0 || budget < 1 || seed < 1
  << "usage: flipfleet_psi252_descent <witness> <max_pairs> <max_fixed> <budget> <seed> <out_path>"
  exit(2)
content = read_file(witness_path)
if content == nil
  << "PSI252_DESCENT_ERROR witness unreadable"
  exit(2)
lines = content.split("\n")
rank = lines[0].to_i() ## i64
if rank < 2 || rank > 60
  << "PSI252_DESCENT_ERROR bad witness rank"
  exit(2)
us = i64[rank + 2]
vs = i64[rank + 2]
ws = i64[rank + 2]
t = 0 ## i64
while t < rank
  parts = lines[1 + t].split(" ")
  us[t] = parts[0].to_i()
  vs[t] = parts[1].to_i()
  ws[t] = parts[2].to_i()
  t += 1
meta = i64[8]
hits = ffpds_sweep(us, vs, ws, rank, max_pairs, max_fixed, budget, seed, out_path, meta) ## i64
if hits < 0
  << "PSI252_DESCENT_ERROR code=" + hits.to_s()
  exit(2)
<< "PSI252_DESCENT_START witness=" + witness_path + " rank=" + rank.to_s() + " pairs=" + meta[4].to_s() + " fixed=" + meta[5].to_s() + " budget=" + budget.to_s()
if hits > 0
  << "PSI252_DESCENT_RECORD_CANDIDATE out=" + out_path + " (ROTATE TO <2,2,5> AND INDEPENDENTLY RE-GATE BEFORE ANY CLAIM)"
<< "PSI252_DESCENT_DONE hits=" + hits.to_s() + " certified_unsat=" + meta[1].to_s() + " indeterminate=" + meta[2].to_s()
