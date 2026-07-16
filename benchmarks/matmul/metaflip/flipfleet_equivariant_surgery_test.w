# Planted regressions plus bounded smokes for equivariant orbit surgery
# (move 5).  Pure CPU, in-process CDCL only.  Run from the repo root.
#
# Proved here, in order: the rho census of naive 3x3 (3 fixed cubes + 8 free
# orbits, the flipfleet_sym_anneal convention), rho^3 = id and cube
# detection, planted ORBIT re-derivation (excise one whole orbit, the
# invariant CDCL solve must find a 3-term replacement reproducing the
# residual exactly, application restores full exactness), planted CUBE
# re-derivation, an honest orbit-drop attempt (excise 2 orbits, ask for
# 1 orbit + 2 cubes = net -1), the end-to-end driver with the publish dance,
# and the 5x5 d1155 frontier census + a budget-bounded re-derivation probe.

use flipfleet_equivariant_surgery

-> ffest_expect(label, condition) (String bool) i64
  if !condition
    << "EQUIVARIANT_FAIL " + label
    exit(1)
  1

cap3 = ffw_default_capacity(3) ## i64
st3 = i64[ffw_state_size(cap3)]
rank3 = ffw_init_naive_cap(st3, 3, cap3, 7101, 0, 1, 1, 1) ## i64
z = ffest_expect("naive 3x3 rank", rank3 == 27)
eu = i64[64]
ev = i64[64]
ew = i64[64]
count = ffw_export_current(st3, eu, ev, ew) ## i64
z = ffest_expect("naive export", count == 27)

# --- census + rho unit checks ------------------------------------------------
profile = i64[4]
z = ffest_expect("naive is rho-closed", ffes_verify_c3(eu, ev, ew, 27, 3, profile) == 1)
z = ffest_expect("naive orbit census", profile[0] == 8 && profile[1] == 3)

u0 = eu[5] ## i64
v0 = ev[5] ## i64
w0 = ew[5] ## i64
u1 = ffes_rho_u(u0, v0, w0, 3) ## i64
v1 = ffes_rho_v(u0, v0, w0, 3) ## i64
w1 = ffes_rho_w(u0, v0, w0, 3) ## i64
u2 = ffes_rho_u(u1, v1, w1, 3) ## i64
v2 = ffes_rho_v(u1, v1, w1, 3) ## i64
w2 = ffes_rho_w(u1, v1, w1, 3) ## i64
u3 = ffes_rho_u(u2, v2, w2, 3) ## i64
v3 = ffes_rho_v(u2, v2, w2, 3) ## i64
w3 = ffes_rho_w(u2, v2, w2, 3) ## i64
z = ffest_expect("rho cubes to identity", u3 == u0 && v3 == v0 && w3 == w0)
z = ffest_expect("cube detection", ffes_is_cube(1, 1, 1, 3) == 1 && ffes_is_cube(1, 2, 1, 3) == 0)

# --- planted orbit re-derivation ----------------------------------------------
# The orbit of naive (0,1,0) = (2, 8, 1).
a0 = ffes_find_term(eu, ev, ew, 27, 2, 8, 1) ## i64
z = ffest_expect("anchor term live", a0 >= 0)
a1 = ffes_find_term(eu, ev, ew, 27, ffes_rho_u(2, 8, 1, 3), ffes_rho_v(2, 8, 1, 3), ffes_rho_w(2, 8, 1, 3)) ## i64
b1u = ffes_rho_u(2, 8, 1, 3) ## i64
b1v = ffes_rho_v(2, 8, 1, 3) ## i64
b1w = ffes_rho_w(2, 8, 1, 3) ## i64
a2 = ffes_find_term(eu, ev, ew, 27, ffes_rho_u(b1u, b1v, b1w, 3), ffes_rho_v(b1u, b1v, b1w, 3), ffes_rho_w(b1u, b1v, b1w, 3)) ## i64
z = ffest_expect("orbit images live", a1 >= 0 && a2 >= 0 && a1 != a0 && a2 != a0 && a1 != a2)
excised = i64[8]
excised[0] = a0
excised[1] = a1
excised[2] = a2
rep_u = i64[34]
rep_v = i64[34]
rep_w = i64[34]
smeta = i64[16]
solved = ffes_solve_replacement(eu, ev, ew, 27, 3, excised, 3, 1, 0, 200000, 7103, rep_u, rep_v, rep_w, smeta) ## i64
z = ffest_expect("orbit re-derivation SAT", solved == 3 && smeta[6] == 1)
ex_u = i64[4]
ex_v = i64[4]
ex_w = i64[4]
ex_u[0] = eu[a0]
ex_v[0] = ev[a0]
ex_w[0] = ew[a0]
ex_u[1] = eu[a1]
ex_v[1] = ev[a1]
ex_w[1] = ew[a1]
ex_u[2] = eu[a2]
ex_v[2] = ev[a2]
ex_w[2] = ew[a2]
applied = ffes_apply(st3, 3, ex_u, ex_v, ex_w, 3, rep_u, rep_v, rep_w, 3) ## i64
z = ffest_expect("orbit replacement applies", applied > 0 && applied <= 27)
z = ffest_expect("orbit replacement exact", ffw_verify_current_exact(st3, 3) == 1)
<< "EQUIVARIANT_ORBIT solved=" + solved.to_s() + " vars=" + smeta[4].to_s() + " clauses=" + smeta[5].to_s() + " conflicts=" + smeta[7].to_s() + " ms=" + smeta[11].to_s() + " applied_rank=" + applied.to_s()

