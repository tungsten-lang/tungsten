# Bounded enumerator for rank-neutral q=2 low-rank shears with correction
# absorption.  This is the host reference for the regular GPU search: choose a
# source pair, two logical axes, and a first carrier; derive the exact rank-1
# or rank-2 complementary matrix and find the remaining carrier if needed.

use flipfleet_shear_moves
use flipfleet_tunnel_catalyst

-> fflrs_factor_pair(source_u, source_v, source_w, shift_axis, factor_axis, correction_left, correction_right) (i64[] i64[] i64[] i64 i64 i64[] i64[]) i64
  if ffsm_axis_pair_valid(shift_axis, factor_axis) == 0
    return 0
  right_axis = 3 - shift_axis - factor_axis ## i64
  left0 = ffsm_axis_get(source_u, source_v, source_w, 0, factor_axis) ## i64
  left1 = ffsm_axis_get(source_u, source_v, source_w, 1, factor_axis) ## i64
  right0 = ffsm_axis_get(source_u, source_v, source_w, 0, right_axis) ## i64
  right1 = ffsm_axis_get(source_u, source_v, source_w, 1, right_axis) ## i64
  if left0 == left1
    merged = right0 ^ right1 ## i64
    if merged == 0
      return 0
    correction_left[0] = left0
    correction_right[0] = merged
    return 1
  if right0 == right1
    merged = left0 ^ left1 ## i64
    if merged == 0
      return 0
    correction_left[0] = merged
    correction_right[0] = right0
    return 1
  correction_left[0] = left0
  correction_right[0] = right0
  correction_left[1] = left1
  correction_right[1] = right1
  2

-> fflrs_is_one_flip(source_u, source_v, source_w, count, out_u, out_v, out_w) (i64[] i64[] i64[] i64 i64[] i64[] i64[]) i64
  trial_u = i64[count]
  trial_v = i64[count]
  trial_w = i64[count]
  code = 0 ## i64
  while code < fftc_code_count(count)
    z = fftc_copy_terms(source_u, source_v, source_w, count, trial_u, trial_v, trial_w) ## i64
    if fftc_apply_code(trial_u, trial_v, trial_w, count, code, 0 - 1) == 1
      if fftc_terms_same_set(trial_u, trial_v, trial_w, count, out_u, out_v, out_w, count) == 1
        return 1
    code += 1
  0

-> fflrs_distinct4(a, b, c, d, count) (i64 i64 i64 i64 i64) i64
  if a < 0 || b < 0 || c < 0 || a >= count || b >= count || c >= count
    return 0
  if a == b || a == c || b == c
    return 0
  if d >= 0
    if d >= count || d == a || d == b || d == c
      return 0
  1

# Returns three or four replacement terms and their source positions.  `nonce`
# rotates pair order so repeated GPU epochs do not always accept the same door.
# meta: correction rank, shift axis, factor axis, pairs tried, carriers tried,
# one-flip skips.
-> fflrs_find_pair_absorb(us, vs, ws, scheme_rank, nonce, selected, out_u, out_v, out_w, meta) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64[] i64[]) i64
  if scheme_rank < 3
    return 0
  pair_total = (scheme_rank * (scheme_rank - 1)) / 2 ## i64
  pair_step = 0 ## i64
  while pair_step < pair_total
    wanted_pair = (pair_step + nonce) % pair_total ## i64
    pair_index = 0 ## i64
    first = 0 ## i64
    second = 1 ## i64
    i = 0 ## i64
    found_pair = 0 ## i64
    while i < scheme_rank - 1 && found_pair == 0
      j = i + 1 ## i64
      while j < scheme_rank && found_pair == 0
        if pair_index == wanted_pair
          first = i
          second = j
          found_pair = 1
        pair_index += 1
        j += 1
      i += 1
    source_u = i64[2]
    source_v = i64[2]
    source_w = i64[2]
    source_u[0] = us[first]
    source_v[0] = vs[first]
    source_w[0] = ws[first]
    source_u[1] = us[second]
    source_v[1] = vs[second]
    source_w[1] = ws[second]
    axis_code = 0 ## i64
    while axis_code < 6
      axes = i64[3]
      z = ffsm_axis_code(axis_code, axes) ## i64
      shift_axis = axes[0] ## i64
      factor_axis = axes[1] ## i64
      right_axis = axes[2] ## i64
      correction_left = i64[2]
      correction_right = i64[2]
      correction_rank = fflrs_factor_pair(source_u, source_v, source_w, shift_axis, factor_axis, correction_left, correction_right) ## i64
      if correction_rank >= 1
        carrier_step = 0 ## i64
        while carrier_step < scheme_rank
          carrier0 = (carrier_step + nonce) % scheme_rank ## i64
          shift = ffsm_axis_get(us, vs, ws, carrier0, shift_axis) ## i64
          carrier0_left = ffsm_axis_get(us, vs, ws, carrier0, factor_axis) ## i64
          carrier0_right = ffsm_axis_get(us, vs, ws, carrier0, right_axis) ## i64
          carrier1 = 0 - 1 ## i64
          if shift > 0 && carrier0_left == correction_left[0] && (carrier0_right ^ correction_right[0]) != 0
            if correction_rank == 2
              scan = 0 ## i64
              while scan < scheme_rank && carrier1 < 0
                candidate = (scan + nonce) % scheme_rank ## i64
                if ffsm_axis_get(us, vs, ws, candidate, shift_axis) == shift
                  if ffsm_axis_get(us, vs, ws, candidate, factor_axis) == correction_left[1]
                    if (ffsm_axis_get(us, vs, ws, candidate, right_axis) ^ correction_right[1]) != 0
                      carrier1 = candidate
                scan += 1
            if correction_rank == 1 || carrier1 >= 0
              if fflrs_distinct4(first, second, carrier0, carrier1, scheme_rank) == 1
                total = 2 + correction_rank ## i64
                local_u = i64[4]
                local_v = i64[4]
                local_w = i64[4]
                local_u[0] = us[first]
                local_v[0] = vs[first]
                local_w[0] = ws[first]
                local_u[1] = us[second]
                local_v[1] = vs[second]
                local_w[1] = ws[second]
                local_u[2] = us[carrier0]
                local_v[2] = vs[carrier0]
                local_w[2] = ws[carrier0]
                if correction_rank == 2
                  local_u[3] = us[carrier1]
                  local_v[3] = vs[carrier1]
                  local_w[3] = ws[carrier1]
                made = ffsm_low_rank_shear_absorb(local_u, local_v, local_w, 2, correction_rank, shift_axis, factor_axis, shift, correction_left, correction_right, out_u, out_v, out_w) ## i64
                if made == total
                  if fftc_local_exact(local_u, local_v, local_w, total, out_u, out_v, out_w, total) == 1
                    if fflrs_is_one_flip(local_u, local_v, local_w, total, out_u, out_v, out_w) == 0
                      selected[0] = first
                      selected[1] = second
                      selected[2] = carrier0
                      if correction_rank == 2
                        selected[3] = carrier1
                      meta[0] = correction_rank
                      meta[1] = shift_axis
                      meta[2] = factor_axis
                      meta[3] = pair_step + 1
                      meta[4] = carrier_step + 1
                      return total
                    meta[5] = meta[5] + 1
          carrier_step += 1
      axis_code += 1
    pair_step += 1
  0
