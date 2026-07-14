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
kernel void ffx_enumerate_triples(
  device uint *fps0 [[buffer(0)]],
  device uint *fps1 [[buffer(1)]],
  device uint *fps2 [[buffer(2)]],
  device uint *fps3 [[buffer(3)]],
  device uint *triple0 [[buffer(4)]],
  device uint *triple1 [[buffer(5)]],
  device uint *triple2 [[buffer(6)]],
  device uint *triple3 [[buffer(7)]],
  device uint *packed [[buffer(8)]],
  device int *params [[buffer(9)]],
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
  int square = (count * count);
  int a = (tid / square);
  int rem = (tid - (a * square));
  int b = (rem / count);
  int c = (rem - (b * count));
  packed[tid] = 0;
  if ((a < b)) {
    if ((b < c)) {
      triple0[tid] = ((fps0[a] ^ fps0[b]) ^ fps0[c]);
      triple1[tid] = ((fps1[a] ^ fps1[b]) ^ fps1[c]);
      triple2[tid] = ((fps2[a] ^ fps2[b]) ^ fps2[c]);
      triple3[tid] = ((fps3[a] ^ fps3[b]) ^ fps3[c]);
      packed[tid] = (tid + 1);
    }
  }
}

[[max_total_threads_per_threadgroup(1024)]]
kernel void ffx_enumerate_quads(
  device uint *fps0 [[buffer(0)]],
  device uint *fps1 [[buffer(1)]],
  device uint *fps2 [[buffer(2)]],
  device uint *fps3 [[buffer(3)]],
  device uint *quad0 [[buffer(4)]],
  device uint *quad1 [[buffer(5)]],
  device uint *quad2 [[buffer(6)]],
  device uint *quad3 [[buffer(7)]],
  device uint *packed [[buffer(8)]],
  device int *params [[buffer(9)]],
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
  int square = (count * count);
  int cube = (square * count);
  int a = (tid / cube);
  int rem = (tid - (a * cube));
  int b = (rem / square);
  rem = (rem - (b * square));
  int c = (rem / count);
  int d = (rem - (c * count));
  packed[tid] = 0;
  if ((a < b)) {
    if ((b < c)) {
      if ((c < d)) {
        quad0[tid] = (((fps0[a] ^ fps0[b]) ^ fps0[c]) ^ fps0[d]);
        quad1[tid] = (((fps1[a] ^ fps1[b]) ^ fps1[c]) ^ fps1[d]);
        quad2[tid] = (((fps2[a] ^ fps2[b]) ^ fps2[c]) ^ fps2[d]);
        quad3[tid] = (((fps3[a] ^ fps3[b]) ^ fps3[c]) ^ fps3[d]);
        packed[tid] = (tid + 1);
      }
    }
  }
}

[[max_total_threads_per_threadgroup(1024)]]
kernel void ffx_probe_triples(
  device uint *fps0 [[buffer(0)]],
  device uint *fps1 [[buffer(1)]],
  device uint *fps2 [[buffer(2)]],
  device uint *fps3 [[buffer(3)]],
  device uint *table [[buffer(4)]],
  device uint *target [[buffer(5)]],
  device uint *matches [[buffer(6)]],
  device int *params [[buffer(7)]],
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
  uint table_mask = params[1];
  int table_cap = params[2];
  int tuple_size = params[3];
  int square = (count * count);
  int a = (tid / square);
  int rem = (tid - (a * square));
  int b = (rem / count);
  int c = (rem - (b * count));
  matches[tid] = 0;
  if ((a < b)) {
    if ((b < c)) {
      uint want0 = (((target[0] ^ fps0[a]) ^ fps0[b]) ^ fps0[c]);
      uint want1 = (((target[1] ^ fps1[a]) ^ fps1[b]) ^ fps1[c]);
      uint want2 = (((target[2] ^ fps2[a]) ^ fps2[b]) ^ fps2[c]);
      uint want3 = (((target[3] ^ fps3[a]) ^ fps3[b]) ^ fps3[c]);
      uint mixed = (((want0 ^ (want1 >> 7)) ^ (want2 >> 13)) ^ (want3 >> 19));
      uint slot = (mixed & table_mask);
      int used_offset = (table_cap * 4);
      int tuple_offset = (table_cap * 5);
      int scanned = 0;
      int found = 0;
      while ((scanned < table_cap)) {
        if ((table[(used_offset + slot)] == 0)) {
          scanned = table_cap;
        } else {
          if ((table[slot] == want0)) {
            if ((table[(table_cap + slot)] == want1)) {
              if ((table[((table_cap * 2) + slot)] == want2)) {
                if ((table[((table_cap * 3) + slot)] == want3)) {
                  uint code = (table[(tuple_offset + slot)] - 1);
                  int x = 0;
                  int y = 0;
                  int z = -(1);
                  if ((tuple_size == 2)) {
                    x = (code / count);
                    y = (code - (x * count));
                  }
                  if ((tuple_size == 3)) {
                    x = (code / square);
                    int rest = (code - (x * square));
                    y = (rest / count);
                    z = (rest - (y * count));
                  }
                  int overlap = 0;
                  if ((x == a)) {
                    overlap = 1;
                  }
                  if ((x == b)) {
                    overlap = 1;
                  }
                  if ((x == c)) {
                    overlap = 1;
                  }
                  if ((y == a)) {
                    overlap = 1;
                  }
                  if ((y == b)) {
                    overlap = 1;
                  }
                  if ((y == c)) {
                    overlap = 1;
                  }
                  if ((z == a)) {
                    overlap = 1;
                  }
                  if ((z == b)) {
                    overlap = 1;
                  }
                  if ((z == c)) {
                    overlap = 1;
                  }
                  if ((overlap == 0)) {
                    matches[tid] = table[(tuple_offset + slot)];
                    found = 1;
                    scanned = table_cap;
                  }
                }
              }
            }
          }
          if ((found == 0)) {
            slot = ((slot + 1) & table_mask);
            scanned = (scanned + 1);
          }
        }
      }
    }
  }
}

