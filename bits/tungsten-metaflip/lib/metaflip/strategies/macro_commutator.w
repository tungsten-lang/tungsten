# Rank-neutral conjugate and commutator macros over labelled ordinary flips.
#
# This is a second Rubik-style move family.  A setup flip A moves a selected
# factor into a useful coordinate frame, a connected trigger B acts there,
# and replay applies either
#
#   conjugate:  A B A
#   commutator: A B A B
#
# Ordinary labelled flips are involutions, so the repeated codes are literal
# inverse moves when they remain legal.  Every prefix is an exact rank-R
# representation; the macro hides intermediate objective debt (usually extra
# density or lost pair pressure), not tensor rank.  Search admits only an
# endpoint that makes one caller-selected structural change exactly:
# `factor(focus, axis) == target` where the source factor differed.
# The longer five-label ribbon below generalizes the setup word.  These are
# offline candidate generators: matched continuation did not justify putting
# either word in the CPU scheduler.
#
# Recipe (14 words):
#   [0] length (3 or 4), [1] setup code A, [2] trigger code B,
#   [3] focus label, [4] focus axis, [5] target factor,
#   [6] result rank, [7] endpoint distance, [8] density delta,
#   [9] pair-pressure delta, [10..11] setup labels,
#   [12..13] trigger labels.
#
# Stats (12 words):
#   [0] connected pairs examined, [1] legal setups, [2] legal triggers,
#   [3] legal conjugate closes, [4] legal commutator closes,
#   [5] changed endpoints, [6] target hits, [7] exact target hits,
#   [8] best distance, [9] best density delta,
#   [10] best pressure delta, [11] final replay exact.

use macro_holonomy

-> ffcc_clear(values, count) (i64[] i64) i64
  i = 0 ## i64
  while i < count
    values[i] = 0
    i += 1
  count

-> ffcc_pairs_touch(left, right) (i64[] i64[]) i64
  if left[0] == right[0] || left[0] == right[1] || left[1] == right[0] || left[1] == right[1]
    return 1
  0

-> ffcc_pair_has(pair, label) (i64[] i64) i64
  if pair[0] == label || pair[1] == label
    return 1
  0

-> ffcc_target_hit(us, vs, ws, focus, axis, target) (i64[] i64[] i64[] i64 i64 i64) i64
  if focus < 0 || focus >= us.size() || axis < 0 || axis > 2 || target <= 0
    return 0
  if ffmh_axis_get(us,vs,ws,focus,axis) == target
    return 1
  0

-> ffcc_distinct_terms(us, vs, ws, count) (i64[] i64[] i64[] i64) i64
  i = 0 ## i64
  while i < count
    j = i + 1 ## i64
    while j < count
      if fftc_same_term(us[i],vs[i],ws[i],us[j],vs[j],ws[j]) == 1
        return 0
      j += 1
    i += 1
  1

-> ffcc_better(distance, density_delta, pressure_delta, stats) (i64 i64 i64 i64[]) i64
  if stats[7] == 0
    return 1
  if distance > stats[8]
    return 1
  if distance < stats[8]
    return 0
  if density_delta < stats[9]
    return 1
  if density_delta > stats[9]
    return 0
  if pressure_delta > stats[10]
    return 1
  0

-> ffcc_consider(source_u, source_v, source_w, count, candidate_u, candidate_v, candidate_w, config, out_u, out_v, out_w, recipe, stats) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  length = config[0] ## i64
  code_a = config[1] ## i64
  code_b = config[2] ## i64
  focus = config[3] ## i64
  axis = config[4] ## i64
  target = config[5] ## i64
  distance = ffmh_distance(source_u,source_v,source_w,count,candidate_u,candidate_v,candidate_w,count) ## i64
  if distance < 1
    return 0
  if ffcc_distinct_terms(candidate_u,candidate_v,candidate_w,count) == 0
    return 0
  stats[5] += 1
  if ffcc_target_hit(candidate_u,candidate_v,candidate_w,focus,axis,target) == 0
    return 0
  stats[6] += 1
  if ffmh_local_exact(source_u,source_v,source_w,count,candidate_u,candidate_v,candidate_w,count) != 1
    return 0
  stats[7] += 1
  density_delta = fftc_density(candidate_u,candidate_v,candidate_w,count) - fftc_density(source_u,source_v,source_w,count) ## i64
  pressure_delta = ffmh_pair_pressure(candidate_u,candidate_v,candidate_w,count) - ffmh_pair_pressure(source_u,source_v,source_w,count) ## i64
  if ffcc_better(distance,density_delta,pressure_delta,stats) == 0
    return 1
  z = ffmh_copy(candidate_u,candidate_v,candidate_w,count,out_u,out_v,out_w) ## i64
  recipe[0] = length
  recipe[1] = code_a
  recipe[2] = code_b
  recipe[3] = focus
  recipe[4] = axis
  recipe[5] = target
  recipe[6] = count
  recipe[7] = distance
  recipe[8] = density_delta
  recipe[9] = pressure_delta
  pair = i64[3]
  z = ffmh_decode_code(code_a,count,pair)
  recipe[10] = pair[0]
  recipe[11] = pair[1]
  z = ffmh_decode_code(code_b,count,pair)
  recipe[12] = pair[0]
  recipe[13] = pair[1]
  stats[8] = distance
  stats[9] = density_delta
  stats[10] = pressure_delta
  1

