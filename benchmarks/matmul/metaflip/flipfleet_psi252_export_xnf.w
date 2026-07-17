# XNF export of the open <2,5,2> psi-quotient cells: cryptominisat native
# XOR lines ("x <lits> 0", odd parity) instead of Tseitin chains, so
# Gaussian elimination sees the 400 coefficient rows structurally.  Lex
# SBPs are deliberately omitted (the solver's own symmetry machinery takes
# over; soundness is unaffected -- class UNSAT stays class UNSAT).
#
# Usage: flipfleet_psi252_export_xnf <out_dir>
# Variable numbering matches ffpsi_* exactly (products at prim + 1 + ...),
# so any SAT model decodes with the lane's maps.

use flipfleet_psi_quotient

-> ffpx_cell_text(c, f) (i64 i64)
  n = 2 ## i64
  m = 5 ## i64
  p = 2 ## i64
  um = n * m ## i64
  vm = m * p ## i64
  wm = n * p ## i64
  cells = um * vm * wm ## i64
  prim = ffpsi_prim(c, f, um, vm, wm) ## i64
  slots = 2 * c + f ## i64
  vars = i64[4]
  body = "" ## String
  chunk = "" ## String
  in_chunk = 0 ## i64
  clauses = 0 ## i64
  # Nonzero guards.
  k = 0 ## i64
  while k < c
    base = ffpsi_pair_base(k, um, vm, wm) ## i64
    axis = 0 ## i64
    while axis < 3
      width = um ## i64
      off = 0 ## i64
      if axis == 1
        width = vm
        off = um
      if axis == 2
        width = wm
        off = um + vm
      line = "" ## String
      pos = 0 ## i64
      while pos < width
        line = line + (base + off + pos).to_s() + " "
        pos += 1
      chunk = chunk + line + "0\n"
      clauses += 1
      axis += 1
    k += 1
  q = 0 ## i64
  while q < f
    base = ffpsi_fixed_base(c, q, um, vm, wm) ## i64
    line = "" ## String
    pos = 0 ## i64
    while pos < um
      line = line + (base + pos).to_s() + " "
      pos += 1
    chunk = chunk + line + "0\n"
    clauses += 1
    line = ""
    pos = 0
    while pos < wm
      line = line + (base + um + pos).to_s() + " "
      pos += 1
    chunk = chunk + line + "0\n"
    clauses += 1
    # w symmetry: w(i,k) == w(k,i).
    i = 0 ## i64
    while i < n
      kk = i + 1 ## i64
      while kk < n
        wa = base + um + i * p + kk ## i64
        wb = base + um + kk * p + i ## i64
        chunk = chunk + "-" + wa.to_s() + " " + wb.to_s() + " 0\n"
        chunk = chunk + wa.to_s() + " -" + wb.to_s() + " 0\n"
        clauses += 2
        kk += 1
      i += 1
    q += 1
  body = body + chunk
  chunk = ""
  # Products + native XOR rows.
  cell = 0 ## i64
  while cell < cells
    cc = cell % wm ## i64
    rest = cell / wm ## i64
    b = rest % vm ## i64
    a = rest / vm ## i64
    xline = "x " ## String
    slot = 0 ## i64
    while slot < slots
      pv = ffpsi_product_var(prim, slots, cell, slot) ## i64
      z = ffpsi_slot_inputs(slot, c, n, m, um, vm, wm, a, b, cc, vars) ## i64
      chunk = chunk + "-" + pv.to_s() + " " + vars[0].to_s() + " 0\n"
      chunk = chunk + "-" + pv.to_s() + " " + vars[1].to_s() + " 0\n"
      chunk = chunk + "-" + pv.to_s() + " " + vars[2].to_s() + " 0\n"
      chunk = chunk + pv.to_s() + " -" + vars[0].to_s() + " -" + vars[1].to_s() + " -" + vars[2].to_s() + " 0\n"
      clauses += 4
      xline = xline + pv.to_s() + " "
      slot += 1
    i2 = cc / p ## i64
    j = a % m ## i64
    i = a / m ## i64
    j2 = b / p ## i64
    k2 = b % p ## i64
    kk2 = cc % p ## i64
    want = 0 ## i64
    if j == j2 && i == i2 && k2 == kk2
      want = 1
    if want == 1
      chunk = chunk + xline + "0\n"
    else
      # Even parity: negate the first literal.
      first = ffpsi_product_var(prim, slots, cell, 0) ## i64
      neg = "x -" + first.to_s() + " " ## String
      slot = 1
      while slot < slots
        neg = neg + ffpsi_product_var(prim, slots, cell, slot).to_s() + " "
        slot += 1
      chunk = chunk + neg + "0\n"
    clauses += 1
    in_chunk += 1
    if in_chunk >= 16
      body = body + chunk
      chunk = ""
      in_chunk = 0
    cell += 1
  if in_chunk > 0
    body = body + chunk
  "p cnf " + (prim + cells * slots).to_s() + " " + clauses.to_s() + "\n" + body

args = argv()
if args.size() < 1
  << "usage: flipfleet_psi252_export_xnf <out_dir>"
  exit(2)
out_dir = args[0]
c = 7 ## i64
while c >= 4
  f = 17 - 2 * c ## i64
  path = out_dir + "/psi252_xnf_r17_c" + c.to_s() + "f" + f.to_s() + ".cnf" ## String
  text = ffpx_cell_text(c, f)
  if write_file(path, text)
    << "PSI252_XNF cell=(" + c.to_s() + "," + f.to_s() + ") path=" + path
  else
    << "PSI252_XNF_ERROR cell=(" + c.to_s() + "," + f.to_s() + ")"
  c -= 1
<< "PSI252_XNF_DONE"
