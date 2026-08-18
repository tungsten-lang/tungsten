// Two-stage draft-vocabulary argmax.
//
// mtp_compact_draft_select scans 98,304 + 26 logits with ONE 32-thread
// simdgroup, and does it TWICE -- once for the maximum, once to recover its
// index. That is the same shape as the full-vocabulary argmax this repo already
// replaced (measured 1,648 us -> 3.92 us by switching to 1024-logit tiles); it
// was simply never applied to the draft path, where it costs a large fraction
// of the MTP head step. The head step is what caps draft depth, so this is not
// a micro-optimisation.
//
// Semantics are preserved exactly, including tie-breaking. The two logit
// buffers are treated as one logical index space:
//     [0, prefix_count)                    -> prefix_logits[i],  id = i
//     [prefix_count, prefix+control)       -> control_logits[j], id = control_start + j
// Ties resolve to the LOWEST id, and because every control id (>= 248,044)
// exceeds every prefix id (< 98,304), lowest-id order agrees with logical index
// order -- so a single (value, id) reduction reproduces the original result.

#include <metal_stdlib>
using namespace metal;

constant int DRAFT_TILE = 1024;

inline bool draft_better(float cv, int ci, float bv, int bi) {
  if (cv > bv) return true;
  if (cv < bv) return false;
  return ci < bi;
}

// Fetch logical element `idx` as (value, id).
inline void draft_fetch(
  device const float *prefix_logits,
  device const float *control_logits,
  int idx, int prefix_count, int control_start,
  thread float &v, thread int &id
) {
  if (idx < prefix_count) {
    v = prefix_logits[idx];
    id = idx;
  } else {
    const int j = idx - prefix_count;
    v = control_logits[j];
    id = control_start + j;
  }
}

[[max_total_threads_per_threadgroup(256)]]
kernel void mtp_draft_select_stage1(
  device const float *prefix_logits  [[buffer(0)]],
  device const float *control_logits [[buffer(1)]],
  device float       *partial_vals   [[buffer(2)]],
  device int         *partial_ids    [[buffer(3)]],
  constant int &prefix_count         [[buffer(4)]],
  constant int &control_count        [[buffer(5)]],
  constant int &control_start        [[buffer(6)]],
  uint tg   [[threadgroup_position_in_grid]],
  uint lid  [[thread_position_in_threadgroup]],
  uint nthr [[threads_per_threadgroup]]
) {
  const int total = prefix_count + control_count;
  const int begin = int(tg) * DRAFT_TILE;
  const int end = min(begin + DRAFT_TILE, total);

  float best_v = -INFINITY;
  int best_i = INT_MAX;
  for (int idx = begin + int(lid); idx < end; idx += int(nthr)) {
    float v; int id;
    draft_fetch(prefix_logits, control_logits, idx, prefix_count, control_start, v, id);
    if (draft_better(v, id, best_v, best_i)) { best_v = v; best_i = id; }
  }

  threadgroup float sv[256];
  threadgroup int   si[256];
  sv[lid] = best_v;
  si[lid] = best_i;
  threadgroup_barrier(mem_flags::mem_threadgroup);
  for (uint s = nthr / 2; s > 0; s >>= 1) {
    if (lid < s) {
      if (draft_better(sv[lid + s], si[lid + s], sv[lid], si[lid])) {
        sv[lid] = sv[lid + s];
        si[lid] = si[lid + s];
      }
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
  }
  if (lid == 0) {
    partial_vals[tg] = sv[0];
    partial_ids[tg] = si[0];
  }
}

[[max_total_threads_per_threadgroup(256)]]
kernel void mtp_draft_select_stage2(
  device const float *partial_vals [[buffer(0)]],
  device const int   *partial_ids  [[buffer(1)]],
  device int         *result       [[buffer(2)]],
  constant int &n_partials         [[buffer(3)]],
  uint lid  [[thread_position_in_threadgroup]],
  uint nthr [[threads_per_threadgroup]]
) {
  float best_v = -INFINITY;
  int best_i = INT_MAX;
  for (int i = int(lid); i < n_partials; i += int(nthr)) {
    if (draft_better(partial_vals[i], partial_ids[i], best_v, best_i)) {
      best_v = partial_vals[i];
      best_i = partial_ids[i];
    }
  }
  threadgroup float sv[256];
  threadgroup int   si[256];
  sv[lid] = best_v;
  si[lid] = best_i;
  threadgroup_barrier(mem_flags::mem_threadgroup);
  for (uint s = nthr / 2; s > 0; s >>= 1) {
    if (lid < s) {
      if (draft_better(sv[lid + s], si[lid + s], sv[lid], si[lid])) {
        sv[lid] = sv[lid + s];
        si[lid] = si[lid + s];
      }
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
  }
  if (lid == 0) result[0] = si[0];
}