# --- planted cube re-derivation ------------------------------------------------
rank3b = ffw_init_naive_cap(st3, 3, cap3, 7105, 0, 1, 1, 1) ## i64
count = ffw_export_current(st3, eu, ev, ew)
c0 = ffes_find_term(eu, ev, ew, 27, 1, 1, 1) ## i64
z = ffest_expect("cube term live", c0 >= 0)
excised[0] = c0
solved = ffes_solve_replacement(eu, ev, ew, 27, 3, excised, 1, 0, 1, 200000, 7107, rep_u, rep_v, rep_w, smeta)
z = ffest_expect("cube re-derivation SAT", solved == 1 && smeta[6] == 1)
z = ffest_expect("cube solution is a cube", ffes_is_cube(rep_u[0], rep_v[0], rep_w[0], 3) == 1)
ex_u[0] = eu[c0]
ex_v[0] = ev[c0]
ex_w[0] = ew[c0]
applied = ffes_apply(st3, 3, ex_u, ex_v, ex_w, 1, rep_u, rep_v, rep_w, 1)
z = ffest_expect("cube replacement applies", applied > 0 && applied <= 27)
z = ffest_expect("cube replacement exact", ffw_verify_current_exact(st3, 3) == 1)

# --- honest orbit-drop attempt ---------------------------------------------------
# Excise two orbits (6 terms), ask for 1 orbit + 2 cubes (5 terms, net -1).
rank3c = ffw_init_naive_cap(st3, 3, cap3, 7109, 0, 1, 1, 1) ## i64
count = ffw_export_current(st3, eu, ev, ew)
ids = i64[32]
groups = ffes_partition(eu, ev, ew, 27, 3, ids, profile) ## i64
z = ffest_expect("partition groups", groups == 11)
ex_count = 0 ## i64
taken = 0 ## i64
g = 1 ## i64
drop_ex = i64[8]
while g <= groups && taken < 2
  size = 0 ## i64
  i = 0 ## i64
  while i < 27
    if ids[i] == g
      size += 1
    i += 1
  if size == 3
    i = 0
    while i < 27
      if ids[i] == g
        drop_ex[ex_count] = i
        ex_count += 1
      i += 1
    taken += 1
  g += 1
z = ffest_expect("two orbits selected", ex_count == 6)
solved = ffes_solve_replacement(eu, ev, ew, 27, 3, drop_ex, 6, 1, 2, 150000, 7111, rep_u, rep_v, rep_w, smeta)
z = ffest_expect("drop attempt terminates", solved >= 0)
<< "EQUIVARIANT_DROP want=(1,2) status=" + smeta[6].to_s() + " solved=" + solved.to_s() + " conflicts=" + smeta[7].to_s() + " ms=" + smeta[11].to_s()
if solved > 0
  i = 0 ## i64
  while i < ex_count
    ex_u[0] = 0
    i += 1
  dex_u = i64[8]
  dex_v = i64[8]
  dex_w = i64[8]
  i = 0
  while i < 6
    dex_u[i] = eu[drop_ex[i]]
    dex_v[i] = ev[drop_ex[i]]
    dex_w[i] = ew[drop_ex[i]]
    i += 1
  applied = ffes_apply(st3, 3, dex_u, dex_v, dex_w, 6, rep_u, rep_v, rep_w, solved)
  z = ffest_expect("drop application exact when SAT", applied > 0 && ffw_verify_current_exact(st3, 3) == 1)
  << "EQUIVARIANT_DROP applied_rank=" + applied.to_s()

