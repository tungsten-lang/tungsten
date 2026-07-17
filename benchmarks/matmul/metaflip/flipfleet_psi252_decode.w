# Decode an external solver model of a <2,5,2> psi-quotient cell back into
# an exact scheme (move 4 support tooling).
#
# Usage: flipfleet_psi252_decode <model_file> <c> <f> <out_path>
# The model file is cryptominisat output: "v " lines of space-separated
# literals (positive = true).  Variable numbering matches ffpsi_* exactly.
# The decoded pairs expand through psi, fixed generators through the u/w
# wiring; the term list is parity-compacted, gated by the lane's own
# exhaustive rectangular verifier, and written as a <2,5,2>-orientation
# scheme file (rank header + "u v w" rows), then re-read and re-gated.

use flipfleet_psi_quotient

-> ffpd_write(us, vs, ws, count, path) (i64[] i64[] i64[] i64 String) i64
  text = count.to_s() + "\n" ## String
  t = 0 ## i64
  while t < count
    text = text + us[t].to_s() + " " + vs[t].to_s() + " " + ws[t].to_s() + "\n"
    t += 1
  if write_file(path, text)
    return 1
  0

args = argv()
if args.size() < 4
  << "usage: flipfleet_psi252_decode <model_file> <c> <f> <out_path>"
  exit(2)
model_path = args[0]
c = args[1].to_i() ## i64
f = args[2].to_i() ## i64
out_path = args[3]
if c < 0 || f < 0 || c + f < 1
  << "usage: flipfleet_psi252_decode <model_file> <c> <f> <out_path>"
  exit(2)

content = read_file(model_path)
if content == nil
  << "PSI252_DECODE_ERROR model file unreadable"
  exit(2)
if !content.include?("SATISFIABLE") || content.include?("UNSATISFIABLE")
  << "PSI252_DECODE_ERROR model is not SATISFIABLE"
  exit(2)

n = 2 ## i64
m = 5 ## i64
p = 2 ## i64
um = n * m ## i64
vm = m * p ## i64
wm = n * p ## i64
prim = ffpsi_prim(c, f, um, vm, wm) ## i64
assign = i64[prim + 2]
lines = content.split("\n")
li = 0 ## i64
while li < lines.size()
  line = lines[li]
  if line.size() > 1 && line.slice(0, 2) == "v "
    parts = line.split(" ")
    pi = 1 ## i64
    while pi < parts.size()
      lit = parts[pi].to_i() ## i64
      v = lit ## i64
      if v < 0
        v = 0 - v
      if v >= 1 && v <= prim
        if lit > 0
          assign[v] = 1
      pi += 1
  li += 1

# Rebuild pair representatives and fixed generators from the assignment.
out_u = i64[64]
out_v = i64[64]
out_w = i64[64]
count = 0 ## i64
k = 0 ## i64
while k < c
  base = ffpsi_pair_base(k, um, vm, wm) ## i64
  u = 0 ## i64
  v = 0 ## i64
  w = 0 ## i64
  pos = 0 ## i64
  while pos < um
    if assign[base + pos] == 1
      u = u | (1 << pos)
    pos += 1
  pos = 0
  while pos < vm
    if assign[base + um + pos] == 1
      v = v | (1 << pos)
    pos += 1
  pos = 0
  while pos < wm
    if assign[base + um + vm + pos] == 1
      w = w | (1 << pos)
    pos += 1
  out_u[count] = u
  out_v[count] = v
  out_w[count] = w
  count += 1
  out_u[count] = ffpsi_apply_u(u, v, w, n, m)
  out_v[count] = ffpsi_apply_v(u, v, w, n, m)
  out_w[count] = ffpsi_apply_w(u, v, w, n, m)
  count += 1
  k += 1
q = 0 ## i64
while q < f
  base = ffpsi_fixed_base(c, q, um, vm, wm) ## i64
  u = 0 ## i64
  w = 0 ## i64
  pos = 0 ## i64
  while pos < um
    if assign[base + pos] == 1
      u = u | (1 << pos)
    pos += 1
  pos = 0
  while pos < wm
    if assign[base + um + pos] == 1
      w = w | (1 << pos)
    pos += 1
  v = 0 ## i64
  j = 0 ## i64
  while j < m
    kk = 0 ## i64
    while kk < p
      if ((u >> (kk * m + j)) & 1) == 1
        v = v | (1 << (j * p + kk))
      kk += 1
    j += 1
  out_u[count] = u
  out_v[count] = v
  out_w[count] = w
  count += 1
  q += 1

# Parity-compact (equal terms cancel pairwise; zero factors drop).
cu = i64[count + 1]
cv = i64[count + 1]
cw = i64[count + 1]
kept = 0 ## i64
i = 0 ## i64
while i < count
  if out_u[i] != 0 && out_v[i] != 0 && out_w[i] != 0
    dup = 0 - 1 ## i64
    j2 = 0 ## i64
    while j2 < kept
      if cu[j2] == out_u[i] && cv[j2] == out_v[i] && cw[j2] == out_w[i]
        dup = j2
        j2 = kept
      j2 += 1
    if dup >= 0
      cu[dup] = cu[kept - 1]
      cv[dup] = cv[kept - 1]
      cw[dup] = cw[kept - 1]
      kept -= 1
    else
      cu[kept] = out_u[i]
      cv[kept] = out_v[i]
      cw[kept] = out_w[i]
      kept += 1
  i += 1

if kept < 1 || ffpsi_verify_rect(cu, cv, cw, kept, n, m, p) != 1
  << "PSI252_DECODE_ERROR decoded scheme failed the exhaustive gate (kept=" + kept.to_s() + ")"
  exit(1)
census = i64[4]
groups = ffpsi_census(cu, cv, cw, kept, n, m, census) ## i64
if ffpd_write(cu, cv, cw, kept, out_path) != 1
  << "PSI252_DECODE_ERROR write failed"
  exit(1)
<< "PSI252_DECODE rank=" + kept.to_s() + " pairs=" + census[0].to_s() + " fixed=" + census[1].to_s() + " psi_closed=" + census[2].to_s() + " out=" + out_path
<< "PSI252_DECODE_DONE"
