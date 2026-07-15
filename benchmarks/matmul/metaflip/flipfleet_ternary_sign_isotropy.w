use flipfleet_ternary_worker

# Diagonal sign isotropies for strict {-1,0,1} matrix-multiplication schemes.
#
# Choose signs d_i, e_j, f_k in {-1,+1} for the three physical matrix
# indices.  Apply d_i e_j to A[i,j], e_j f_k to B[j,k], and d_i f_k to
# C[i,k] in every rank-one term.  Each target coefficient A[i,j]B[j,k]C[i,k]
# receives the square d_i^2 e_j^2 f_k^2, so the complete multiplication
# tensor is unchanged.  This endpoint is always strict ternary and preserves
# rank, support, and density.  It is a genuinely signed symmetry: modulo two,
# -1 == +1 and the entire action is literally the identity.
#
# The move is kept in a separate audit module.  Unlike a non-diagonal index
# shear it is an alphabet automorphism, so it may only re-label the local move
# graph.  The matched benchmark decides whether canonical gauge choices turn
# that re-labeling into useful practical diversification.

-> fftsi_factor_flip_mask(n, rows, columns) (i64 i64 i64) i64
  mask = 0 ## i64
  row = 0 ## i64
  while row < n
    column = 0 ## i64
    while column < n
      row_flip = (rows >> row) & 1 ## i64
      column_flip = (columns >> column) & 1 ## i64
      if row_flip != column_flip
        mask = mask | (1 << (row * n + column))
      column += 1
    row += 1
  mask

# Swap the positive/negative membership of every selected coefficient.  The
# result is returned in the worker scratch words 44/45.
-> fftsi_flip_vector(st, positive,negative, mask) (i64[] i64 i64 i64) i64
  selected = mask & st[30] ## i64
  keep = st[30] ^ selected ## i64
  st[44] = (positive & keep) | (negative & selected)
  st[45] = (negative & keep) | (positive & selected)
  1

# Apply a complete diagonal sign conjugation.  index_i/index_j/index_k are
# n-bit masks identifying physical coordinates whose sign is -1.  The map is
# an involution.  A zero return means the requested action is the identity on
# all three factor spaces; -1 denotes malformed input.
-> fftsi_raw(st, index_i,index_j,index_k) (i64[] i64 i64 i64) i64
  if fft_valid(st) == 0 || st[5] < 1
    return 0 - 1
  legal = (1 << st[2]) - 1 ## i64
  if (index_i & legal) != index_i || (index_j & legal) != index_j || (index_k & legal) != index_k
    return 0 - 1

  masks = i64[3]
  masks[0] = fftsi_factor_flip_mask(st[2],index_i,index_j)
  masks[1] = fftsi_factor_flip_mask(st[2],index_j,index_k)
  masks[2] = fftsi_factor_flip_mask(st[2],index_i,index_k)
  if (masks[0] | masks[1] | masks[2]) == 0
    return 0

  slot = 0 ## i64
  while slot < st[5]
    factor = 0 ## i64
    while factor < 3
      base = 32 + 2 * factor ## i64
      z = fftsi_flip_vector(st,st[st[base]+slot],st[st[base+1]+slot],masks[factor]) ## i64
      st[st[base]+slot] = st[44]
      st[st[base+1]+slot] = st[45]
      factor += 1
    z = fft_canonicalize_slot(st,slot)
    slot += 1
  # Support is invariant, hence so is density.  Recompute rather than trusting
  # the caller so this helper is safe in standalone audits.
  st[20] = fft_current_density(st)
  1

# A deterministic family used by the matched benchmark.  It covers all three
# one-index actions and three coupled actions without enumerating the full
# 2^(3n-1) symmetry orbit.  Results are returned in masks[0..2].
-> fftsi_trial_masks(n, trial, masks) (i64 i64 i64[]) i64
  coordinate = trial % n ## i64
  other = (trial / n + coordinate + 1) % n ## i64
  masks[0] = 0
  masks[1] = 0
  masks[2] = 0
  mode = trial % 6 ## i64
  if mode == 0
    masks[0] = 1 << coordinate
  if mode == 1
    masks[1] = 1 << coordinate
  if mode == 2
    masks[2] = 1 << coordinate
  if mode == 3
    masks[0] = 1 << coordinate
    masks[1] = 1 << other
  if mode == 4
    masks[1] = 1 << coordinate
    masks[2] = 1 << other
  if mode == 5
    masks[0] = 1 << coordinate
    masks[1] = 1 << other
    masks[2] = 1 << ((other + 1) % n)
  1
