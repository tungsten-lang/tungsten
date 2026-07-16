# Planted regressions for 2-adic carry compilation (move 6).  Pure CPU.
# Run from the repo root (lexer tables are CWD-relative).
#
# Plants, in order: integer Strassen (all-odd witness, clean level-0 close),
# a planted -2t carry (depth-1 primitive, unchanged emission), an odd-defect
# corruption (must refuse, never emit), a signless 0/1 lift of Strassen (the
# vacuity guard: exact mod 2, provably NOT exact over Z), GL(Z) sandwich
# transvection exactness plus bounded rebalance descent, the rectangular
# <2,2,3> path with a planted carry, the witness file parser (comments,
# negatives, rejects), and the publish dance including tamper refusal.

use flipfleet_carry_compile

-> ffcct_expect(label, condition) (String bool) i64
  if !condition
    << "CARRY_COMPILE_FAIL " + label
    exit(1)
  1

# Serialize an integer witness in the documented file format.
-> ffcct_witness_text(iu, iv, iw, r, n, m, p) (i64[] i64[] i64[] i64 i64 i64 i64)
  text = "# planted witness\n\n" + n.to_s() + " " + m.to_s() + " " + p.to_s() + " " + r.to_s() + "\n"
  t = 0 ## i64
  while t < r
    row = "" ## String
    e = 0 ## i64
    while e < n * m
      if e > 0
        row = row + " "
      row = row + iu[t * n * m + e].to_s()
      e += 1
    text = text + row + "\n"
    row = ""
    e = 0
    while e < m * p
      if e > 0
        row = row + " "
      row = row + iv[t * m * p + e].to_s()
      e += 1
    text = text + row + "\n"
    row = ""
    e = 0
    while e < n * p
      if e > 0
        row = row + " "
      row = row + iw[t * n * p + e].to_s()
      e += 1
    text = text + row + "\n"
    t += 1
  text

iu = i64[40]
iv = i64[40]
iw = i64[40]
out_u = i64[16]
out_v = i64[16]
out_w = i64[16]
acc_u = i64[16]
acc_v = i64[16]
acc_w = i64[16]
acc_level = i64[16]
profile = i64[64]
meta = i64[16]

# --- integer Strassen: clean level-0 close --------------------------------
r = ffcc_strassen_int(iu, iv, iw) ## i64
z = ffcct_expect("strassen term count", r == 7)
z = ffcct_expect("strassen exact over Z", ffcc_verify_z_exact(iu, iv, iw, 7, 2, 2, 2) == 1)
emitted = ffcc_compile(iu, iv, iw, 7, 2, 2, 2, out_u, out_v, out_w, acc_u, acc_v, acc_w, acc_level, profile, meta) ## i64
z = ffcct_expect("strassen emitted", emitted == 7)
z = ffcct_expect("strassen level-0 profile", profile[0] == 7 && meta[8] == 7)
z = ffcct_expect("strassen no defect", meta[3] == 0 - 1 && meta[4] == 0)
z = ffcct_expect("strassen certified over Z", meta[6] == 1)
z = ffcct_expect("strassen bound", meta[2] == 7)
z = ffcct_expect("strassen gates", ffcc_gate_square(out_u, out_v, out_w, 7, 2) == 1)

# --- planted -2t carry: depth-1 primitive, emission unchanged --------------
r = ffcc_strassen_int(iu, iv, iw)
r = ffcc_plant_carry(iu, iv, iw, 7, 0, 4, 4, 4)
z = ffcct_expect("plant grows witness", r == 8)
z = ffcct_expect("planted still exact over Z", ffcc_verify_z_exact(iu, iv, iw, 8, 2, 2, 2) == 1)
emitted = ffcc_compile(iu, iv, iw, 8, 2, 2, 2, out_u, out_v, out_w, acc_u, acc_v, acc_w, acc_level, profile, meta)
z = ffcct_expect("planted emitted still 7", emitted == 7)
z = ffcct_expect("planted raw level-0", meta[8] == 7)
z = ffcct_expect("planted depth-1 primitive", profile[1] == 1)
z = ffcct_expect("planted bound 8", meta[2] == 8)
z = ffcct_expect("planted certified", meta[6] == 1 && meta[4] == 0)
z = ffcct_expect("planted gates", ffcc_gate_square(out_u, out_v, out_w, 7, 2) == 1)

