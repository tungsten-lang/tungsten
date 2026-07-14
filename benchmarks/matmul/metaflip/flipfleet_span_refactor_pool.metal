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
kernel void ffsrp_probe_two(
  device long *signatures [[buffer(0)]],
  device long *target [[buffer(1)]],
  device int *control [[buffer(2)]],
  device int *params [[buffer(3)]],
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
  int count = params[0];
  int a = (tid / count);
  int b = (tid - (a * count));
  if ((a < b)) {
    if (((signatures[a] ^ signatures[b]) == target[0])) {
      int old = atomic_fetch_min_explicit(((device atomic_int*)control + 0), tid, memory_order_relaxed);
    }
  }
}

[[max_total_threads_per_threadgroup(1024)]]
kernel void ffsrp_probe_three(
  device long *signatures [[buffer(0)]],
  device long *table_signatures [[buffer(1)]],
  device uint *table_codes [[buffer(2)]],
  device long *target [[buffer(3)]],
  device int *original_ids [[buffer(4)]],
  device int *control [[buffer(5)]],
  device int *params [[buffer(6)]],
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
  int count = params[0];
  int table_mask = params[1];
  int table_capacity = params[2];
  int k = params[3];
  int a = (tid / count);
  int b = (tid - (a * count));
  if ((a < b)) {
    long wanted = ((target[0] ^ signatures[a]) ^ signatures[b]);
    long lo = (wanted & 4294967295);
    long hi = ((wanted >> 32) & 4294967295);
    long rotated = (((hi << 13) & 4294967295) | (hi >> 19));
    long mixed = ((((lo ^ rotated) ^ (lo >> 16)) ^ (hi >> 11)) & 4294967295);
    mixed = (((mixed * 1103515245) + 12345) & 4294967295);
    mixed = (mixed ^ (mixed >> 16));
    int slot = (mixed & table_mask);
    int scanned = 0;
    int done = 0;
    while ((scanned < table_capacity)) {
      if ((done == 0)) {
        uint packed = table_codes[slot];
        if ((packed == 0)) {
          done = 1;
        } else {
          if ((table_signatures[slot] == wanted)) {
            int third = (packed - 1);
            int distinct = 1;
            if ((third == a)) {
              distinct = 0;
            }
            if ((third == b)) {
              distinct = 0;
            }
            if ((distinct != 0)) {
              int unchanged = 0;
              if ((k == 3)) {
                int in_a = 0;
                int in_b = 0;
                int in_third = 0;
                int oi = 0;
                while ((oi < 3)) {
                  if ((original_ids[oi] == a)) {
                    in_a = 1;
                  }
                  if ((original_ids[oi] == b)) {
                    in_b = 1;
                  }
                  if ((original_ids[oi] == third)) {
                    in_third = 1;
                  }
                  oi = (oi + 1);
                }
                if ((in_a != 0)) {
                  if ((in_b != 0)) {
                    if ((in_third != 0)) {
                      unchanged = 1;
                    }
                  }
                }
              }
              if ((unchanged == 0)) {
                int old = atomic_fetch_min_explicit(((device atomic_int*)control + 0), tid, memory_order_relaxed);
                done = 1;
              }
            }
          }
          if ((done == 0)) {
            slot = ((slot + 1) & table_mask);
            scanned = (scanned + 1);
          }
        }
      } else {
        scanned = table_capacity;
      }
    }
  }
}

[[max_total_threads_per_threadgroup(1024)]]
kernel void ffsrp_probe_four(
  device long *signatures [[buffer(0)]],
  device long *table_signatures [[buffer(1)]],
  device uint *table_codes [[buffer(2)]],
  device long *target [[buffer(3)]],
  device int *original_ids [[buffer(4)]],
  device int *control [[buffer(5)]],
  device int *params [[buffer(6)]],
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
  int count = params[0];
  int table_mask = params[1];
  int table_capacity = params[2];
  int k = params[3];
  int a = (tid / count);
  int b = (tid - (a * count));
  if ((a < b)) {
    long wanted = ((target[0] ^ signatures[a]) ^ signatures[b]);
    long lo = (wanted & 4294967295);
    long hi = ((wanted >> 32) & 4294967295);
    long rotated = (((hi << 13) & 4294967295) | (hi >> 19));
    long mixed = ((((lo ^ rotated) ^ (lo >> 16)) ^ (hi >> 11)) & 4294967295);
    mixed = (((mixed * 1103515245) + 12345) & 4294967295);
    mixed = (mixed ^ (mixed >> 16));
    int slot = (mixed & table_mask);
    int scanned = 0;
    int done = 0;
    while ((scanned < table_capacity)) {
      if ((done == 0)) {
        uint packed = table_codes[slot];
        if ((packed == 0)) {
          done = 1;
        } else {
          if ((table_signatures[slot] == wanted)) {
            int code = (packed - 1);
            int c = (code / count);
            int d = (code - (c * count));
            int distinct = 1;
            if ((c == a)) {
              distinct = 0;
            }
            if ((c == b)) {
              distinct = 0;
            }
            if ((d == a)) {
              distinct = 0;
            }
            if ((d == b)) {
              distinct = 0;
            }
            if ((distinct != 0)) {
              int unchanged = 0;
              if ((k == 4)) {
                int in_a = 0;
                int in_b = 0;
                int in_c = 0;
                int in_d = 0;
                int oi = 0;
                while ((oi < 4)) {
                  if ((original_ids[oi] == a)) {
                    in_a = 1;
                  }
                  if ((original_ids[oi] == b)) {
                    in_b = 1;
                  }
                  if ((original_ids[oi] == c)) {
                    in_c = 1;
                  }
                  if ((original_ids[oi] == d)) {
                    in_d = 1;
                  }
                  oi = (oi + 1);
                }
                if ((in_a != 0)) {
                  if ((in_b != 0)) {
                    if ((in_c != 0)) {
                      if ((in_d != 0)) {
                        unchanged = 1;
                      }
                    }
                  }
                }
              }
              if ((unchanged == 0)) {
                int old = atomic_fetch_min_explicit(((device atomic_int*)control + 0), tid, memory_order_relaxed);
                done = 1;
              }
            }
          }
          if ((done == 0)) {
            slot = ((slot + 1) & table_mask);
            scanned = (scanned + 1);
          }
        }
      } else {
        scanned = table_capacity;
      }
    }
  }
}

