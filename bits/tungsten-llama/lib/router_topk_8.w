# GPU-side router top-K + softmax. Replaces the CPU read-back of
# router_scores, the CPU top-K loop, the CPU softmax, and the CPU writes
# to the 8 per-slot constant buffers.
#
# Eliminates the per-layer CPU↔GPU sync that was breaking the
# command-buffer chain. With this, the entire pre-router + expert batch
# can encode into one big concurrent batch with one commit at the end.
#
# Single threadgroup, lane 0 only — the work is tiny (find top-8 of 128)
# and the win isn't compute parallelism, it's avoiding the host sync.
#
# Hardcoded for TOP_K=8. The 8 selected_ids buffers and one packed
# weights[8] buffer are written in place; downstream expert dispatches
# read them.

## f32[]: scores
## i32[]: sel0
## i32[]: sel1
## i32[]: sel2
## i32[]: sel3
## i32[]: sel4
## i32[]: sel5
## i32[]: sel6
## i32[]: sel7
## f32[]: weights
## i32: n_experts
@gpu fn router_topk_8(scores, sel0, sel1, sel2, sel3, sel4, sel5, sel6, sel7, weights, n_experts)
  lane = gpu.thread_index_in_simdgroup ## i32
  if lane == 0
    # Top-8 via repeated argmax with -inf masking. Stores raw logits in
    # weights[0..7]; we softmax them in the second pass below.
    i = 0 ## i32
    while i < 8
      best_v = ~-1000000000.0 ## f32
      best_i = -1 ## i32
      j = 0 ## i32
      while j < n_experts
        v = scores[j] ## f32
        if v > best_v
          best_v = v
          best_i = j
        j = j + 1
      if i == 0
        sel0[0] = best_i
      if i == 1
        sel1[0] = best_i
      if i == 2
        sel2[0] = best_i
      if i == 3
        sel3[0] = best_i
      if i == 4
        sel4[0] = best_i
      if i == 5
        sel5[0] = best_i
      if i == 6
        sel6[0] = best_i
      if i == 7
        sel7[0] = best_i
      weights[i] = best_v
      scores[best_i] = ~-1000000000.0
      i = i + 1
    # Softmax over the 8 picks. weights[0] is the highest by construction
    # (we picked them in descending order), so subtract it for stability.
    max_v = weights[0] ## f32
    sum_e = 0.0 ## f32
    i = 0
    while i < 8
      e = exp(weights[i] - max_v) ## f32
      weights[i] = e
      sum_e = sum_e + e
      i = i + 1
    inv_s = ~1.0 / sum_e ## f32
    i = 0
    while i < 8
      weights[i] = weights[i] * inv_s
      i = i + 1
