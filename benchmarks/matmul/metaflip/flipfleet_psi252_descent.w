# psi-equivariant descent surgery on a psi-symmetric <2,5,2> witness
# (move 4 follow-on; the equivariant-surgery pattern transplanted from the
# C3 rotation to the transpose involution).
#
# Load a psi-closed scheme, census it into conjugate pairs and fixed
# terms, then for every excision of (j pairs, q fixed) solve for a
# psi-invariant replacement with ONE FEWER term (2j' + q' = 2j + q - 1)
# reproducing the excised residual exactly.  Any hit splices into the
# witness as a psi-symmetric scheme of rank r - 1 -- at rank 18 input
# that is an outright <2,2,5> record candidate, gated in-lane and
# published only through write -> re-read -> re-gate.  Every UNSAT is a
# certified local lemma: that residual has no smaller psi-invariant
# presentation.  Instances are tiny next to whole-cell existence (one
# replacement group of unknowns instead of seventeen), so verdicts come
# in seconds and the sweep is exhaustive over the excision menu.
#
# Usage: flipfleet_psi252_descent <witness> <max_pairs> <max_fixed>
#          <budget> <seed> <out_path>
# Verdict lines are grep-able: PSI252_DESCENT excise=(j,q) want=(j',q').

use flipfleet_psi_quotient

-> ffpds_write(us, vs, ws, count, path) (i64[] i64[] i64[] i64 String) i64
  text = count.to_s() + "\n" ## String
  t = 0 ## i64
  while t < count
    text = text + us[t].to_s() + " " + vs[t].to_s() + " " + ws[t].to_s() + "\n"
    t += 1
  if write_file(path, text)
    return 1
  0

# Solve one excision: groups listed as term indices (whole psi-groups).
# Returns the replacement term count on a gated hit (terms in rep_*),
# 0 on UNSAT/budget (meta[2] = status), negative on structure errors.
-> ffpds_solve(us, vs, ws, rank, excised, ex_count, want_c, want_f, budget, seed, rep_u, rep_v, rep_w, meta) (i64[] i64[] i64[] i64 i64[] i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[]) i64
  i = 0 ## i64
  while i < 16
    meta[i] = 0
    i += 1
  n = 2 ## i64
  m = 5 ## i64
  p = 2 ## i64
  um = n * m ## i64
  vm = m * p ## i64
  wm = n * p ## i64
  cells = um * vm * wm ## i64
  target = i64[cells / 64 + 2]
  i = 0
  while i < ex_count
    idx = excised[i] ## i64
    if idx < 0 || idx >= rank
      return 0 - 3
    z = ffpsi_xor_outer(target, us[idx], vs[idx], ws[idx], um, vm, wm) ## i64
    i += 1
  slots = 2 * want_c + want_f ## i64
  prim = ffpsi_prim(want_c, want_f, um, vm, wm) ## i64
  aux = cells * (slots + 2) + (want_c + want_f) * (um + vm + wm) + 64 ## i64
  max_vars = prim + cells * slots + aux + 64 ## i64
  learnt_words = budget * 96 ## i64
  if learnt_words > 64000000
    learnt_words = 64000000
  clause_words = cells * slots * 30 + cells * (slots + 2) * 12 + (want_c + want_f) * (um + vm + wm + 8) * 4 + 300000 + learnt_words ## i64
  sat = i64[ffcdcl_state_size(max_vars, clause_words)]
  if ffcdcl_init(sat, max_vars, seed) != 1
    return 0 - 2
  if ffpsi_encode_target(sat, n, m, want_c, want_f, target) != 1
    return 0 - 2
  if ffpsi_encode_sbps(sat, n, m, want_c, want_f) != 1
    return 0 - 2
  meta[0] = ffcdcl_top_var(sat)
  meta[1] = ffcdcl_clause_count(sat)
  assumptions = i64[1]
  status = ffcdcl_solve(sat, assumptions, 0, budget) ## i64
  meta[2] = status
  meta[3] = ffcdcl_conflicts(sat)
  if status != 1
    return 0
  ffpsi_decode(sat, n, m, want_c, want_f, rep_u, rep_v, rep_w)

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
if ffpsi_verify_rect(us, vs, ws, rank, 2, 5, 2) != 1
  << "PSI252_DESCENT_ERROR witness failed the exhaustive gate"
  exit(2)

# Census into groups: group id per term, kind 0 = pair (two members),
# kind 1 = fixed.
group_of = i64[rank + 2]
group_kind = i64[64]
group_first = i64[64]
group_second = i64[64]
groups = 0 ## i64
t = 0
while t < rank
  group_of[t] = 0 - 1
  t += 1
t = 0
while t < rank
  if group_of[t] < 0
    pu = ffpsi_apply_u(us[t], vs[t], ws[t], 2, 5) ## i64
    pv = ffpsi_apply_v(us[t], vs[t], ws[t], 2, 5) ## i64
    pw = ffpsi_apply_w(us[t], vs[t], ws[t], 2, 5) ## i64
    if pu == us[t] && pv == vs[t] && pw == ws[t]
      group_of[t] = groups
      group_kind[groups] = 1
      group_first[groups] = t
      group_second[groups] = 0 - 1
      groups += 1
    else
      partner = 0 - 1 ## i64
      s = 0 ## i64
      while s < rank
        if s != t && group_of[s] < 0 && us[s] == pu && vs[s] == pv && ws[s] == pw
          partner = s
          s = rank
        s += 1
      if partner < 0
        << "PSI252_DESCENT_ERROR witness is not psi-closed"
        exit(2)
      group_of[t] = groups
      group_of[partner] = groups
      group_kind[groups] = 0
      group_first[groups] = t
      group_second[groups] = partner
      groups += 1
  t += 1