# --- odd defect: refuse, never emit ----------------------------------------
r = ffcc_strassen_int(iu, iv, iw)
z = ffcc_copy_term(iu, iv, iw, 0, 7, 4, 4, 4)
emitted = ffcc_compile(iu, iv, iw, 8, 2, 2, 2, out_u, out_v, out_w, acc_u, acc_v, acc_w, acc_level, profile, meta)
z = ffcct_expect("odd defect refused", emitted == 0 - 2)
z = ffcct_expect("odd defect depth zero", meta[3] == 0)

# --- vacuity guard: 0/1 lift of Strassen mod 2 -----------------------------
r = ffcc_strassen_int(iu, iv, iw)
emitted = ffcc_compile(iu, iv, iw, 7, 2, 2, 2, out_u, out_v, out_w, acc_u, acc_v, acc_w, acc_level, profile, meta)
lifted = ffcc_lift_gf2(out_u, out_v, out_w, 7, iu, iv, iw, 4, 4, 4) ## i64
z = ffcct_expect("lift count", lifted == 7)
was_z_exact = ffcc_verify_z_exact(iu, iv, iw, 7, 2, 2, 2) ## i64
z = ffcct_expect("signless lift not exact over Z", was_z_exact == 0)
emitted = ffcc_compile(iu, iv, iw, 7, 2, 2, 2, out_u, out_v, out_w, acc_u, acc_v, acc_w, acc_level, profile, meta)
z = ffcct_expect("lift still emits mod-2 scheme", emitted == 7)
z = ffcct_expect("lift gates over GF(2)", ffcc_gate_square(out_u, out_v, out_w, 7, 2) == 1)
z = ffcct_expect("vacuity flagged", meta[6] == 0)
<< "CARRY_VACUITY levels=" + meta[0].to_s() + " leftover_cells=" + meta[4].to_s() + " odd_defect_depth=" + meta[3].to_s()

# --- GL(Z) sandwich transvection + bounded rebalance -----------------------
r = ffcc_strassen_int(iu, iv, iw)
z = ffcc_apply_transvection(iu, iv, iw, 7, 2, 2, 2, 0, 0, 1, 1)
z = ffcct_expect("transvection fixes T", ffcc_verify_z_exact(iu, iv, iw, 7, 2, 2, 2) == 1)
z = ffcc_apply_transvection(iu, iv, iw, 7, 2, 2, 2, 1, 1, 0, 2)
z = ffcct_expect("second transvection fixes T", ffcc_verify_z_exact(iu, iv, iw, 7, 2, 2, 2) == 1)
rb_meta = i64[4]
final_obj = ffcc_rebalance(iu, iv, iw, 7, 2, 2, 2, 8, rb_meta) ## i64
z = ffcct_expect("rebalance monotone", rb_meta[2] <= rb_meta[1])
z = ffcct_expect("rebalance probed", rb_meta[3] > 0)
z = ffcct_expect("rebalance preserves T", ffcc_verify_z_exact(iu, iv, iw, 7, 2, 2, 2) == 1)
emitted = ffcc_compile(iu, iv, iw, 7, 2, 2, 2, out_u, out_v, out_w, acc_u, acc_v, acc_w, acc_level, profile, meta)
z = ffcct_expect("rebalanced compile emits", emitted > 0)
z = ffcct_expect("rebalanced gates", ffcc_gate_square(out_u, out_v, out_w, emitted, 2) == 1)
<< "CARRY_REBALANCE initial=" + rb_meta[1].to_s() + " final=" + rb_meta[2].to_s() + " steps=" + rb_meta[0].to_s() + " probes=" + rb_meta[3].to_s()

