# Bit-parallel simulation proposes signal equivalences; it proves nothing.
# Complements share a normalized signature. Hash collisions are checked against
# every word, and every nominated pair must subsequently pass both native SAT
# queries in circuit_cones.w before it may be used as an alias.

use circuit_cones

-> wassat_cone_random(state) (i64[]) i64
  x = state[0]
  x = x ^ (x << 13) ## i64
  x = x ^ ((x >> 7) & 144115188075855871) ## i64
  x = x ^ (x << 17) ## i64
  state[0] = x
  x

-> wassat_cone_simulate(ga, gb, inputs, last, words, sig, state, deadline, random_words = 0, stop = nil) (i64[] i64[] i64 i64 i64 i64[] i64[] i64 i64 i64[]) i64
  return 0 if wassat_cone_stopped(stop, deadline)
  v = 1 ## i64
  while v <= inputs
    j = 0 ## i64
    while j < words
      if random_words == 0 || j < random_words
        sig[v * words + j] = wassat_cone_random(state)
      else
        sig[v * words + j] = sig[v * words + j % random_words]
      j += 1
    v += 1
    return 0 if (v & 1023) == 0 && wassat_cone_stopped(stop, deadline)
  while v <= last
    a = ga[v]
    b = gb[v]
    av = wassat_cone_abs(a)
    bv = wassat_cone_abs(b)
    an = a < 0 ? -1 : 0
    bn = b < 0 ? -1 : 0
    j = 0
    while j < words
      sig[v * words + j] = (sig[av * words + j] ^ an) & (sig[bv * words + j] ^ bn)
      j += 1
    v += 1
    return 0 if (v & 1023) == 0 && wassat_cone_stopped(stop, deadline)
  1

-> wassat_cone_signature_hash(sig, off, words, flip) (i64[] i64 i64 i64) i64
  h = 1469598103934665603 ## i64
  j = 0 ## i64
  while j < words
    h = (h ^ (sig[off + j] ^ flip)) * 1099511628211 ## i64
    j += 1
  h

-> wassat_cone_signature_equal(sig, a, b, words, af, bf) (i64[] i64 i64 i64 i64 i64) bool
  j = 0 ## i64
  while j < words
    return false if (sig[a * words + j] ^ af) != (sig[b * words + j] ^ bf)
    j += 1
  true

# st: 0 nominee count, 1 table probes, 2 constant signatures, 3 stopped.
-> wassat_cone_nominate(sig, inputs, last, words, table, left, right, st, deadline, stop = nil) (i64[] i64 i64 i64 i64[] i64[] i64[] i64[] i64 i64[]) i64
  if wassat_cone_stopped(stop, deadline)
    st[3] = 1
    return 0
  mask = table.size - 1 ## i64
  v = 1 ## i64
  while v <= last
    off = v * words ## i64
    flip = (sig[off] & 1) == 0 ? 0 : -1
    zero = true
    one = true
    j = 0 ## i64
    while j < words
      zero = false if sig[off + j] != 0
      one = false if sig[off + j] != -1
      j += 1
    if zero || one
      st[2] += 1
    else
      slot = wassat_cone_signature_hash(sig, off, words, flip) & mask ## i64
      steps = 0 ## i64
      while table[slot] != 0
        prev = table[slot]
        pf = (sig[prev * words] & 1) == 0 ? 0 : -1
        st[1] += 1
        if wassat_cone_signature_equal(sig, v, prev, words, flip, pf)
          if v > inputs
            count = st[0]
            return 0 if count >= left.size || count >= right.size
            left[count] = v
            right[count] = flip == pf ? prev : 0 - prev
            st[0] = count + 1
          break
        slot = (slot + 1) & mask
        steps += 1
        return 0 if steps >= table.size
      table[slot] = v if table[slot] == 0
    v += 1
    if (v & 1023) == 0 && wassat_cone_stopped(stop, deadline)
      st[3] = 1
      return 0
  1

-> wassat_cone_sim_candidates(decoded, words = 16, deadline = 0, random_words = 0, stop = nil)
  miss = { "recognized": false, "stopped": false, "count": 0 }
  return miss unless decoded["recognized"]
  return miss if words < 1 || words > 32 || random_words < 0 || random_words > words
  if wassat_cone_stopped(stop, deadline)
    miss["stopped"] = true
    return miss
  last = decoded["last_gate"]
  size = 8
  while size < 2 * (last + 1)
    size *= 2
  sig = i64[(last + 1) * words]
  table = i64[size]
  left = i64[decoded["gates"]]
  right = i64[decoded["gates"]]
  state = i64[1]
  state[0] = 88172645463325252
  ok = wassat_cone_simulate(decoded["ga"], decoded["gb"], decoded["inputs"], last, words, sig, state, deadline, random_words, stop)
  if ok == 0
    miss["stopped"] = true
    return miss
  stats = i64[4]
  ok = wassat_cone_nominate(sig, decoded["inputs"], last, words, table, left, right, stats, deadline, stop)
  if ok == 0
    miss["stopped"] = stats[3] != 0
    return miss
  { "recognized": true, "stopped": false, "count": stats[0],
    "left": left, "right": right, "signatures": sig, "words": words,
    "table": table, "refinements": 0, "counterexamples": 0,
    "probes": stats[1], "constants": stats[2] }

