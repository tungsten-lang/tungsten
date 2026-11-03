
-> wassat_byte_abs(x) (i64) i64
  x < 0 ? -x : x

-> wassat_byte_poll(m, stop, deadline) (i64[] i64[] i64) i64
  m[12] += 1
  if wassat_stop_load(stop) != 0
    m[11] = 1
  elsif deadline > 0 && clock_ms() >= deadline
    m[11] = 2
  m[11]

# Exact defining clauses; every accepted output is unique, and every other
# original clause remains an assertion. Width and work bounds only cause misses.
# program stride8: kind,signed output,input count,input offset,truth,start,end,0.
-> wassat_byte_decode(lits, offs, lens, nv, nc, program, inputs, units, residual, m, stop, deadline) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64[] i64[] i64[] i64) i64
  ci = 0; used = 0
  scratch = i64[64]
  while ci < nc
    return 0 if (ci & 1023) == 0 && wassat_byte_poll(m, stop, deadline) != 0
    m[3] = ci + 1
    n = lens[ci]; off = offs[ci]
    return 0 if n < 1 || n > 65 || off < 0 || off + n > lits.size
    out = 0; j = 0
    while j < n
      v = wassat_byte_abs(lits[off + j])
      return 0 if v < 1 || v > nv
      out = v if v > out
      j += 1
    if n == 1
      units[m[1]] = lits[off]; m[1] += 1; ci += 1
      next
    base = 8 * out
    if program[base] != 0
      return 0 if m[2] >= residual.size
      residual[m[2]] = ci; m[2] += 1; ci += 1
      next
    kind = 0; y = out; nf = 0; q = ci; truth = 0
    if n == 2
      ol = wassat_byte_abs(lits[off]) == out ? lits[off] : lits[off + 1]
      y = -ol
      good = 1
      while q < nc && lens[q] == 2 && nf < 64 && good == 1
        p = offs[q]; a = lits[p]; b = lits[p + 1]
        if a == ol
          a = b
        elsif b != ol
          break
        if wassat_byte_abs(a) >= out
          break
        k = 0
        while k < nf
          good = 0 if scratch[k] == a
          k += 1
        break if good == 0
        scratch[nf] = a; nf += 1; q += 1
      if good == 1 && nf > 0 && q < nc && lens[q] == nf + 1
        p = offs[q]; j = 0; found = 0
        while j < lens[q] && good == 1
          l = lits[p + j]
          if l == y
            found += 1
          else
            count = 0; k = 0
            while k < nf
              count += 1 if scratch[k] == -l
              k += 1
            good = 0 if count != 1
          k = 0
          while k < j
            good = 0 if lits[p + k] == l
            k += 1
          j += 1
        if good == 1 && found == 1
          kind = 1; q += 1
    if kind == 0 && n == 3 && ci + 4 <= nc
      a = wassat_byte_abs(lits[off]); b = wassat_byte_abs(lits[off + 1]); c = wassat_byte_abs(lits[off + 2])
      if a > b
        tmp = a; a = b; b = tmp
      if b > c
        tmp = b; b = c; c = tmp
      if a > b
        tmp = a; a = b; b = tmp
      if a != b && b != c
        seen = 0; parity = -1; good = 1; q = ci
        while q < ci + 4 && good == 1
          good = 0 if lens[q] != 3
          pat = 0; vars = 0; j = 0
          while j < lens[q] && good == 1
            l = lits[offs[q] + j]; v = wassat_byte_abs(l)
            k = v == a ? 0 : v == b ? 1 : v == c ? 2 : -1
            if k < 0
              good = 0
            else
              good = 0 if (vars & (1 << k)) != 0
              vars |= 1 << k
              pat |= 1 << k if l > 0
            j += 1
          pp = (pat & 1) ^ ((pat >> 1) & 1) ^ ((pat >> 2) & 1)
          parity = pp if parity < 0
          good = 0 if vars != 7 || pp != parity || (seen & (1 << pat)) != 0
          seen |= 1 << pat
          q += 1
        if good == 1
          kind = 2; y = out; nf = 2; scratch[0] = a; scratch[1] = b
          truth = parity == 0 ? 6 : 9
    if kind == 0
      nf = 0; q = ci; valid = 0; good = 1
      while q < nc && q - ci < 32 && good == 1 && valid == 0
        p = offs[q]; j = 0; found = 0
        while j < lens[q] && good == 1
          v = wassat_byte_abs(lits[p + j])
          if v == out
            found = 1
          elsif v > out || v < 1
            good = 0
          else
            k = 0
            while k < nf && scratch[k] != v
              k += 1
            if k == nf
              if nf == 4
                good = 0
              else
                scratch[nf] = v; nf += 1
          j += 1
        good = 0 if found == 0
        break if good == 0
        valid = 1; truth = 0; mask = 0
        while mask < (1 << nf) && valid == 1
          allowed = 0; bit = 0
          while bit < 2
            ok = 1; rc = ci
            while rc <= q && ok == 1
              hit = 0; j = 0
              while j < lens[rc]
                l = lits[offs[rc] + j]; v = wassat_byte_abs(l); val = bit
                if v != out
                  k = 0
                  while k < nf && scratch[k] != v
                    k += 1
                  val = (mask >> k) & 1
                hit = 1 if val == (l > 0 ? 1 : 0)
                j += 1; m[7] += 1
              ok = 0 if hit == 0
              rc += 1
            if ok == 1
              allowed += 1
              truth |= bit << mask
            bit += 1
          valid = 0 if allowed != 1
          mask += 1
        q += 1
      if valid == 1 && good == 1
        kind = 3; y = out
    return 0 if kind == 0 || used + nf > inputs.size
    program[base] = kind; program[base + 1] = y
    program[base + 2] = nf; program[base + 3] = used
    program[base + 4] = truth; program[base + 5] = ci; program[base + 6] = q
    j = 0
    while j < nf
      inputs[used] = scratch[j]; used += 1; j += 1
    m[0] += 1; m[4] = used; m[6] += q - ci; ci = q
  m[3] = 0
  1

