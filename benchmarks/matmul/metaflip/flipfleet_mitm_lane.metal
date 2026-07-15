// Tungsten @gpu kernel output — do not edit by hand
#include <metal_stdlib>
#include <metal_simdgroup_matrix>
using namespace metal;

// Threadgroup-wide reductions across up to 1024 threads (32 simdgroups).
inline float __tg_sum_f32(float v, threadgroup float *s, uint sl, uint si, uint n_simds) {
  float sm = simd_sum(v);
  if (sl == 0) { s[si] = sm; }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  float partial = (sl < n_simds) ? s[sl] : 0.0f;
  float total = (si == 0) ? simd_sum(partial) : 0.0f;
  if (si == 0 && sl == 0) { s[0] = total; }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  return s[0];
}
inline float __tg_max_f32(float v, threadgroup float *s, uint sl, uint si, uint n_simds) {
  float sm = simd_max(v);
  if (sl == 0) { s[si] = sm; }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  float partial = (sl < n_simds) ? s[sl] : -INFINITY;
  float total = (si == 0) ? simd_max(partial) : -INFINITY;
  if (si == 0 && sl == 0) { s[0] = total; }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  return s[0];
}
inline int __tg_min_i32(int v, threadgroup int *s, uint sl, uint si, uint n_simds) {
  int sm = simd_min(v);
  if (sl == 0) { s[si] = sm; }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  int partial = (sl < n_simds) ? s[sl] : INT_MAX;
  int total = (si == 0) ? simd_min(partial) : INT_MAX;
  if (si == 0 && sl == 0) { s[0] = total; }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  return s[0];
}

[[max_total_threads_per_threadgroup(1024)]]
kernel void ffm_enumerate_pairs(
  device uint *fps0 [[buffer(0)]],
  device uint *fps1 [[buffer(1)]],
  device uint *fps2 [[buffer(2)]],
  device uint *fps3 [[buffer(3)]],
  device uint *pair0 [[buffer(4)]],
  device uint *pair1 [[buffer(5)]],
  device uint *pair2 [[buffer(6)]],
  device uint *pair3 [[buffer(7)]],
  device int *enum_params [[buffer(8)]],
  uint3 __tid [[thread_position_in_grid]],
  uint3 __tid_in_tg [[thread_position_in_threadgroup]],
  uint3 __tg_id [[threadgroup_position_in_grid]],
  uint3 __tg_size [[threads_per_threadgroup]],
  uint __simd_lane [[thread_index_in_simdgroup]],
  uint __simd_id [[simdgroup_index_in_threadgroup]]
) {
  threadgroup float __tg_scratch_f[32];
  threadgroup int   __tg_scratch_i[32];
  uint __tg_total = __tg_size.x * __tg_size.y * __tg_size.z;
  int tid = int(__tid.x);
  int count = enum_params[0];
  int left = (tid / count);
  int right = (tid - (left * count));
  if ((left < right)) {
    pair0[tid] = (fps0[left] ^ fps0[right]);
    pair1[tid] = (fps1[left] ^ fps1[right]);
    pair2[tid] = (fps2[left] ^ fps2[right]);
    pair3[tid] = (fps3[left] ^ fps3[right]);
  }
}

[[max_total_threads_per_threadgroup(1024)]]
kernel void ffm_probe_pairs(
  device uint *q0 [[buffer(0)]],
  device uint *q1 [[buffer(1)]],
  device uint *q2 [[buffer(2)]],
  device uint *q3 [[buffer(3)]],
  device uint *table0 [[buffer(4)]],
  device uint *table1 [[buffer(5)]],
  device uint *table2 [[buffer(6)]],
  device uint *table3 [[buffer(7)]],
  device uint *table_used [[buffer(8)]],
  device uint *table_pair [[buffer(9)]],
  device uint *target_fp [[buffer(10)]],
  device uint *matches [[buffer(11)]],
  device int *probe_params [[buffer(12)]],
  uint3 __tid [[thread_position_in_grid]],
  uint3 __tid_in_tg [[thread_position_in_threadgroup]],
  uint3 __tg_id [[threadgroup_position_in_grid]],
  uint3 __tg_size [[threads_per_threadgroup]],
  uint __simd_lane [[thread_index_in_simdgroup]],
  uint __simd_id [[simdgroup_index_in_threadgroup]]
) {
  threadgroup float __tg_scratch_f[32];
  threadgroup int   __tg_scratch_i[32];
  uint __tg_total = __tg_size.x * __tg_size.y * __tg_size.z;
  int tid = int(__tid.x);
  int count = probe_params[0];
  uint table_mask = probe_params[1];
  int table_cap = probe_params[2];
  int left = (tid / count);
  int right = (tid - (left * count));
  int outbase = (tid * 16);
  int hit = 0;
  while ((hit < 16)) {
    matches[(outbase + hit)] = 0;
    hit = (hit + 1);
  }
  if ((left < right)) {
    uint want0 = ((target_fp[0] ^ q0[left]) ^ q0[right]);
    uint want1 = ((target_fp[1] ^ q1[left]) ^ q1[right]);
    uint want2 = ((target_fp[2] ^ q2[left]) ^ q2[right]);
    uint want3 = ((target_fp[3] ^ q3[left]) ^ q3[right]);
    uint mixed = ((((((want0 ^ (want1 << 7)) ^ (want1 >> 25)) ^ (want2 << 13)) ^ (want2 >> 19)) ^ (want3 << 19)) ^ (want3 >> 13));
    mixed = ((mixed ^ (mixed >> 16)) * 73244475);
    mixed = ((mixed ^ (mixed >> 16)) * 73244475);
    mixed = (mixed ^ (mixed >> 16));
    uint slot_u = (mixed & table_mask);
    int slot = slot_u;
    int scanned = 0;
    int found = 0;
    while ((scanned < table_cap)) {
      if ((table_used[slot] == 0)) {
        scanned = table_cap;
      } else {
        if ((table0[slot] == want0)) {
          if ((table1[slot] == want1)) {
            if ((table2[slot] == want2)) {
              if ((table3[slot] == want3)) {
                uint packed_u = table_pair[slot];
                int packed = packed_u;
                int other_left = (packed / count);
                int other_right = (packed - (other_left * count));
                if ((other_left != left)) {
                  if ((other_left != right)) {
                    if ((other_right != left)) {
                      if ((other_right != right)) {
                        if ((found < 16)) {
                          matches[(outbase + found)] = packed_u;
                          found = (found + 1);
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
        slot = ((slot + 1) & table_mask);
        scanned = (scanned + 1);
      }
    }
  }
}