# Deterministic replay with a fresh local exactness gate.  replay_meta:
# exact, changed, target hit, distance, density delta, pressure delta.
-> ffcc_replay(source_u, source_v, source_w, count, recipe, out_u, out_v, out_w, replay_meta) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[]) i64
  if count < 2 || count > 6 || recipe.size() < 14 || replay_meta.size() < 6
    return 0
  if out_u.size() < count || out_v.size() < count || out_w.size() < count
    return 0
  z = ffcc_clear(replay_meta,6) ## i64
  length = recipe[0] ## i64
  if length != 3 && length != 4
    return 0
  if recipe[6] != count
    return 0
  us = i64[count]
  vs = i64[count]
  ws = i64[count]
  z = ffmh_copy(source_u,source_v,source_w,count,us,vs,ws)
  if fftc_apply_code(us,vs,ws,count,recipe[1],0-1) != 1
    return 0
  if fftc_apply_code(us,vs,ws,count,recipe[2],0-1) != 1
    return 0
  if fftc_apply_code(us,vs,ws,count,recipe[1],0-1) != 1
    return 0
  if length == 4
    if fftc_apply_code(us,vs,ws,count,recipe[2],0-1) != 1
      return 0
  distance = ffmh_distance(source_u,source_v,source_w,count,us,vs,ws,count) ## i64
  exact = ffmh_local_exact(source_u,source_v,source_w,count,us,vs,ws,count) ## i64
  target_hit = ffcc_target_hit(us,vs,ws,recipe[3],recipe[4],recipe[5]) ## i64
  replay_meta[0] = exact
  if distance > 0
    replay_meta[1] = 1
  replay_meta[2] = target_hit
  replay_meta[3] = distance
  replay_meta[4] = fftc_density(us,vs,ws,count) - fftc_density(source_u,source_v,source_w,count)
  replay_meta[5] = ffmh_pair_pressure(us,vs,ws,count) - ffmh_pair_pressure(source_u,source_v,source_w,count)
  if exact != 1 || distance < 1 || target_hit != 1 || ffcc_distinct_terms(us,vs,ws,count) == 0
    return 0
  z = ffmh_copy(us,vs,ws,count,out_u,out_v,out_w)
  count