# --- end-to-end driver + publish dance -----------------------------------------
seed_path = "/tmp/ffes_test_naive3.txt"
out_path = "/tmp/ffes_test_out3.txt"
rank3d = ffw_init_naive_cap(st3, 3, cap3, 7113, 0, 1, 1, 1) ## i64
z = ffest_expect("seed dump", ffw_dump_best(st3, seed_path) == 27)
dmeta = i64[16]
result = ffes_surgery(seed_path, 3, 1, 0, 1, 0, 200000, 7115, out_path, dmeta) ## i64
z = ffest_expect("driver applies", result > 0 && dmeta[10] == 1)
z = ffest_expect("driver census", dmeta[12] == 8 && dmeta[13] == 3)
reload = i64[ffw_state_size(cap3)]
z = ffest_expect("driver output reloads", ffw_load_scheme_cap(reload, out_path, 3, cap3, 7117, 0, 1, 1, 1) == result)
z = ffest_expect("driver output exact", ffw_verify_current_exact(reload, 3) == 1)
<< "EQUIVARIANT_DRIVER rank=" + result.to_s() + " status=" + dmeta[6].to_s() + " conflicts=" + dmeta[7].to_s() + " ms=" + dmeta[11].to_s()

# --- 5x5 d1155 frontier census + bounded probe ----------------------------------
cap5 = ffw_default_capacity(5) ## i64
st5 = i64[ffw_state_size(cap5)]
r5 = ffw_load_scheme_cap(st5, "benchmarks/matmul/metaflip/matmul_5x5_rank93_d1155_gf2.txt", 5, cap5, 7119, 0, 1, 1, 1) ## i64
if r5 == 93
  eu5 = i64[128]
  ev5 = i64[128]
  ew5 = i64[128]
  c5 = ffw_export_current(st5, eu5, ev5, ew5) ## i64
  closed5 = ffes_verify_c3(eu5, ev5, ew5, 93, 5, profile) ## i64
  << "EQUIVARIANT_D1155 closed=" + closed5.to_s() + " orbits=" + profile[0].to_s() + " cubes=" + profile[1].to_s()
  if closed5 == 1
    z = ffest_expect("d1155 documented census", profile[0] == 30 && profile[1] == 3)
    ids5 = i64[128]
    groups5 = ffes_partition(eu5, ev5, ew5, 93, 5, ids5, profile) ## i64
    ex5 = i64[4]
    ex5_count = 0 ## i64
    g = 1
    while g <= groups5 && ex5_count == 0
      size = 0 ## i64
      i = 0 ## i64
      while i < 93
        if ids5[i] == g
          size += 1
        i += 1
      if size == 3
        i = 0
        while i < 93
          if ids5[i] == g
            ex5[ex5_count] = i
            ex5_count += 1
          i += 1
      g += 1
    z = ffest_expect("d1155 orbit selected", ex5_count == 3)
    solved5 = ffes_solve_replacement(eu5, ev5, ew5, 93, 5, ex5, 3, 1, 0, 20000, 7121, rep_u, rep_v, rep_w, smeta) ## i64
    << "EQUIVARIANT_D1155 probe status=" + smeta[6].to_s() + " solved=" + solved5.to_s() + " vars=" + smeta[4].to_s() + " clauses=" + smeta[5].to_s() + " conflicts=" + smeta[7].to_s() + " ms=" + smeta[11].to_s()
    z = ffest_expect("d1155 probe terminates", solved5 >= 0)
else
  << "EQUIVARIANT_D1155 file-not-loaded rank=" + r5.to_s() + " (skipping frontier leg)"

<< "flipfleet_equivariant_surgery_test: all checks passed"
