# Capture driver for pair-lift crossover children (move 10).
#
# Usage: flipfleet_pair_lift_capture <parentA> <parentB> <n> <m> <p>
#          <moves> <want_mixed> <seed> <out_prefix>
# Runs one deterministic ffpl_run and, for each gated child whose term-set
# distance from BOTH parents is positive, writes <out_prefix>_child<k>.txt
# (rank header + "u v w" rows), then re-loads and re-gates the file bytes
# through the rect worker when the shape is allowlisted -- the standard
# publish discipline.  Grep-able: PAIR_LIFT_CAPTURE lines.

use flipfleet_pair_lift
use metaflip_rect_worker

-> ffplc_write(us, vs, ws, count, path) (i64[] i64[] i64[] i64 String) i64
  text = count.to_s() + "\n" ## String
  t = 0 ## i64
  while t < count
    text = text + us[t].to_s() + " " + vs[t].to_s() + " " + ws[t].to_s() + "\n"
    t += 1
  if write_file(path, text)
    return 1
  0

-> ffplc_regate(path, count, n, m, p, seed) (String i64 i64 i64 i64 i64) i64
  if ffr_supported(n, m, p) == 0
    return 2
  capacity = ffr_default_capacity(n, m, p) ## i64
  st = i64[ffr_state_size(capacity)]
  loaded = ffr_load_scheme_cap(st, path, n, m, p, capacity, seed, 0, 1, 1, 1) ## i64
  if loaded == count && ffr_verify_current_exact(st, n, m, p) == 1
    return 1
  0

args = argv()
if args.size() < 9
  << "usage: flipfleet_pair_lift_capture <parentA> <parentB> <n> <m> <p> <moves> <want_mixed> <seed> <out_prefix>"
  exit(2)
pa = args[0]
pb = args[1]
n = args[2].to_i() ## i64
m = args[3].to_i() ## i64
p = args[4].to_i() ## i64
moves = args[5].to_i() ## i64
want_mixed = args[6].to_i() ## i64
seed = args[7].to_i() ## i64
prefix = args[8]
if n < 2 || m < 2 || p < 2 || moves < 0 || seed < 1
  << "usage: flipfleet_pair_lift_capture <parentA> <parentB> <n> <m> <p> <moves> <want_mixed> <seed> <out_prefix>"
  exit(2)
if ffr_supported(n, m, p) == 0
  << "PAIR_LIFT_CAPTURE_ERROR shape not in the rect allowlist"
  exit(2)

cap = ffr_default_capacity(n, m, p) ## i64
sta = i64[ffr_state_size(cap)]
stb = i64[ffr_state_size(cap)]
ra = ffr_load_scheme_cap(sta, pa, n, m, p, cap, seed, 0, 1, 1, 1) ## i64
rb = ffr_load_scheme_cap(stb, pb, n, m, p, cap, seed + 2, 0, 1, 1, 1) ## i64
if ra < 1 || rb < 1
  << "PAIR_LIFT_CAPTURE_ERROR parents failed to load (" + ra.to_s() + ", " + rb.to_s() + ")"
  exit(2)
xu = i64[cap]
xv = i64[cap]
xw = i64[cap]
yu = i64[cap]
yv = i64[cap]
yw = i64[cap]
ca = ffw_export_current(sta, xu, xv, xw) ## i64
cb = ffw_export_current(stb, yu, yv, yw) ## i64
c1u = i64[cap]
c1v = i64[cap]
c1w = i64[cap]
c2u = i64[cap]
c2v = i64[cap]
c2w = i64[cap]
meta = i64[20]
ok = ffpl_run(xu, xv, xw, ra, yu, yv, yw, rb, n, m, p, moves, want_mixed, seed, c1u, c1v, c1w, c2u, c2v, c2w, meta) ## i64
<< "PAIR_LIFT_CAPTURE run ok=" + ok.to_s() + " fired=" + meta[2].to_s() + " cross=" + meta[4].to_s() + " harvest_mixed=" + meta[6].to_s() + " c1=" + meta[8].to_s() + " d(c1,A)=" + meta[10].to_s() + " d(c1,B)=" + meta[11].to_s() + " c2=" + meta[12].to_s() + " d(c2,B)=" + meta[14].to_s() + " d(c2,A)=" + meta[15].to_s()
if ok != 1
  << "PAIR_LIFT_CAPTURE_DONE captured=0"
  exit(0)
captured = 0 ## i64
if meta[9] == 1 && meta[10] > 0 && meta[11] > 0
  path = prefix + "_child1.txt" ## String
  if ffplc_write(c1u, c1v, c1w, meta[8], path) == 1
    gate = ffplc_regate(path, meta[8], n, m, p, seed + 11) ## i64
    if gate >= 1
      captured += 1
      << "PAIR_LIFT_CAPTURE_CHILD path=" + path + " rank=" + meta[8].to_s() + " d_from_A=" + meta[10].to_s() + " d_from_B=" + meta[11].to_s() + " regate=" + gate.to_s()
if meta[13] == 1 && meta[14] > 0 && meta[15] > 0
  path = prefix + "_child2.txt" ## String
  if ffplc_write(c2u, c2v, c2w, meta[12], path) == 1
    gate = ffplc_regate(path, meta[12], n, m, p, seed + 13) ## i64
    if gate >= 1
      captured += 1
      << "PAIR_LIFT_CAPTURE_CHILD path=" + path + " rank=" + meta[12].to_s() + " d_from_B=" + meta[14].to_s() + " d_from_A=" + meta[15].to_s() + " regate=" + gate.to_s()
<< "PAIR_LIFT_CAPTURE_DONE captured=" + captured.to_s()