# Search connected A/B pairs for a caller-selected factor substitution.  Both
# A and B must touch one another, and at least one must touch the focus label;
# disjoint commuting moves and unrelated churn are excluded by construction.
-> ffcc_search_target(source_u, source_v, source_w, count, focus, axis, target, max_pairs, out_u, out_v, out_w, recipe, stats) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[] i64[]) i64
  if count < 2 || count > 6 || focus < 0 || focus >= count || axis < 0 || axis > 2 || target <= 0 || max_pairs < 1
    return 0
  if out_u.size() < count || out_v.size() < count || out_w.size() < count || recipe.size() < 14 || stats.size() < 12
    return 0
  if ffmh_axis_get(source_u,source_v,source_w,focus,axis) == target
    return 0
  z = ffcc_clear(recipe,14) ## i64
  z = ffcc_clear(stats,12)
  code_count = fftc_code_count(count) ## i64
  state_a_u = i64[count]
  state_a_v = i64[count]
  state_a_w = i64[count]
  state_ab_u = i64[count]
  state_ab_v = i64[count]
  state_ab_w = i64[count]
  state_aba_u = i64[count]
  state_aba_v = i64[count]
  state_aba_w = i64[count]
  state_abab_u = i64[count]
  state_abab_v = i64[count]
  state_abab_w = i64[count]
  pair_a = i64[3]
  pair_b = i64[3]
  config = i64[6]
  config[3] = focus
  config[4] = axis
  config[5] = target
  code_a = 0 ## i64
  while code_a < code_count && stats[0] < max_pairs
    if ffmh_decode_code(code_a,count,pair_a) == 1
      z = ffmh_copy(source_u,source_v,source_w,count,state_a_u,state_a_v,state_a_w)
      if fftc_apply_code(state_a_u,state_a_v,state_a_w,count,code_a,0-1) == 1
        stats[1] += 1
        code_b = 0 ## i64
        while code_b < code_count && stats[0] < max_pairs
          if code_b != code_a && ffmh_decode_code(code_b,count,pair_b) == 1
            connected = ffcc_pairs_touch(pair_a,pair_b) ## i64
            if ffcc_pair_has(pair_a,focus) == 0 && ffcc_pair_has(pair_b,focus) == 0
              connected = 0
            if connected == 1
              stats[0] += 1
              z = ffmh_copy(state_a_u,state_a_v,state_a_w,count,state_ab_u,state_ab_v,state_ab_w)
              if fftc_apply_code(state_ab_u,state_ab_v,state_ab_w,count,code_b,0-1) == 1
                stats[2] += 1
                z = ffmh_copy(state_ab_u,state_ab_v,state_ab_w,count,state_aba_u,state_aba_v,state_aba_w)
                if fftc_apply_code(state_aba_u,state_aba_v,state_aba_w,count,code_a,0-1) == 1
                  stats[3] += 1
                  config[0] = 3
                  config[1] = code_a
                  config[2] = code_b
                  z = ffcc_consider(source_u,source_v,source_w,count,state_aba_u,state_aba_v,state_aba_w,config,out_u,out_v,out_w,recipe,stats)
                  z = ffmh_copy(state_aba_u,state_aba_v,state_aba_w,count,state_abab_u,state_abab_v,state_abab_w)
                  if fftc_apply_code(state_abab_u,state_abab_v,state_abab_w,count,code_b,0-1) == 1
                    stats[4] += 1
                    config[0] = 4
                    z = ffcc_consider(source_u,source_v,source_w,count,state_abab_u,state_abab_v,state_abab_w,config,out_u,out_v,out_w,recipe,stats)
          code_b += 1
    code_a += 1
  if stats[7] < 1
    return 0
  replay_meta = i64[6]
  replayed = ffcc_replay(source_u,source_v,source_w,count,recipe,out_u,out_v,out_w,replay_meta) ## i64
  if replayed != count || replay_meta[0] != 1 || replay_meta[1] != 1 || replay_meta[2] != 1
    stats[11] = 0
    return 0
  stats[11] = 1
  count

# A longer setup ribbon reaches five labelled source terms before triggering:
#
#   S = A C D,  endpoint = S B S^-1 = A C D B D C A
#
# and, when legal, its commutator appends B.  Each setup edge introduces one
# fresh label while touching the existing active component; B introduces a
# fifth.  Unlike a two-flip conjugate, this can leave complete span-4 local
# reachability while never changing rank.
#
# Recipe (18 words): length, A, C, D, B, focus, axis, target, rank, distance,
# density delta, pressure delta, active-label mask, remaining words reserved.
# Stats (14 words): 0 structural triggers; 1..4 legal A/C/D/B;
# 5 inverse closes; 6 commutator closes; 7 changed endpoints;
# 8 target hits; 9 exact hits; 10 best distance; 11 replay exact;
# 12 best density delta; 13 best pair-pressure delta.

-> ffcc_pair_mask(pair) (i64[]) i64
  (1 << pair[0]) | (1 << pair[1])

-> ffcc_ribbon_step(mask, pair) (i64 i64[]) i64
  pair_mask = ffcc_pair_mask(pair) ## i64
  if (pair_mask & mask) == 0
    return 0
  if (pair_mask & (0-mask-1)) == 0
    return 0
  mask | pair_mask

-> ffcc3_better(distance, density_delta, pressure_delta, stats) (i64 i64 i64 i64[]) i64
  if stats[9] == 0
    return 1
  if distance > stats[10]
    return 1
  if distance < stats[10]
    return 0
  # Once the deliberate five-label change is made, prefer a cheaper shoulder.
  if density_delta < stats[12]
    return 1
  if density_delta > stats[12]
    return 0
  if pressure_delta > stats[13]
    return 1
  0

