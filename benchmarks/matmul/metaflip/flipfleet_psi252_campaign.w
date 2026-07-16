# psi-class closure campaign for the <2,5,2> (= rotated <2,2,5>) rank-17
# gap.  Sweeps every (c pairs, f fixed) partition of r = 17 (and the r = 18
# witness cells) through the psi-quotient existence solver at a real
# conflict budget.  Any SAT at 17 is an outright new record candidate
# (gated in-lane before it is reported); certifying every 17-cell UNSAT
# closes the whole psi-symmetric class at rank 17 -- a publishable
# certified negative inside the campaign's only constructive gap.
#
# Usage: flipfleet_psi252_campaign [conflict_budget] [seed]
# Verdict lines are grep-able: PSI252_CAMPAIGN cell=(c,f) rank=<r> ...
# A SAT witness is serialized (rank header + "u v w" rows, <2,5,2>
# orientation) to /tmp/psi252_witness_r<r>_c<c>f<f>.txt after the lane's
# own exhaustive gate.

use flipfleet_psi_quotient

-> ffpc_write_witness(us, vs, ws, count, path) (i64[] i64[] i64[] i64 String) i64
  text = count.to_s() + "\n" ## String
  t = 0 ## i64
  while t < count
    text = text + us[t].to_s() + " " + vs[t].to_s() + " " + ws[t].to_s() + "\n"
    t += 1
  if write_file(path, text)
    return 1
  0

args = argv()
budget = 400000 ## i64
seed = 316001 ## i64
if args.size() > 0
  parsed = args[0].to_i() ## i64
  if parsed > 0
    budget = parsed
if args.size() > 1
  parsed = args[1].to_i() ## i64
  if parsed > 0
    seed = parsed

<< "PSI252_CAMPAIGN_START budget=" + budget.to_s() + " seed=" + seed.to_s()
out_u = i64[64]
out_v = i64[64]
out_w = i64[64]
meta = i64[16]
closed17 = 0 ## i64
open17 = 0 ## i64
sat17 = 0 ## i64

# rank 17 = 2c + f, f odd: cells (8,1) .. (0,17).
c = 8 ## i64
while c >= 0
  f = 17 - 2 * c ## i64
  hit = ffpsi_solve(2, 5, c, f, budget, seed + c * 17, out_u, out_v, out_w, meta) ## i64
  verdict = "indeterminate" ## String
  if meta[2] == 1
    verdict = "SAT"
  if meta[2] == 0 - 1
    verdict = "certified-unsat"
  << "PSI252_CAMPAIGN cell=(" + c.to_s() + "," + f.to_s() + ") rank=17 verdict=" + verdict + " gated_rank=" + hit.to_s() + " vars=" + meta[0].to_s() + " clauses=" + meta[1].to_s() + " conflicts=" + meta[3].to_s() + " ms=" + meta[7].to_s()
  if meta[2] == 0 - 1
    closed17 += 1
  if meta[2] == 0 - 2
    open17 += 1
  if meta[2] == 1
    sat17 += 1
    if hit > 0 && hit <= 17
      path = "/tmp/psi252_witness_r" + hit.to_s() + "_c" + c.to_s() + "f" + f.to_s() + ".txt" ## String
      z = ffpc_write_witness(out_u, out_v, out_w, hit, path)
      << "PSI252_CAMPAIGN_RECORD_CANDIDATE rank=" + hit.to_s() + " witness=" + path + " (gated by ffpsi_verify_rect in-lane; ROTATE TO <2,2,5> AND RE-GATE BEFORE ANY CLAIM)"
  c -= 1

if closed17 == 9
  << "PSI252_CAMPAIGN_CLASS_CLOSED rank=17 all 9 psi-partition cells certified UNSAT at budget=" + budget.to_s() + " -- no psi-symmetric <2,5,2> rank-17 scheme exists"
else
  << "PSI252_CAMPAIGN_STATUS rank=17 closed=" + closed17.to_s() + "/9 indeterminate=" + open17.to_s() + " sat=" + sat17.to_s()

# rank 18 witness cells (a psi-symmetric 18 would further validate the
# encoding at scale and seed the quotient walker).
c = 9
while c >= 5
  f = 18 - 2 * c ## i64
  hit = ffpsi_solve(2, 5, c, f, budget, seed + 7001 + c * 13, out_u, out_v, out_w, meta) ## i64
  verdict = "indeterminate" ## String
  if meta[2] == 1
    verdict = "SAT"
  if meta[2] == 0 - 1
    verdict = "certified-unsat"
  << "PSI252_CAMPAIGN cell=(" + c.to_s() + "," + f.to_s() + ") rank=18 verdict=" + verdict + " gated_rank=" + hit.to_s() + " conflicts=" + meta[3].to_s() + " ms=" + meta[7].to_s()
  if meta[2] == 1 && hit > 0 && hit <= 18
    path = "/tmp/psi252_witness_r" + hit.to_s() + "_c" + c.to_s() + "f" + f.to_s() + ".txt" ## String
    z = ffpc_write_witness(out_u, out_v, out_w, hit, path)
    << "PSI252_CAMPAIGN_WITNESS rank=" + hit.to_s() + " witness=" + path
  c -= 1

<< "PSI252_CAMPAIGN_DONE"
