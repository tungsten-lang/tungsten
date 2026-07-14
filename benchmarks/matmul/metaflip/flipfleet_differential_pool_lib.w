# Cross-parent differential surgery for FlipFleet's rotating pool.
#
# Two exact decompositions of the same tensor differ by a tensor-zero term
# set.  This bounded CPU worker takes the most distant archive pair supplied
# by the coordinator and first performs exact bit-packed GF(2) elimination on
# the complete bounded difference.  Proper nullspace relations are combined
# and scored as hybrid splices.  The older primitive five-term circuit join is
# retained as a fallback when the complete difference exceeds the elimination
# bound or has no selectable proper relation.  Both parents and every emitted
# scheme pass independent exhaustive reconstruction.
#
# This is deliberately a single CPU child, not a GPU-width-scaled kernel.  The
# pool policy caps its logical allocation at one 32-lane quantum and admits at
# most one surgery-family child, so no campaign can launch a CPU swarm.

use flipfleet_kxor_pool_lib
use flipfleet_archive_nullspace

-> ffpd_shell_quote(text) (String)
  "'" + text.replace("'", "'\"'\"'") + "'"

-> ffpd_build_command(root, binary) (String String)
  source = "benchmarks/matmul/metaflip/flipfleet_differential_pool.w"
  "cd " + ffpd_shell_quote(root) + " && TUNGSTEN_LL_PATH=" + ffpd_shell_quote(binary + ".ll") + " bin/tungsten compile --release --native --fast --lto -o " + ffpd_shell_quote(binary) + " " + ffpd_shell_quote(source)

-> ffpd_epoch_command(root, binary, parent_a, parent_b, output, n, pool, offset, min_distance) (String String String String String i64 i64 i64 i64)
  "cd " + ffpd_shell_quote(root) + " && " + ffpd_shell_quote(binary) + " " + ffpd_shell_quote(parent_a) + " " + ffpd_shell_quote(parent_b) + " " + ffpd_shell_quote(output) + " " + n.to_s() + " " + pool.to_s() + " " + offset.to_s() + " " + min_distance.to_s()

