// DIAGNOSTIC ONLY: rank of the target's token in the MTP head's draft
// distribution.
//
// Speculative decoding accepts a draft only when the head's argmax equals the
// target's argmax, so the accept rate measures P(rank == 0) and nothing else.
// It cannot tell you whether a rejected draft was a near miss (target was the
// head's second choice) or a blow-out (target was nowhere). That distinction
// is exactly what decides whether TREE drafting can pay: a k-branch tree
// spends its extra verified rows on the head's next-best candidates, so its
// ceiling is P(rank < k), and it is worth building only if the coverage curve
// rises steeply past rank 0.
//
// Counting strictly-greater logits gives the exact rank in one pass, and the
// whole curve rather than a single top-2 probe. Ties are broken the same way
// the selector breaks them (lowest index wins), so rank 0 here agrees with an
// accepted draft.
//
// Writes result[0] = rank, or -1 when the target lies outside the compact
// draft vocabulary (structurally unproposable, which is its own finding).

#include <metal_stdlib>
using namespace metal;

[[max_total_threads_per_threadgroup(32)]]
kernel void mtp_draft_target_rank(
  device const float *prefix_logits  [[buffer(0)]],
  device const float *control_logits [[buffer(1)]],
  device int         *result         [[buffer(2)]],
  constant int &prefix_count         [[buffer(3)]],
  constant int &control_count        [[buffer(4)]],
  constant int &control_start        [[buffer(5)]],
  constant int &target_id            [[buffer(6)]],
  uint lane [[thread_index_in_simdgroup]]) {

  // Locate the target's own logit, or declare it unproposable.
  bool in_prefix = target_id >= 0 && target_id < prefix_count;
  bool in_control = target_id >= control_start &&
                    target_id < control_start + control_count;
  if (!in_prefix && !in_control) {
    if (lane == 0) result[0] = -1;
    return;
  }
  const float target_logit = in_prefix
    ? prefix_logits[target_id]
    : control_logits[target_id - control_start];

  // Rank = number of candidates strictly better than the target. Ties are
  // resolved by index so this matches the selector's lowest-index-wins rule:
  // an equal logit at a LOWER index outranks the target, one at a higher
  // index does not.
  int local_better = 0;
  for (int i = int(lane); i < prefix_count; i += 32) {
    const float v = prefix_logits[i];
    if (v > target_logit) local_better += 1;
    else if (v == target_logit && i < target_id) local_better += 1;
  }
  for (int i = int(lane); i < control_count; i += 32) {
    const float v = control_logits[i];
    const int id = control_start + i;
    if (v > target_logit) local_better += 1;
    else if (v == target_logit && id < target_id) local_better += 1;
  }

  const int rank = simd_sum(local_better);
  if (lane == 0) result[0] = rank;
}