# This helper uses 14 stats words; the first 12 remain the public counters and
# slots 12/13 retain winner density/pressure for deterministic tie-breaking.
-> ffcc3_consider(source_u, source_v, source_w, count, candidate_u, candidate_v, candidate_w, config, out_u, out_v, out_w, recipe, stats) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  distance = ffmh_distance(source_u,source_v,source_w,count,candidate_u,candidate_v,candidate_w,count) ## i64
  if distance < 1 || ffcc_distinct_terms(candidate_u,candidate_v,candidate_w,count) == 0
    return 0
  stats[7] += 1
  focus = config[5] ## i64
  axis = config[6] ## i64
  target = config[7] ## i64
  if ffcc_target_hit(candidate_u,candidate_v,candidate_w,focus,axis,target) == 0
    return 0
  stats[8] += 1
  if ffmh_local_exact(source_u,source_v,source_w,count,candidate_u,candidate_v,candidate_w,count) != 1
    return 0
  stats[9] += 1
  density_delta = fftc_density(candidate_u,candidate_v,candidate_w,count) - fftc_density(source_u,source_v,source_w,count) ## i64
  pressure_delta = ffmh_pair_pressure(candidate_u,candidate_v,candidate_w,count) - ffmh_pair_pressure(source_u,source_v,source_w,count) ## i64
  if ffcc3_better(distance,density_delta,pressure_delta,stats) == 0
    return 1
  z = ffmh_copy(candidate_u,candidate_v,candidate_w,count,out_u,out_v,out_w) ## i64
  recipe[0] = config[0]
  recipe[1] = config[1]
  recipe[2] = config[2]
  recipe[3] = config[3]
  recipe[4] = config[4]
  recipe[5] = focus
  recipe[6] = axis
  recipe[7] = target
  recipe[8] = count
  recipe[9] = distance
  recipe[10] = density_delta
  recipe[11] = pressure_delta
  recipe[12] = config[8]
  stats[10] = distance
  stats[12] = density_delta
  stats[13] = pressure_delta
  1

-> ffcc3_replay(source_u, source_v, source_w, count, recipe, out_u, out_v, out_w, replay_meta) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[]) i64
  if count < 5 || count > 6 || recipe.size() < 18 || replay_meta.size() < 6
    return 0
  if recipe[0] != 7 && recipe[0] != 8
    return 0
  if recipe[8] != count
    return 0
  us = i64[count]
  vs = i64[count]
  ws = i64[count]
  z = ffmh_copy(source_u,source_v,source_w,count,us,vs,ws) ## i64
  step = 1 ## i64
  while step <= 4
    if fftc_apply_code(us,vs,ws,count,recipe[step],0-1) != 1
      return 0
    step += 1
  step = 3
  while step >= 1
    if fftc_apply_code(us,vs,ws,count,recipe[step],0-1) != 1
      return 0
    step -= 1
  if recipe[0] == 8
    if fftc_apply_code(us,vs,ws,count,recipe[4],0-1) != 1
      return 0
  z = ffcc_clear(replay_meta,6)
  distance = ffmh_distance(source_u,source_v,source_w,count,us,vs,ws,count) ## i64
  exact = ffmh_local_exact(source_u,source_v,source_w,count,us,vs,ws,count) ## i64
  target_hit = ffcc_target_hit(us,vs,ws,recipe[5],recipe[6],recipe[7]) ## i64
  replay_meta[0] = exact
  if distance > 0
    replay_meta[1] = 1
  replay_meta[2] = target_hit
  replay_meta[3] = distance
  replay_meta[4] = fftc_density(us,vs,ws,count) - fftc_density(source_u,source_v,source_w,count)
  replay_meta[5] = ffmh_pair_pressure(us,vs,ws,count) - ffmh_pair_pressure(source_u,source_v,source_w,count)
  if exact != 1 || distance < 1 || target_hit != 1 || ffcc_distinct_terms(us,vs,ws,count) == 0
    return 0
  z = ffmh_copy(us,vs,ws,count,out_u,out_v,out_w)
  count

