// GatedDeltaNet single-step kernel for qwen3.6's linear_attention layers.
// Ported from MLX's gated_delta_step in mlx_lm/models/gated_delta.py.
//
// Recurrence (per (B, Hv) cell, per Dv element):
//   state[Dk]  *= g                                  // decay along Dk
//   kv_mem      = sum_k(state * k)                   // [scalar per Dv]
//   delta       = (v - kv_mem) * beta                // [scalar]
//   state      += k * delta                          // outer-product update
//   y           = sum_k(state * q)                   // [scalar per Dv]
//
// State is held in REGISTERS during the step and only written back to device
// memory at the end (the full state per (head, dv) is just Dk floats; with
// Dk=128 and 32 lanes per simdgroup that's 4 floats/lane).
//
// For decode (T=1) the recurrence loop runs once. Prefill (T>1) variant is
// a future kernel.
//
// GQA: Hv heads (32 for qwen3.6) share groups of (Hv/Hk) Q/K heads. Each
// hv_idx routes to its hk_idx = hv_idx / (Hv/Hk).
//
// Dispatch:
//   threadgroup = (32, 4, 1)  → 128 threads = 4 simdgroups × 32 lanes
//   grid_tgs    = (1, Dv/4, B*Hv)
//
// For qwen3.6 at decode (B=1): 1 × 32 × 32 = 1024 TGs of 128 threads.
// Each TG handles 4 consecutive Dv values for one head; the 4 simdgroups
// run in parallel (one per Dv slot), each cooperatively reducing along Dk
// (32 lanes × 4 elts/lane = 128 = Dk).

#include <metal_stdlib>
using namespace metal;

[[max_total_threads_per_threadgroup(128)]]
kernel void gated_delta_step(
  device const float *__restrict__ q         [[buffer(0)]],   // [B, Hk, Dk]
  device const float *__restrict__ k         [[buffer(1)]],   // [B, Hk, Dk]
  device const float *__restrict__ v         [[buffer(2)]],   // [B, Hv, Dv]
  device const float *__restrict__ g_in      [[buffer(3)]],   // [B, Hv]
  device const float *__restrict__ beta_in   [[buffer(4)]],   // [B, Hv]
  device const float *__restrict__ state_in  [[buffer(5)]],   // [B, Hv, Dv, Dk]
  device       float *__restrict__ y         [[buffer(6)]],   // [B, Hv, Dv]
  device       float *__restrict__ state_out [[buffer(7)]],   // [B, Hv, Dv, Dk]
  constant int &Hk [[buffer(8)]],
  constant int &Hv [[buffer(9)]],
  constant int &Dk [[buffer(10)]],
  constant int &Dv [[buffer(11)]],
  uint3 tg_pos     [[threadgroup_position_in_grid]],
  uint3 t_in_tg    [[thread_position_in_threadgroup]],
  uint  simd_lane  [[thread_index_in_simdgroup]]
) {
  // Identity: which (B, Hv head, Dv element) this thread is responsible for.
  int n        = int(tg_pos.z);              // = b * Hv + hv_idx
  int hv_idx   = n % Hv;
  int b_idx    = n / Hv;
  int dv_base  = int(tg_pos.y) * 4;          // 4 Dv values per TG
  int dv_off   = int(t_in_tg.y);             // 0..3 within TG
  int dv_idx   = dv_base + dv_off;

  int gqa_factor = Hv / Hk;
  int hk_idx     = hv_idx / gqa_factor;

  int n_per_t   = Dk / 32;                   // 4 for Dk=128
  int dk_base   = int(simd_lane) * n_per_t;  // start index along Dk for this lane

  // Load per-head scalars.
  float g_val    = g_in   [b_idx * Hv + hv_idx];
  float beta_val = beta_in[b_idx * Hv + hv_idx];

  // Pointers into Q, K, V, state for this (b, head, dv).
  int q_off       = (b_idx * Hk + hk_idx) * Dk;
  int k_off       = q_off;                                              // Q and K share head layout
  int v_off       = (b_idx * Hv + hv_idx) * Dv + dv_idx;
  int state_off   = ((b_idx * Hv + hv_idx) * Dv + dv_idx) * Dk;

  // Pull this lane's slice of state into registers (Dk/32 elts per lane).
  float state[4];
  for (int i = 0; i < n_per_t; i++) {
    state[i] = state_in[state_off + dk_base + i];
  }

  // Decay: state *= g
  for (int i = 0; i < n_per_t; i++) {
    state[i] *= g_val;
  }

  // kv_mem = sum_k(state * k); needs cross-lane reduction
  float kv_mem = 0.0f;
  for (int i = 0; i < n_per_t; i++) {
    kv_mem += state[i] * k[k_off + dk_base + i];
  }
  kv_mem = simd_sum(kv_mem);

  // delta = (v - kv_mem) * beta — scalar, all lanes have it
  float v_val = v[v_off];
  float delta = (v_val - kv_mem) * beta_val;

  // state += k * delta
  for (int i = 0; i < n_per_t; i++) {
    state[i] += k[k_off + dk_base + i] * delta;
  }

  // y = sum_k(state * q); cross-lane reduction
  float out = 0.0f;
  for (int i = 0; i < n_per_t; i++) {
    out += state[i] * q[q_off + dk_base + i];
  }
  out = simd_sum(out);
  if (simd_lane == 0) {
    y[v_off] = out;
  }

  // Write state back to device memory.
  for (int i = 0; i < n_per_t; i++) {
    state_out[state_off + dk_base + i] = state[i];
  }
}