-> wassat_byte_program_hash(program, inputs, units, residual, nv, m) (i64[] i64[] i64[] i64[] i64 i64[]) i64
  h = 0; v = 1
  while v <= nv
    b = 8 * v
    if program[b] > 0
      j = 0
      while j < 7
        h = ((h * 48271) ^ program[b + j]) & 2147483647; j += 1
      j = 0
      while j < program[b + 2]
        h = ((h * 48271) ^ inputs[program[b + 3] + j]) & 2147483647; j += 1
    v += 1
  j = 0
  while j < m[1]
    h = ((h * 48271) ^ units[j]) & 2147483647; j += 1
  j = 0
  while j < m[2]
    h = ((h * 48271) ^ residual[j]) & 2147483647; j += 1
  h

# Alternate sweep direction to close implications pointing back toward earlier
# gate definitions; each unit still comes from an original clause.
-> wassat_byte_root_alternate(lits, offs, lens, nc, values, passes, m, stop, deadline) (i64[] i64[] i64[] i64 i8[] i64 i64[] i64[] i64) i64
  pass = 0
  while pass < passes
    changed = 0; ci = (pass & 1) == 0 ? 0 : nc - 1
    step = (pass & 1) == 0 ? 1 : -1
    while ci >= 0 && ci < nc
      return 0 if wassat_cover_tick(m, stop, deadline) != 0
      m[5] += 1
      j = 0; unit = 0; unknown = 0; sat = 0
      while j < lens[ci] && sat == 0
        l = lits[offs[ci] + j]; v = wassat_byte_abs(l); value = values[v]
        if value == (l < 0 ? -1 : 1)
          sat = 1
        elsif value == 0
          unit = l; unknown += 1
        j += 1
      if sat == 0
        if unknown == 0
          m[9] = ci + 1
          return -1
        if unknown == 1
          values[wassat_byte_abs(unit)] = unit < 0 ? -1 : 1
          m[7] += 1; changed = 1
      ci += step
    return 0 if changed == 0
    pass += 1
  0

use congruence
use tables
use linear
use expressions