-> ffcc3_search_target(source_u, source_v, source_w, count, focus, axis, target, max_sequences, out_u, out_v, out_w, recipe, stats) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[] i64[]) i64
  if count < 5 || count > 6 || focus < 0 || focus >= count || axis < 0 || axis > 2 || target <= 0 || max_sequences < 1
    return 0
  if out_u.size() < count || out_v.size() < count || out_w.size() < count || recipe.size() < 18 || stats.size() < 14
    return 0
  if ffmh_axis_get(source_u,source_v,source_w,focus,axis) == target
    return 0
  z = ffcc_clear(recipe,18) ## i64
  z = ffcc_clear(stats,14)
  code_count = fftc_code_count(count) ## i64
  s1u=i64[count]; s1v=i64[count]; s1w=i64[count]
  s2u=i64[count]; s2v=i64[count]; s2w=i64[count]
  s3u=i64[count]; s3v=i64[count]; s3w=i64[count]
  s4u=i64[count]; s4v=i64[count]; s4w=i64[count]
  s5u=i64[count]; s5v=i64[count]; s5w=i64[count]
  s6u=i64[count]; s6v=i64[count]; s6w=i64[count]
  s7u=i64[count]; s7v=i64[count]; s7w=i64[count]
  s8u=i64[count]; s8v=i64[count]; s8w=i64[count]
  pa=i64[3]; pc=i64[3]; pd=i64[3]; pb=i64[3]
  config=i64[9]
  config[5]=focus; config[6]=axis; config[7]=target
  a=0 ## i64
  while a < code_count && stats[0] < max_sequences
    if ffmh_decode_code(a,count,pa) == 1
      z=ffmh_copy(source_u,source_v,source_w,count,s1u,s1v,s1w)
      if fftc_apply_code(s1u,s1v,s1w,count,a,0-1) == 1
        stats[1]+=1
        mask1=ffcc_pair_mask(pa) ## i64
        c=0 ## i64
        while c < code_count && stats[0] < max_sequences
          if ffmh_decode_code(c,count,pc) == 1
            mask2=ffcc_ribbon_step(mask1,pc) ## i64
            if mask2 != 0
              z=ffmh_copy(s1u,s1v,s1w,count,s2u,s2v,s2w)
              if fftc_apply_code(s2u,s2v,s2w,count,c,0-1) == 1
                stats[2]+=1
                d=0 ## i64
                while d < code_count && stats[0] < max_sequences
                  if ffmh_decode_code(d,count,pd) == 1
                    mask3=ffcc_ribbon_step(mask2,pd) ## i64
                    if mask3 != 0
                      z=ffmh_copy(s2u,s2v,s2w,count,s3u,s3v,s3w)
                      if fftc_apply_code(s3u,s3v,s3w,count,d,0-1) == 1
                        stats[3]+=1
                        b=0 ## i64
                        while b < code_count && stats[0] < max_sequences
                          if ffmh_decode_code(b,count,pb) == 1
                            mask4=ffcc_ribbon_step(mask3,pb) ## i64
                            if mask4 != 0 && (mask4 & (1 << focus)) != 0
                              stats[0]+=1
                              z=ffmh_copy(s3u,s3v,s3w,count,s4u,s4v,s4w)
                              if fftc_apply_code(s4u,s4v,s4w,count,b,0-1) == 1
                                stats[4]+=1
                                z=ffmh_copy(s4u,s4v,s4w,count,s5u,s5v,s5w)
                                if fftc_apply_code(s5u,s5v,s5w,count,d,0-1) == 1
                                  if fftc_apply_code(s5u,s5v,s5w,count,c,0-1) == 1
                                    if fftc_apply_code(s5u,s5v,s5w,count,a,0-1) == 1
                                      stats[5]+=1
                                      config[0]=7; config[1]=a; config[2]=c; config[3]=d; config[4]=b; config[8]=mask4
                                      z=ffcc3_consider(source_u,source_v,source_w,count,s5u,s5v,s5w,config,out_u,out_v,out_w,recipe,stats)
                                      z=ffmh_copy(s5u,s5v,s5w,count,s8u,s8v,s8w)
                                      if fftc_apply_code(s8u,s8v,s8w,count,b,0-1) == 1
                                        stats[6]+=1
                                        config[0]=8
                                        z=ffcc3_consider(source_u,source_v,source_w,count,s8u,s8v,s8w,config,out_u,out_v,out_w,recipe,stats)
                          b+=1
                  d+=1
          c+=1
    a+=1
  if stats[9] < 1
    return 0
  replay_meta=i64[6]
  replayed=ffcc3_replay(source_u,source_v,source_w,count,recipe,out_u,out_v,out_w,replay_meta) ## i64
  if replayed != count || replay_meta[0] != 1 || replay_meta[1] != 1 || replay_meta[2] != 1
    stats[11]=0
    return 0
  stats[11]=1
  count
