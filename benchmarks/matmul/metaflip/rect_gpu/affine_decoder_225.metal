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
kernel void ff225ad_triple_weight(
  device long *base [[buffer(0)]],
  device long *basis [[buffer(1)]],
  device int *best [[buffer(2)]],
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
  int dimension = params[0];
  int words = params[1];
  int work = params[2];
  if ((tid < work)) {
    int square = (dimension * dimension);
    int a = (tid / square);
    int remainder = (tid - (a * square));
    int b = (remainder / dimension);
    int c = (remainder - (b * dimension));
    if ((a < b)) {
      if ((b < c)) {
        int weight = 0;
        int word = 0;
        while ((word < words)) {
          long value = (((base[word] ^ basis[((a * words) + word)]) ^ basis[((b * words) + word)]) ^ basis[((c * words) + word)]);
          value = (value - ((value >> 1) & 6148914691236517205));
          value = ((value & 3689348814741910323) + ((value >> 2) & 3689348814741910323));
          value = ((value + (value >> 4)) & 1085102592571150095);
          weight = (weight + ((value * 72340172838076673) >> 56));
          word = (word + 1);
        }
        int old = atomic_fetch_min_explicit(((device atomic_int*)best + 0), weight, memory_order_relaxed);
      }
    }
  }
}

[[max_total_threads_per_threadgroup(1024)]]
kernel void ff225ad_triple_winner(
  device long *base [[buffer(0)]],
  device long *basis [[buffer(1)]],
  device int *best [[buffer(2)]],
  device int *winner [[buffer(3)]],
  device int *params [[buffer(4)]],
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
  int dimension = params[0];
  int words = params[1];
  int work = params[2];
  if ((tid < work)) {
    int square = (dimension * dimension);
    int a = (tid / square);
    int remainder = (tid - (a * square));
    int b = (remainder / dimension);
    int c = (remainder - (b * dimension));
    if ((a < b)) {
      if ((b < c)) {
        int weight = 0;
        int word = 0;
        while ((word < words)) {
          long value = (((base[word] ^ basis[((a * words) + word)]) ^ basis[((b * words) + word)]) ^ basis[((c * words) + word)]);
          value = (value - ((value >> 1) & 6148914691236517205));
          value = ((value & 3689348814741910323) + ((value >> 2) & 3689348814741910323));
          value = ((value + (value >> 4)) & 1085102592571150095);
          weight = (weight + ((value * 72340172838076673) >> 56));
          word = (word + 1);
        }
        if ((weight == best[0])) {
          int old = atomic_fetch_min_explicit(((device atomic_int*)winner + 0), tid, memory_order_relaxed);
        }
      }
    }
  }
}

[[max_total_threads_per_threadgroup(1024)]]
kernel void ff225ad_band_walk(
  device long *states [[buffer(0)]],
  device long *best_states [[buffer(1)]],
  device long *origins [[buffer(2)]],
  device long *generators [[buffer(3)]],
  device int *telemetry [[buffer(4)]],
  device int *params [[buffer(5)]],
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
  int lane = int(__tid.x);
  int lanes = params[0];
  int words = params[1];
  int pool_count = params[2];
  int origin_count = params[3];
  int steps = params[4];
  int band = params[5];
  int nonce = params[6];
  int reset_steps = params[7];
  if ((lane < lanes)) {
    int state_offset = (lane * words);
    int home = (lane % origin_count);
    int current_weight = telemetry[(lane * 5)];
    int best_weight = telemetry[((lane * 5) + 1)];
    int best_distance = telemetry[((lane * 5) + 2)];
    int accepts = telemetry[((lane * 5) + 3)];
    int resets = telemetry[((lane * 5) + 4)];
    int rng = (((((lane + 1) * 1103515245) + (nonce * 12345)) + 1013904223) & 2147483647);
    if ((rng == 0)) {
      rng = 1;
    }
    int stall = 0;
    int step = 0;
    while ((step < steps)) {
      rng = (((rng * 1103515245) + 12345) & 2147483647);
      int generator = (rng % pool_count);
      int next_weight = 0;
      int word = 0;
      while ((word < words)) {
        long value = (states[(state_offset + word)] ^ generators[((generator * words) + word)]);
        value = (value - ((value >> 1) & 6148914691236517205));
        value = ((value & 3689348814741910323) + ((value >> 2) & 3689348814741910323));
        value = ((value + (value >> 4)) & 1085102592571150095);
        next_weight = (next_weight + ((value * 72340172838076673) >> 56));
        word = (word + 1);
      }
      int accept = 0;
      if ((next_weight <= band)) {
        if ((next_weight <= current_weight)) {
          accept = 1;
        } else {
          int delta = (next_weight - current_weight);
          rng = (((rng * 1103515245) + 12345) & 2147483647);
          int chance = 2;
          if ((delta == 1)) {
            chance = 96;
          }
          if ((delta == 2)) {
            chance = 48;
          }
          if ((delta == 3)) {
            chance = 16;
          }
          if (((rng & 255) < chance)) {
            accept = 1;
          }
        }
      }
      if ((accept != 0)) {
        word = 0;
        while ((word < words)) {
          states[(state_offset + word)] = (states[(state_offset + word)] ^ generators[((generator * words) + word)]);
          word = (word + 1);
        }
        current_weight = next_weight;
        accepts = (accepts + 1);
        stall = 0;
        if ((current_weight <= best_weight)) {
          int distance = 0;
          word = 0;
          while ((word < words)) {
            long value = (states[(state_offset + word)] ^ origins[((home * words) + word)]);
            value = (value - ((value >> 1) & 6148914691236517205));
            value = ((value & 3689348814741910323) + ((value >> 2) & 3689348814741910323));
            value = ((value + (value >> 4)) & 1085102592571150095);
            distance = (distance + ((value * 72340172838076673) >> 56));
            word = (word + 1);
          }
          if ((current_weight < best_weight)) {
            best_weight = current_weight;
            best_distance = distance;
            word = 0;
            while ((word < words)) {
              best_states[(state_offset + word)] = states[(state_offset + word)];
              word = (word + 1);
            }
          } else {
            if ((distance > best_distance)) {
              best_distance = distance;
              word = 0;
              while ((word < words)) {
                best_states[(state_offset + word)] = states[(state_offset + word)];
                word = (word + 1);
              }
            }
          }
        }
      } else {
        stall = (stall + 1);
      }
      if ((stall >= reset_steps)) {
        int origin = (((home + resets) + 1) % origin_count);
        word = 0;
        current_weight = 0;
        while ((word < words)) {
          long value = origins[((origin * words) + word)];
          states[(state_offset + word)] = value;
          value = (value - ((value >> 1) & 6148914691236517205));
          value = ((value & 3689348814741910323) + ((value >> 2) & 3689348814741910323));
          value = ((value + (value >> 4)) & 1085102592571150095);
          current_weight = (current_weight + ((value * 72340172838076673) >> 56));
          word = (word + 1);
        }
        resets = (resets + 1);
        stall = 0;
      }
      step = (step + 1);
    }
    telemetry[(lane * 5)] = current_weight;
    telemetry[((lane * 5) + 1)] = best_weight;
    telemetry[((lane * 5) + 2)] = best_distance;
    telemetry[((lane * 5) + 3)] = accepts;
    telemetry[((lane * 5) + 4)] = resets;
  }
}