# --- rectangular <2,3,4> path (smallest allowlisted rect shape) -------------
ru = i64[150]
rv = i64[300]
rw = i64[200]
rout_u = i64[32]
rout_v = i64[32]
rout_w = i64[32]
racc_u = i64[32]
racc_v = i64[32]
racc_w = i64[32]
racc_level = i64[32]
r = ffcc_naive_int(ru, rv, rw, 2, 3, 4) ## i64
z = ffcct_expect("naive 234 count", r == 24)
z = ffcct_expect("naive 234 exact over Z", ffcc_verify_z_exact(ru, rv, rw, 24, 2, 3, 4) == 1)
emitted = ffcc_compile(ru, rv, rw, 24, 2, 3, 4, rout_u, rout_v, rout_w, racc_u, racc_v, racc_w, racc_level, profile, meta)
z = ffcct_expect("naive 234 emitted", emitted == 24)
z = ffcct_expect("naive 234 certified", meta[6] == 1)
z = ffcct_expect("naive 234 gates rect", ffcc_gate_rect(rout_u, rout_v, rout_w, 24, 2, 3, 4) == 1)
r = ffcc_naive_int(ru, rv, rw, 2, 3, 4)
r = ffcc_plant_carry(ru, rv, rw, 24, 5, 6, 12, 8)
z = ffcct_expect("planted 234 grows", r == 25)
emitted = ffcc_compile(ru, rv, rw, 25, 2, 3, 4, rout_u, rout_v, rout_w, racc_u, racc_v, racc_w, racc_level, profile, meta)
z = ffcct_expect("planted 234 emitted", emitted == 24)
z = ffcct_expect("planted 234 depth-1", profile[1] == 1 && meta[6] == 1)
z = ffcct_expect("planted 234 gates", ffcc_gate_rect(rout_u, rout_v, rout_w, 24, 2, 3, 4) == 1)

# --- witness file parser ----------------------------------------------------
witness_path = "/tmp/ffcc_test_witness.txt"
r = ffcc_strassen_int(iu, iv, iw)
z = ffcct_expect("witness write", write_file(witness_path, ffcct_witness_text(iu, iv, iw, 7, 2, 2, 2)))
dims = i64[4]
lu = i64[40]
lv = i64[40]
lw = i64[40]
loaded = ffcc_load_int_scheme(witness_path, dims, lu, lv, lw, 9) ## i64
z = ffcct_expect("witness loads", loaded == 7)
z = ffcct_expect("witness dims", dims[0] == 2 && dims[1] == 2 && dims[2] == 2 && dims[3] == 7)
z = ffcct_expect("witness roundtrip exact", ffcc_verify_z_exact(lu, lv, lw, 7, 2, 2, 2) == 1)
emitted = ffcc_compile(lu, lv, lw, 7, 2, 2, 2, out_u, out_v, out_w, acc_u, acc_v, acc_w, acc_level, profile, meta)
z = ffcct_expect("witness compiles", emitted == 7)
z = ffcct_expect("witness gates", ffcc_gate_square(out_u, out_v, out_w, 7, 2) == 1)
z = ffcct_expect("bad header rejected", write_file(witness_path, "2 2 2 0\n"))
z = ffcct_expect("zero rank rejected", ffcc_load_int_scheme(witness_path, dims, lu, lv, lw, 9) < 0)
z = ffcct_expect("cap write", write_file(witness_path, "2 2 2 1\n40000 0 0 0\n0 0 0 0\n0 0 0 0\n"))
z = ffcct_expect("entry cap rejected", ffcc_load_int_scheme(witness_path, dims, lu, lv, lw, 9) < 0)

# --- publish dance -----------------------------------------------------------
publish_path = "/tmp/ffcc_test_publish.txt"
r = ffcc_strassen_int(iu, iv, iw)
emitted = ffcc_compile(iu, iv, iw, 7, 2, 2, 2, out_u, out_v, out_w, acc_u, acc_v, acc_w, acc_level, profile, meta)
z = ffcct_expect("publish accepts", ffcc_publish_square(out_u, out_v, out_w, 7, 2, publish_path) == 7)
reload = i64[ffw_state_size(ffw_default_capacity(2))]
z = ffcct_expect("publish reloads", ffw_load_scheme_cap(reload, publish_path, 2, ffw_default_capacity(2), 71, 0, 1, 1, 1) == 7)
z = ffcct_expect("publish regates", ffw_verify_best_exact(reload, 2) == 1)
bad_u = i64[16]
i = 0 ## i64
while i < 7
  bad_u[i] = out_u[i]
  i += 1
bad_u[0] = 0
z = ffcct_expect("tampered publish rejected", ffcc_publish_square(bad_u, out_v, out_w, 7, 2, publish_path) < 0)
z = ffcct_expect("tampered file removed", ffw_load_scheme_cap(reload, publish_path, 2, ffw_default_capacity(2), 73, 0, 1, 1, 1) < 0)

<< "flipfleet_carry_compile_test: all checks passed"