pair_total = 0 ## i64
g = 0 ## i64
while g < groups
  if group_kind[g] == 0
    pair_total += 1
  g += 1
<< "PSI252_DESCENT_START witness=" + witness_path + " rank=" + rank.to_s() + " pairs=" + pair_total.to_s() + " fixed=" + (groups - pair_total).to_s() + " budget=" + budget.to_s()

# Enumerate excision menus: j pairs (by group index combination is heavy;
# use contiguous rotations for breadth), q fixed, and every replacement
# split of 2j + q - 1 into 2j' + q'.
rep_u = i64[64]
rep_v = i64[64]
rep_w = i64[64]
meta = i64[16]
excised = i64[16]
hits = 0 ## i64
unsat = 0 ## i64
open_cells = 0 ## i64
j = 0 ## i64
while j <= max_pairs && hits == 0
  q = 0 ## i64
  while q + j >= 1 && q <= max_fixed && hits == 0
    if q + j >= 1
      # Rotate which groups are excised (breadth without C(n,k) blowup).
      rot = 0 ## i64
      while rot < groups && hits == 0
        ex_count = 0 ## i64
        taken_p = 0 ## i64
        taken_f = 0 ## i64
        probe = 0 ## i64
        while probe < groups && (taken_p < j || taken_f < q)
          gg = (rot + probe) % groups ## i64
          if group_kind[gg] == 0 && taken_p < j
            excised[ex_count] = group_first[gg]
            ex_count += 1
            excised[ex_count] = group_second[gg]
            ex_count += 1
            taken_p += 1
          if group_kind[gg] == 1 && taken_f < q
            excised[ex_count] = group_first[gg]
            ex_count += 1
            taken_f += 1
          probe += 1
        if taken_p == j && taken_f == q
          removed = 2 * j + q ## i64
          want_total = removed - 1 ## i64
          wc = want_total / 2 ## i64
          while wc >= 0 && hits == 0
            wf = want_total - 2 * wc ## i64
            solved = ffpds_solve(us, vs, ws, rank, excised, ex_count, wc, wf, budget, seed + rot * 31 + j * 7 + q * 3, rep_u, rep_v, rep_w, meta) ## i64
            verdict = "indeterminate" ## String
            if meta[2] == 0 - 1
              verdict = "certified-unsat"
              unsat += 1
            if meta[2] == 1
              verdict = "SAT"
            if meta[2] == 0 - 2
              open_cells += 1
            << "PSI252_DESCENT excise=(" + j.to_s() + "," + q.to_s() + ")@" + rot.to_s() + " want=(" + wc.to_s() + "," + wf.to_s() + ") verdict=" + verdict + " conflicts=" + meta[3].to_s()
            if solved > 0
              # Splice: witness minus excised plus replacement.
              nu = i64[rank + 16]
              nv = i64[rank + 16]
              nw = i64[rank + 16]
              kept = 0 ## i64
              t = 0
              while t < rank
                inex = 0 ## i64
                e = 0 ## i64
                while e < ex_count
                  if excised[e] == t
                    inex = 1
                  e += 1
                if inex == 0
                  nu[kept] = us[t]
                  nv[kept] = vs[t]
                  nw[kept] = ws[t]
                  kept += 1
                t += 1
              r = 0 ## i64
              while r < solved
                dup = 0 - 1 ## i64
                s2 = 0 ## i64
                while s2 < kept
                  if nu[s2] == rep_u[r] && nv[s2] == rep_v[r] && nw[s2] == rep_w[r]
                    dup = s2
                    s2 = kept
                  s2 += 1
                if dup >= 0
                  nu[dup] = nu[kept - 1]
                  nv[dup] = nv[kept - 1]
                  nw[dup] = nw[kept - 1]
                  kept -= 1
                else
                  if rep_u[r] != 0 && rep_v[r] != 0 && rep_w[r] != 0
                    nu[kept] = rep_u[r]
                    nv[kept] = rep_v[r]
                    nw[kept] = rep_w[r]
                    kept += 1
                r += 1
              if kept < rank && ffpsi_verify_rect(nu, nv, nw, kept, 2, 5, 2) == 1
                z = ffpds_write(nu, nv, nw, kept, out_path)
                << "PSI252_DESCENT_RECORD_CANDIDATE rank=" + kept.to_s() + " out=" + out_path + " (ROTATE TO <2,2,5> AND INDEPENDENTLY RE-GATE BEFORE ANY CLAIM)"
                hits += 1
              else
                << "PSI252_DESCENT_NOTE SAT model did not splice below rank (kept=" + kept.to_s() + ")"
            wc -= 1
        rot += 1
    q += 1
  j += 1
<< "PSI252_DESCENT_DONE hits=" + hits.to_s() + " certified_unsat=" + unsat.to_s() + " indeterminate=" + open_cells.to_s()
