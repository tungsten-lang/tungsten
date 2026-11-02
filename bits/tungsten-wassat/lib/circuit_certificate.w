# Check the functional relation assumed by the bounded circuit refuters.
# Positive-output clauses give the evaluator's formula for each output.
# Negative-output clauses must rule out the other output for every satisfiable
# input assignment. Merely having both clause polarities does not prove this.
#
# A partial relation is safe: input rows admitting neither output may create
# spurious evaluator paths, which can only prevent a refutation. Rows admitting
# both outputs are unsafe and must fall through to ordinary solving.
# work: input clauses scanned, gate checks, truth-table batches, literal visits, miss code.
# Miss codes: 1 bad free input, 2 repeated output, 3 uncovered input,
# 4 support exceeds the bounded check, 5 both output values remain possible.
-> wassat_circuit_certificate_miss(work, reason) (i64[] i64) bool
  work[4] = reason
  false

# Removing the output literal from every defining clause describes the input
# rows on which BOTH output values are allowed. A unit refutation of this
# conjunction proves functionality without enumerating a large truth table
# (for example, a wide AND or OR). Incomplete propagation only declines.
-> wassat_circuit_relation_unit_refuted?(fla, fcs, fcl, next_clause, polarity,
                                        assign, inputs, count, first_clause,
                                        output, values, work) (i64[] i64[] i64[] i64[] i8[] i64[] i64[] i64 i64 i64 i64[] i64[]) bool
  i = 0
  while i < count
    values[i] = 0
    i += 1
  visits = 0
  changed = true
  while changed
    changed = false
    ci = first_clause
    while ci >= 0
      if polarity[ci] != 0
        unset = 0
        last_slot = 0
        last_sign = 0
        satisfied = false
        j = 0
        while j < fcl[ci] && !satisfied
          visits += 1
          work[3] += 1
          return false if visits > 65536
          l = fla[fcs[ci] + j]
          v = l < 0 ? 0 - l : l
          if v != output && assign[v] == 0
            slot = 0
            while slot < count && inputs[slot] != v
              slot += 1
            return false if slot == count
            sign = l > 0 ? 1 : -1
            if values[slot] == sign
              satisfied = true
            elsif values[slot] == 0
              unset += 1
              last_slot = slot
              last_sign = sign
          j += 1
        unless satisfied
          return true if unset == 0
          if unset == 1
            values[last_slot] = last_sign
            changed = true
      ci = next_clause[ci]
  false

-> wassat_circuit_prefix_supported?(fla, fcs, fcl, ncl, assign, free_vars,
                                    n_free, first, last, work) (i64[] i64[] i64[] i64 i64[] i64[] i64 i64 i64 i64[]) bool
  full = -1 ## i64
  i = 0
  while i < 5
    work[i] = 0
    i += 1
  return wassat_circuit_certificate_miss(work, 1) if first < 1 || last < first || n_free < 0 || n_free > 16
  head = i64[last + 1]
  next_clause = i64[ncl]
  polarity = i8[ncl]
  known = i8[last + 1]
  v = 1
  while v <= last
    head[v] = -1
    known[v] = 1 if assign[v] != 0
    v += 1
  i = 0
  while i < n_free
    v = free_vars[i]
    return wassat_circuit_certificate_miss(work, 1) if v < 1 || v > last || known[v] != 0
    known[v] = 1
    i += 1

  ci = 0
  while ci < ncl
    work[0] += 1
    if fcl[ci] > 1
      off = fcs[ci]
      m = 0
      j = 0
      while j < fcl[ci]
        l = fla[off + j]
        v = l < 0 ? 0 - l : l
        m = v if v > m
        work[3] += 1
        j += 1
      if m >= first && m <= last
        next_clause[ci] = head[m]
        head[m] = ci
    ci += 1

  inputs = i64[128]
  values = i64[128]
  masks = i64[6]
  masks[0] = -6148914691236517206 ## i64
  masks[1] = -3689348814741910324 ## i64
  masks[2] = -1085102592571150096 ## i64
  masks[3] = -71777214294589696 ## i64
  masks[4] = -281470681808896 ## i64
  masks[5] = -4294967296 ## i64
  m = first
  while m <= last
    if head[m] >= 0
      count = 0
      ci = head[m]
      while ci >= 0
        off = fcs[ci]
        outputs = 0
        sign = 0
        satisfied = false
        j = 0
        while j < fcl[ci]
          l = fla[off + j]
          v = l < 0 ? 0 - l : l
          if v == m
            outputs += 1
            sign = l > 0 ? 1 : -1
          elsif (l > 0 && assign[v] == 1) || (l < 0 && assign[v] == -1)
            satisfied = true
          work[3] += 1
          j += 1
        return wassat_circuit_certificate_miss(work, 2) unless outputs == 1
        unless satisfied
          polarity[ci] = sign
          j = 0
          while j < fcl[ci]
            l = fla[off + j]
            v = l < 0 ? 0 - l : l
            if v != m && assign[v] == 0
              # Only positive-output clauses are evaluated. Other inputs
              # are universally quantified by the relation check below.
              if sign > 0 && known[v] == 0
                wassat_prof_note("circuit.certificate uncovered_output=[m] input=[v]")
                return wassat_circuit_certificate_miss(work, 3)
              slot = 0
              while slot < count && inputs[slot] != v
                slot += 1
              if slot == count
                return wassat_circuit_certificate_miss(work, 4) if count >= 128
                inputs[count] = v
                count += 1
            work[3] += 1
            j += 1
        ci = next_clause[ci]

      work[1] += 1
      batches = 1
      batches = 1 << (count - 6) if count > 6 && count <= 8
      if count > 8
        supported = wassat_circuit_relation_unit_refuted?(fla, fcs, fcl,
          next_clause, polarity, assign, inputs, count, head[m], m, values, work)
        return wassat_circuit_certificate_miss(work, 4) unless supported
        batches = 0
      batch = 0
      while batch < batches
        work[2] += 1
        i = 0
        while i < count
          values[i] = i < 6 ? masks[i] : (((batch >> (i - 6)) & 1) != 0 ? full : 0)
          i += 1
        zero_ok = -1 ## i64
        one_ok = -1 ## i64
        ci = head[m]
        while ci >= 0
          if polarity[ci] != 0
            clause_bits = 0 ## i64
            off = fcs[ci]
            j = 0
            while j < fcl[ci]
              l = fla[off + j]
              v = l < 0 ? 0 - l : l
              if v != m && assign[v] == 0
                slot = 0
                while slot < count && inputs[slot] != v
                  slot += 1
                return wassat_circuit_certificate_miss(work, 3) if slot == count
                bits = values[slot] ## i64
                bits = full ^ bits if l < 0
                clause_bits = clause_bits | bits
              work[3] += 1
              j += 1
            if polarity[ci] > 0
              zero_ok = zero_ok & clause_bits
            else
              one_ok = one_ok & clause_bits
          ci = next_clause[ci]
        return wassat_circuit_certificate_miss(work, 5) if (zero_ok & one_ok) != 0
        batch += 1
      known[m] = 1
    m += 1
  true