-> ffpd_term_present(us, vs, ws, rank, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  i = 0 ## i64
  while i < rank
    if us[i] == u && vs[i] == v && ws[i] == w
      return 1
    i += 1
  0

-> ffpd_difference(au, av, aw, arank, bu, bv, bw, brank, du, dv, dw, dcap) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  drank = 0 ## i64
  i = 0 ## i64
  while i < arank && drank >= 0
    drank = ffm_toggle_plain(du, dv, dw, drank, dcap, au[i], av[i], aw[i])
    i += 1
  i = 0
  while i < brank && drank >= 0
    drank = ffm_toggle_plain(du, dv, dw, drank, dcap, bu[i], bv[i], bw[i])
    i += 1
  drank

-> ffpd_insert(keys0, keys1, keys2, keys3, used, codes, hcap, p0, p1, p2, p3, code) (i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64 i64 i64 i64) i64
  mixed = p0 ^ (p1 >> 7) ^ (p2 >> 13) ^ (p3 >> 19) ## i64
  slot = mixed & (hcap - 1) ## i64
  while used[slot] != 0
    slot = (slot + 1) & (hcap - 1)
  used[slot] = 1
  keys0[slot] = p0
  keys1[slot] = p1
  keys2[slot] = p2
  keys3[slot] = p3
  codes[slot] = code
  1

# Primary exact strategy.  Elimination itself is serial and deliberately runs
# in this one coordinator child; a discovered child is then available to all
# ordinary GPU lanes through the normal harvest/archive path.
-> ffpd_try_nullspace(state_a, state_b, output_path, n, capacity, pool, distance) (i64[] i64[] String i64 i64 i64 i64) i64
  if pool < 2
    return 0
  out_u = i64[capacity]
  out_v = i64[capacity]
  out_w = i64[capacity]
  meta = i64[9]
  combination_budget = pool * pool ## i64
  if combination_budget < 64
    combination_budget = 64
  hit = ffnd_crossover_states(state_a, state_b, n, pool, combination_budget, out_u, out_v, out_w, meta) ## i64
  if hit > 0
    candidate = i64[ffw_state_size(capacity)]
    loaded = ffw_init_terms_cap(candidate, out_u, out_v, out_w, hit, n, capacity, 93011 + distance, 0, 1, 1, 1) ## i64
    if loaded == hit && ffw_verify_best_exact(candidate, n) == 1
      dumped = ffw_dump_best(candidate, output_path) ## i64
      if dumped == hit
        << "CPU_POOL_PARENT_DIFF n=" + n.to_s() + " strategy=nullspace distance=" + distance.to_s() + " nullity=" + meta[1].to_s() + " selected=" + meta[5].to_s() + " mix=" + meta[6].to_s() + "/" + meta[7].to_s() + " rank=" + state_a[6].to_s() + "->" + hit.to_s()
        return hit
  0

-> ffpd_search(parent_a, parent_b, output_path, n, pool, offset, min_distance) (String String String i64 i64 i64 i64) i64
  if n < 3 || n > 7 || pool < 5
    return 0 - 1
  cleared = write_file(output_path, "")
  if cleared == false
    return 0 - 4
  cap = ffw_default_capacity(n) ## i64
  size = ffw_state_size(cap) ## i64
  state_a = i64[size]
  state_b = i64[size]
  arank = ffw_load_scheme_cap(state_a, parent_a, n, cap, 91001 + offset, 0, 1, 1, 1) ## i64
  brank = ffw_load_scheme_cap(state_b, parent_b, n, cap, 92003 + offset, 0, 1, 1, 1) ## i64
  if arank < 1 || brank < 1
    return 0 - 2
  if ffw_verify_best_exact(state_a, n) != 1 || ffw_verify_best_exact(state_b, n) != 1
    return 0 - 3
  au = i64[cap]
  av = i64[cap]
  aw = i64[cap]
  bu = i64[cap]
  bv = i64[cap]
  bw = i64[cap]
  z = ffw_export_best(state_a, au, av, aw) ## i64
  z = ffw_export_best(state_b, bu, bv, bw)
  dcap = cap * 2 ## i64
  du = i64[dcap]
  dv = i64[dcap]
  dw = i64[dcap]
  drank = ffpd_difference(au, av, aw, arank, bu, bv, bw, brank, du, dv, dw, dcap) ## i64
  required = min_distance ## i64
  if required < 6
    required = 6
  if drank < required
    return 0

  # Exact archive-nullspace crossover gets first refusal.  It only runs when
  # the entire symmetric difference fits `pool`; otherwise the bounded
  # primitive-five fallback below still rotates through local windows.
  nullspace_hit = ffpd_try_nullspace(state_a, state_b, output_path, n, cap, pool, drank) ## i64
  if nullspace_hit > 0
    return nullspace_hit

  count = drank ## i64
  if count > pool
    count = pool
  cu = i64[count]
  cv = i64[count]
  cw = i64[count]
  start = offset % drank ## i64
  i = 0
  while i < count
    source = (start + i) % drank ## i64
    cu[i] = du[source]
    cv[i] = dv[source]
    cw[i] = dw[source]
    i += 1

  fp0 = i64[count]
  fp1 = i64[count]
  fp2 = i64[count]
  fp3 = i64[count]
  words = i64[4]
  i = 0
  while i < count
    z = ffm_fingerprint(cu[i], cv[i], cw[i], n * n, words)
    fp0[i] = words[0]
    fp1[i] = words[1]
    fp2[i] = words[2]
    fp3[i] = words[3]
    i += 1
  pairs = count * (count - 1) / 2 ## i64
  hcap = 1 ## i64
  while hcap < pairs * 3
    hcap *= 2
  keys0 = i64[hcap]
  keys1 = i64[hcap]
  keys2 = i64[hcap]
  keys3 = i64[hcap]
  used = i64[hcap]
  codes = i64[hcap]
  left = 0 ## i64
  while left < count
    right = left + 1 ## i64
    while right < count
      z = ffpd_insert(keys0, keys1, keys2, keys3, used, codes, hcap, fp0[left] ^ fp0[right], fp1[left] ^ fp1[right], fp2[left] ^ fp2[right], fp3[left] ^ fp3[right], left * count + right + 1)
      right += 1
    left += 1

  best_indices = i64[5]
  best_projected_rank = cap + 1 ## i64
  a = 0 ## i64
  while a < count
    b = a + 1 ## i64
    while b < count
      c = b + 1 ## i64
      while c < count
        want0 = fp0[a] ^ fp0[b] ^ fp0[c] ## i64
        want1 = fp1[a] ^ fp1[b] ^ fp1[c] ## i64
        want2 = fp2[a] ^ fp2[b] ^ fp2[c] ## i64
        want3 = fp3[a] ^ fp3[b] ^ fp3[c] ## i64
        slot = (want0 ^ (want1 >> 7) ^ (want2 >> 13) ^ (want3 >> 19)) & (hcap - 1) ## i64
        scanned = 0 ## i64
        while scanned < hcap && used[slot] != 0
          if keys0[slot] == want0 && keys1[slot] == want1 && keys2[slot] == want2 && keys3[slot] == want3
            code = codes[slot] - 1 ## i64
            x = code / count ## i64
            y = code % count ## i64
            if x != a && x != b && x != c && y != a && y != b && y != c
              indices = i64[5]
              indices[0] = x
              indices[1] = y
              indices[2] = a
              indices[3] = b
              indices[4] = c
              if ffx_primitive_zero(cu, cv, cw, indices, 5, n) == 1
                overlap = 0 ## i64
                ii = 0 ## i64
                while ii < 5
                  source = indices[ii] ## i64
                  overlap += ffpd_term_present(au, av, aw, arank, cu[source], cv[source], cw[source])
                  ii += 1
                projected = arank + 5 - overlap * 2 ## i64
                if projected < best_projected_rank
                  best_projected_rank = projected
                  ii = 0
                  while ii < 5
                    best_indices[ii] = indices[ii]
                    ii += 1
          slot = (slot + 1) & (hcap - 1)
          scanned += 1
        c += 1
      b += 1
    a += 1

  if best_projected_rank <= cap
    hit = ffx_accept_identity(au, av, aw, arank, cu, cv, cw, best_indices, 5, n, output_path) ## i64
    if hit > 0
      << "CPU_POOL_PARENT_DIFF n=" + n.to_s() + " strategy=primitive5 distance=" + drank.to_s() + " pool=" + count.to_s() + " rank=" + arank.to_s() + "->" + hit.to_s()
      return hit
  0
