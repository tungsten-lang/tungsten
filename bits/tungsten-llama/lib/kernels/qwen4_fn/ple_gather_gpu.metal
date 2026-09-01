// Device-side per-token setup for Qwen3.8-Flash-Next:
//
//   build_rope_tab: cos/sin tables from the pos buffer (theta = base^(-2i/64))
//     — replaces 64 host writes + host trig per token.
//   ple_table_gather: gather + dequant the 16 n-gram rows (160 fp8 bytes each)
//     straight from the mmapped table shards — replaces 2560 host writes and
//     moves the table's random page faults onto the GPU where they overlap
//     other work. The host still computes the 16 hashed row ids (int64 math)
//     and writes (shard_idx, byte_offset) pairs into ple_ids.
//
// Dispatch: build_rope_tab = 32 threads; ple_table_gather = 16 TGs x 160.

#include <metal_stdlib>
using namespace metal;

kernel void build_rope_tab(
  device const int *__restrict__ pos     [[buffer(0)]],
  device float     *__restrict__ cos_tab [[buffer(1)]],
  device float     *__restrict__ sin_tab [[buffer(2)]],
  constant float &log_base [[buffer(3)]],
  constant int   &rot_half [[buffer(4)]],
  uint __tid [[thread_position_in_grid]]
) {
  int i = int(__tid);
  if (i >= rot_half) return;
  float theta = exp(log_base * (-(float)i / (float)rot_half));
  float angle = (float)pos[0] * theta;
  cos_tab[i] = cos(angle);
  sin_tab[i] = sin(angle);
}

static inline float e4m3_decode_f32(uint b) {
  half h = as_type<half>(ushort((b & 127) << 7)) * 256.0h;
  return float(h);
}

[[max_total_threads_per_threadgroup(160)]]
kernel void ple_table_gather(
  device const uchar *__restrict__ s0 [[buffer(0)]],
  device const uchar *__restrict__ s1 [[buffer(1)]],
  device const uchar *__restrict__ s2 [[buffer(2)]],
  device const uchar *__restrict__ s3 [[buffer(3)]],
  device const uchar *__restrict__ s4 [[buffer(4)]],
  device const uchar *__restrict__ s5 [[buffer(5)]],
  device const uchar *__restrict__ s6 [[buffer(6)]],
  device const uchar *__restrict__ s7 [[buffer(7)]],
  device const uchar *__restrict__ s8 [[buffer(8)]],
  device const uchar *__restrict__ s9 [[buffer(9)]],
  device const int   *__restrict__ ids [[buffer(10)]],   // [16 x (shard, offset)]
  device float       *__restrict__ e   [[buffer(11)]],   // [2560]
  constant float &scale    [[buffer(12)]],
  constant int   &head_dim [[buffer(13)]],
  uint __tg_id     [[threadgroup_position_in_grid]],
  uint __tid_in_tg [[thread_position_in_threadgroup]]
) {
  int h = int(__tg_id);
  int j = int(__tid_in_tg);
  if (j >= head_dim) return;
  int shard = ids[h * 2];
  int off = ids[h * 2 + 1];
  device const uchar *base =
      shard == 0 ? s0 : shard == 1 ? s1 : shard == 2 ? s2 : shard == 3 ? s3 :
      shard == 4 ? s4 : shard == 5 ? s5 : shard == 6 ? s6 : shard == 7 ? s7 :
      shard == 8 ? s8 : s9;
  e[h * head_dim + j] = e4m3_decode_f32(uint(base[off + j])) * scale;
}