[[max_total_threads_per_threadgroup(1024)]]
kernel void ffx_probe_quads(
  device uint *fps0 [[buffer(0)]],
  device uint *fps1 [[buffer(1)]],
  device uint *fps2 [[buffer(2)]],
  device uint *fps3 [[buffer(3)]],
  device uint *table [[buffer(4)]],
  device uint *target [[buffer(5)]],
  device uint *matches [[buffer(6)]],
  device int *params [[buffer(7)]],
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
  uint table_mask = params[1];
  int table_cap = params[2];
  int tuple_size = params[3];
  int square = (count * count);
  int cube = (square * count);
  int a = (tid / cube);
  int rem = (tid - (a * cube));
  int b = (rem / square);
  rem = (rem - (b * square));
  int c = (rem / count);
  int d = (rem - (c * count));
  matches[tid] = 0;
  if ((a < b)) {
    if ((b < c)) {
      if ((c < d)) {
        uint want0 = ((((target[0] ^ fps0[a]) ^ fps0[b]) ^ fps0[c]) ^ fps0[d]);
        uint want1 = ((((target[1] ^ fps1[a]) ^ fps1[b]) ^ fps1[c]) ^ fps1[d]);
        uint want2 = ((((target[2] ^ fps2[a]) ^ fps2[b]) ^ fps2[c]) ^ fps2[d]);
        uint want3 = ((((target[3] ^ fps3[a]) ^ fps3[b]) ^ fps3[c]) ^ fps3[d]);
        uint mixed = (((want0 ^ (want1 >> 7)) ^ (want2 >> 13)) ^ (want3 >> 19));
        uint slot = (mixed & table_mask);
        int used_offset = (table_cap * 4);
        int tuple_offset = (table_cap * 5);
        int scanned = 0;
        int found = 0;
        while ((scanned < table_cap)) {
          if ((table[(used_offset + slot)] == 0)) {
            scanned = table_cap;
          } else {
            if ((table[slot] == want0)) {
              if ((table[(table_cap + slot)] == want1)) {
                if ((table[((table_cap * 2) + slot)] == want2)) {
                  if ((table[((table_cap * 3) + slot)] == want3)) {
                    uint code = (table[(tuple_offset + slot)] - 1);
                    int x = (code / cube);
                    int rest = (code - (x * cube));
                    int y = (rest / square);
                    rest = (rest - (y * square));
                    int z = (rest / count);
                    int q = (rest - (z * count));
                    int overlap = 0;
                    if ((x == a)) {
                      overlap = 1;
                    }
                    if ((x == b)) {
                      overlap = 1;
                    }
                    if ((x == c)) {
                      overlap = 1;
                    }
                    if ((x == d)) {
                      overlap = 1;
                    }
                    if ((y == a)) {
                      overlap = 1;
                    }
                    if ((y == b)) {
                      overlap = 1;
                    }
                    if ((y == c)) {
                      overlap = 1;
                    }
                    if ((y == d)) {
                      overlap = 1;
                    }
                    if ((z == a)) {
                      overlap = 1;
                    }
                    if ((z == b)) {
                      overlap = 1;
                    }
                    if ((z == c)) {
                      overlap = 1;
                    }
                    if ((z == d)) {
                      overlap = 1;
                    }
                    if ((q == a)) {
                      overlap = 1;
                    }
                    if ((q == b)) {
                      overlap = 1;
                    }
                    if ((q == c)) {
                      overlap = 1;
                    }
                    if ((q == d)) {
                      overlap = 1;
                    }
                    if ((overlap == 0)) {
                      matches[tid] = table[(tuple_offset + slot)];
                      found = 1;
                      scanned = table_cap;
                    }
                  }
                }
              }
            }
            if ((found == 0)) {
              slot = ((slot + 1) & table_mask);
              scanned = (scanned + 1);
            }
          }
        }
      }
    }
  }
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
    uint mixed = (((want0 ^ (want1 >> 7)) ^ (want2 >> 13)) ^ (want3 >> 19));
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