# Cache only disproved canonical signed pairs. This is a search filter, never
# an alias or proof step. The decoder bounds variable IDs below 2^21, so a
# positive left variable and signed right literal fit injectively in 43 bits.
-> wassat_cone_known_difference(table, y, rhs, remember = false) (i64[] i64 i64 bool) bool
  key = (y << 22) | (2 * wassat_cone_abs(rhs) + (rhs < 0 ? 1 : 0)) ## i64
  mixed = (key ^ (key >> 21)) * 1099511628211 ## i64
  mask = table.size - 1 ## i64
  slot = mixed & mask ## i64
  steps = 0 ## i64
  while table[slot] != 0
    return true if table[slot] == key
    slot = (slot + 1) & mask
    steps += 1
    return false if steps >= table.size
  table[slot] = key if remember
  false

-> wassat_cone_clear_table(table, deadline, stop = nil) (i64[] i64 i64[]) bool
  return false if wassat_cone_stopped(stop, deadline)
  i = 0 ## i64
  while i < table.size
    table[i] = 0
    i += 1
    return false if (i & 4095) == 0 && wassat_cone_stopped(stop, deadline)
  true

-> wassat_cone_sim_word(ga, gb, inputs, last, words, sig, word, deadline, stop = nil) (i64[] i64[] i64 i64 i64 i64[] i64 i64 i64[]) bool
  return false if wassat_cone_stopped(stop, deadline)
  v = inputs + 1 ## i64
  while v <= last
    a = ga[v]; b = gb[v]
    an = a < 0 ? -1 : 0
    bn = b < 0 ? -1 : 0
    sig[v * words + word] = (sig[wassat_cone_abs(a) * words + word] ^ an) & (sig[wassat_cone_abs(b) * words + word] ^ bn)
    v += 1
    return false if (v & 1023) == 0 && wassat_cone_stopped(stop, deadline)
  true

# Pack up to 64 actual local SAT models into one reserved signature word.
# Missing primary inputs are false. Reevaluate the ORIGINAL complete network,
# and verify that each resulting pattern really separates the queried pair.
# A counterexample never becomes an axiom or a refutation.
-> wassat_cone_refine(decoded, nominees, patterns, left, right, word, deadline = 0, stop = nil)
  return false if wassat_cone_stopped(stop, deadline)
  n = patterns.size
  return false if n == 0 || n > 64 || left.size != n || right.size != n
  words = nominees["words"]
  return false if word < 0 || word >= words
  sig = nominees["signatures"] ## i64[]
  inputs = decoded["inputs"]
  last = decoded["last_gate"]
  i = 1
  while i <= inputs
    sig[i * words + word] = 0
    i += 1
  i = 0
  while i < n
    bit = 1 << i ## i64
    values = patterns[i]
    j = 0
    while j < values.size
      v = values[j]
      return false if v < 1 || v > inputs
      sig[v * words + word] = sig[v * words + word] | bit
      j += 1
    i += 1
  return false unless wassat_cone_sim_word(decoded["ga"], decoded["gb"], inputs, last, words, sig, word, deadline, stop)
  i = 0
  while i < n
    a = left[i]; b = right[i]
    av = wassat_cone_abs(a); bv = wassat_cone_abs(b)
    return false if av < 1 || bv < 1 || av > last || bv > last
    aa = (sig[av * words + word] >> i) & 1
    bb = (sig[bv * words + word] >> i) & 1
    aa = aa ^ 1 if a < 0
    bb = bb ^ 1 if b < 0
    return false if aa == bb
    i += 1
  return false unless wassat_cone_clear_table(nominees["table"], deadline, stop)
  stats = i64[4]
  ok = wassat_cone_nominate(sig, inputs, last, words, nominees["table"], nominees["left"], nominees["right"], stats, deadline, stop)
  return false if ok == 0
  nominees["count"] = stats[0]
  nominees["probes"] += stats[1]
  nominees["refinements"] += 1
  nominees["counterexamples"] += n
  true
