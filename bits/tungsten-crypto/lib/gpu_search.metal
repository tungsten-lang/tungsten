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

constant uint __gpu_const_sha256d_mine_kc[64] = {1116352408, 1899447441, 3049323471, 3921009573, 961987163, 1508970993, 2453635748, 2870763221, 3624381080, 310598401, 607225278, 1426881987, 1925078388, 2162078206, 2614888103, 3248222580, 3835390401, 4022224774, 264347078, 604807628, 770255983, 1249150122, 1555081692, 1996064986, 2554220882, 2821834349, 2952996808, 3210313671, 3336571891, 3584528711, 113926993, 338241895, 666307205, 773529912, 1294757372, 1396182291, 1695183700, 1986661051, 2177026350, 2456956037, 2730485921, 2820302411, 3259730800, 3345764771, 3516065817, 3600352804, 4094571909, 275423344, 430227734, 506948616, 659060556, 883997877, 958139571, 1322822218, 1537002063, 1747873779, 1955562222, 2024104815, 2227730452, 2361852424, 2428436474, 2756734187, 3204031479, 3329325298};

[[max_total_threads_per_threadgroup(1024)]]
kernel void sha256d_mine(
  device uint *job [[buffer(0)]],
  device int *out [[buffer(1)]],
  uint3 __tid [[thread_position_in_grid]],
  uint3 __tid_in_tg [[thread_position_in_threadgroup]],
  uint3 __tg_id [[threadgroup_position_in_grid]],
  uint3 __tg_size [[threads_per_threadgroup]],
  uint __simd_lane [[thread_index_in_simdgroup]],
  uint __simd_id [[simdgroup_index_in_threadgroup]]
) {
  uint __tg_total = __tg_size.x * __tg_size.y * __tg_size.z;
  uint nonce;
  uint a;
  uint b;
  uint c;
  uint d;
  uint e;
  uint f;
  uint g;
  uint h;
  uint i;
  uint t1;
  uint t2;
  uint x;
  uint y;
  uint h7;
  uint v7;
  int slot;
  uint gid = int(__tid.x);
  uint base = job[29];
  uint count = job[30];
  uint per = job[31];
  uint top = job[21];
  uint idx = (gid * per);
  uint last = (idx + per);
  if ((last > count)) {
    last = count;
  }
  uint m[16];
  uint best_val = 4294967295;
  uint best_nonce = 0;
  while ((idx < last)) {
    nonce = (base + idx);
    m[0] = job[19];
    m[1] = job[20];
    m[2] = job[18];
    m[3] = (((((nonce >> 24) & 255) | ((nonce >> 8) & 65280)) | ((nonce & 65280) << 8)) | (nonce << 24));
    m[4] = 2147483648;
    m[5] = 0;
    m[6] = 0;
    m[7] = 0;
    m[8] = 0;
    m[9] = 0;
    m[10] = 0;
    m[11] = 0;
    m[12] = 0;
    m[13] = 0;
    m[14] = 0;
    m[15] = 640;
    a = job[8];
    b = job[9];
    c = job[10];
    d = job[11];
    e = job[12];
    f = job[13];
    g = job[14];
    h = job[15];
    i = 3;
    #pragma clang loop unroll(full)
    while ((i < 18)) {
      t1 = ((((h + ((((e >> 6) | (e << 26)) ^ ((e >> 11) | (e << 21))) ^ ((e >> 25) | (e << 7)))) + (g ^ (e & (f ^ g)))) + __gpu_const_sha256d_mine_kc[i]) + m[(i & 15)]);
      t2 = (((((a >> 2) | (a << 30)) ^ ((a >> 13) | (a << 19))) ^ ((a >> 22) | (a << 10))) + ((a & b) ^ (c & (a ^ b))));
      h = g;
      g = f;
      f = e;
      e = (d + t1);
      d = c;
      c = b;
      b = a;
      a = (t1 + t2);
      i = (i + 1);
    }
    i = 18;
    #pragma clang loop unroll(full)
    while ((i < 64)) {
      x = m[((i + 1) & 15)];
      y = m[((i + 14) & 15)];
      m[(i & 15)] = (((m[(i & 15)] + ((((x >> 7) | (x << 25)) ^ ((x >> 18) | (x << 14))) ^ (x >> 3))) + m[((i + 9) & 15)]) + ((((y >> 17) | (y << 15)) ^ ((y >> 19) | (y << 13))) ^ (y >> 10)));
      t1 = ((((h + ((((e >> 6) | (e << 26)) ^ ((e >> 11) | (e << 21))) ^ ((e >> 25) | (e << 7)))) + (g ^ (e & (f ^ g)))) + __gpu_const_sha256d_mine_kc[i]) + m[(i & 15)]);
      t2 = (((((a >> 2) | (a << 30)) ^ ((a >> 13) | (a << 19))) ^ ((a >> 22) | (a << 10))) + ((a & b) ^ (c & (a ^ b))));
      h = g;
      g = f;
      f = e;
      e = (d + t1);
      d = c;
      c = b;
      b = a;
      a = (t1 + t2);
      i = (i + 1);
    }
    m[0] = (job[0] + a);
    m[1] = (job[1] + b);
    m[2] = (job[2] + c);
    m[3] = (job[3] + d);
    m[4] = (job[4] + e);
    m[5] = (job[5] + f);
    m[6] = (job[6] + g);
    m[7] = (job[7] + h);
    m[8] = 2147483648;
    m[9] = 0;
    m[10] = 0;
    m[11] = 0;
    m[12] = 0;
    m[13] = 0;
    m[14] = 0;
    m[15] = 256;
    a = 1779033703;
    b = 3144134277;
    c = 1013904242;
    d = 2773480762;
    e = 1359893119;
    f = 2600822924;
    g = 528734635;
    h = 1541459225;
    i = 0;
    #pragma clang loop unroll(full)
    while ((i < 16)) {
      t1 = ((((h + ((((e >> 6) | (e << 26)) ^ ((e >> 11) | (e << 21))) ^ ((e >> 25) | (e << 7)))) + (g ^ (e & (f ^ g)))) + __gpu_const_sha256d_mine_kc[i]) + m[(i & 15)]);
      t2 = (((((a >> 2) | (a << 30)) ^ ((a >> 13) | (a << 19))) ^ ((a >> 22) | (a << 10))) + ((a & b) ^ (c & (a ^ b))));
      h = g;
      g = f;
      f = e;
      e = (d + t1);
      d = c;
      c = b;
      b = a;
      a = (t1 + t2);
      i = (i + 1);
    }
    i = 16;
    #pragma clang loop unroll(full)
    while ((i < 61)) {
      x = m[((i + 1) & 15)];
      y = m[((i + 14) & 15)];
      m[(i & 15)] = (((m[(i & 15)] + ((((x >> 7) | (x << 25)) ^ ((x >> 18) | (x << 14))) ^ (x >> 3))) + m[((i + 9) & 15)]) + ((((y >> 17) | (y << 15)) ^ ((y >> 19) | (y << 13))) ^ (y >> 10)));
      t1 = ((((h + ((((e >> 6) | (e << 26)) ^ ((e >> 11) | (e << 21))) ^ ((e >> 25) | (e << 7)))) + (g ^ (e & (f ^ g)))) + __gpu_const_sha256d_mine_kc[i]) + m[(i & 15)]);
      t2 = (((((a >> 2) | (a << 30)) ^ ((a >> 13) | (a << 19))) ^ ((a >> 22) | (a << 10))) + ((a & b) ^ (c & (a ^ b))));
      h = g;
      g = f;
      f = e;
      e = (d + t1);
      d = c;
      c = b;
      b = a;
      a = (t1 + t2);
      i = (i + 1);
    }
    h7 = (1541459225 + e);
    v7 = (((((h7 >> 24) & 255) | ((h7 >> 8) & 65280)) | ((h7 & 65280) << 8)) | (h7 << 24));
    if ((v7 < best_val)) {
      best_val = v7;
      best_nonce = nonce;
    }
    if ((v7 <= top)) {
      slot = atomic_fetch_add_explicit(((device atomic_int*)out + 0), 1, memory_order_relaxed);
      if ((slot < 15)) {
        atomic_store_explicit(((device atomic_int*)out + (1 + slot)), nonce, memory_order_relaxed);
      }
    }
    idx = (idx + 1);
  }
  uint mybias = (best_val ^ 2147483648);
  atomic_fetch_min_explicit(((device atomic_int*)out + 16), mybias, memory_order_relaxed);
  uint cur = atomic_load_explicit(((device atomic_int*)out + 16), memory_order_relaxed);
  if ((cur == mybias)) {
    atomic_store_explicit(((device atomic_int*)out + 17), best_nonce, memory_order_relaxed);
  }
}

constant uint __gpu_const_sha256d_digest_kc[64] = {1116352408, 1899447441, 3049323471, 3921009573, 961987163, 1508970993, 2453635748, 2870763221, 3624381080, 310598401, 607225278, 1426881987, 1925078388, 2162078206, 2614888103, 3248222580, 3835390401, 4022224774, 264347078, 604807628, 770255983, 1249150122, 1555081692, 1996064986, 2554220882, 2821834349, 2952996808, 3210313671, 3336571891, 3584528711, 113926993, 338241895, 666307205, 773529912, 1294757372, 1396182291, 1695183700, 1986661051, 2177026350, 2456956037, 2730485921, 2820302411, 3259730800, 3345764771, 3516065817, 3600352804, 4094571909, 275423344, 430227734, 506948616, 659060556, 883997877, 958139571, 1322822218, 1537002063, 1747873779, 1955562222, 2024104815, 2227730452, 2361852424, 2428436474, 2756734187, 3204031479, 3329325298};

[[max_total_threads_per_threadgroup(1024)]]
kernel void sha256d_digest(
  device uint *job [[buffer(0)]],
  device uint *out [[buffer(1)]],
  uint3 __tid [[thread_position_in_grid]],
  uint3 __tid_in_tg [[thread_position_in_threadgroup]],
  uint3 __tg_id [[threadgroup_position_in_grid]],
  uint3 __tg_size [[threads_per_threadgroup]],
  uint __simd_lane [[thread_index_in_simdgroup]],
  uint __simd_id [[simdgroup_index_in_threadgroup]]
) {
  uint __tg_total = __tg_size.x * __tg_size.y * __tg_size.z;
  uint nonce;
  uint m[16];
  uint a;
  uint b;
  uint c;
  uint d;
  uint e;
  uint f;
  uint g;
  uint h;
  uint i;
  uint t1;
  uint t2;
  uint x;
  uint y;
  uint o;
  uint gid = int(__tid.x);
  uint count = job[30];
  if ((gid < count)) {
    nonce = (job[29] + gid);
    m[0] = job[19];
    m[1] = job[20];
    m[2] = job[18];
    m[3] = (((((nonce >> 24) & 255) | ((nonce >> 8) & 65280)) | ((nonce & 65280) << 8)) | (nonce << 24));
    m[4] = 2147483648;
    m[5] = 0;
    m[6] = 0;
    m[7] = 0;
    m[8] = 0;
    m[9] = 0;
    m[10] = 0;
    m[11] = 0;
    m[12] = 0;
    m[13] = 0;
    m[14] = 0;
    m[15] = 640;
    a = job[8];
    b = job[9];
    c = job[10];
    d = job[11];
    e = job[12];
    f = job[13];
    g = job[14];
    h = job[15];
    i = 3;
    #pragma clang loop unroll(full)
    while ((i < 18)) {
      t1 = ((((h + ((((e >> 6) | (e << 26)) ^ ((e >> 11) | (e << 21))) ^ ((e >> 25) | (e << 7)))) + (g ^ (e & (f ^ g)))) + __gpu_const_sha256d_digest_kc[i]) + m[(i & 15)]);
      t2 = (((((a >> 2) | (a << 30)) ^ ((a >> 13) | (a << 19))) ^ ((a >> 22) | (a << 10))) + ((a & b) ^ (c & (a ^ b))));
      h = g;
      g = f;
      f = e;
      e = (d + t1);
      d = c;
      c = b;
      b = a;
      a = (t1 + t2);
      i = (i + 1);
    }
    i = 18;
    #pragma clang loop unroll(full)
    while ((i < 64)) {
      x = m[((i + 1) & 15)];
      y = m[((i + 14) & 15)];
      m[(i & 15)] = (((m[(i & 15)] + ((((x >> 7) | (x << 25)) ^ ((x >> 18) | (x << 14))) ^ (x >> 3))) + m[((i + 9) & 15)]) + ((((y >> 17) | (y << 15)) ^ ((y >> 19) | (y << 13))) ^ (y >> 10)));
      t1 = ((((h + ((((e >> 6) | (e << 26)) ^ ((e >> 11) | (e << 21))) ^ ((e >> 25) | (e << 7)))) + (g ^ (e & (f ^ g)))) + __gpu_const_sha256d_digest_kc[i]) + m[(i & 15)]);
      t2 = (((((a >> 2) | (a << 30)) ^ ((a >> 13) | (a << 19))) ^ ((a >> 22) | (a << 10))) + ((a & b) ^ (c & (a ^ b))));
      h = g;
      g = f;
      f = e;
      e = (d + t1);
      d = c;
      c = b;
      b = a;
      a = (t1 + t2);
      i = (i + 1);
    }
    m[0] = (job[0] + a);
    m[1] = (job[1] + b);
    m[2] = (job[2] + c);
    m[3] = (job[3] + d);
    m[4] = (job[4] + e);
    m[5] = (job[5] + f);
    m[6] = (job[6] + g);
    m[7] = (job[7] + h);
    m[8] = 2147483648;
    m[9] = 0;
    m[10] = 0;
    m[11] = 0;
    m[12] = 0;
    m[13] = 0;
    m[14] = 0;
    m[15] = 256;
    a = 1779033703;
    b = 3144134277;
    c = 1013904242;
    d = 2773480762;
    e = 1359893119;
    f = 2600822924;
    g = 528734635;
    h = 1541459225;
    i = 0;
    #pragma clang loop unroll(full)
    while ((i < 16)) {
      t1 = ((((h + ((((e >> 6) | (e << 26)) ^ ((e >> 11) | (e << 21))) ^ ((e >> 25) | (e << 7)))) + (g ^ (e & (f ^ g)))) + __gpu_const_sha256d_digest_kc[i]) + m[(i & 15)]);
      t2 = (((((a >> 2) | (a << 30)) ^ ((a >> 13) | (a << 19))) ^ ((a >> 22) | (a << 10))) + ((a & b) ^ (c & (a ^ b))));
      h = g;
      g = f;
      f = e;
      e = (d + t1);
      d = c;
      c = b;
      b = a;
      a = (t1 + t2);
      i = (i + 1);
    }
    i = 16;
    #pragma clang loop unroll(full)
    while ((i < 64)) {
      x = m[((i + 1) & 15)];
      y = m[((i + 14) & 15)];
      m[(i & 15)] = (((m[(i & 15)] + ((((x >> 7) | (x << 25)) ^ ((x >> 18) | (x << 14))) ^ (x >> 3))) + m[((i + 9) & 15)]) + ((((y >> 17) | (y << 15)) ^ ((y >> 19) | (y << 13))) ^ (y >> 10)));
      t1 = ((((h + ((((e >> 6) | (e << 26)) ^ ((e >> 11) | (e << 21))) ^ ((e >> 25) | (e << 7)))) + (g ^ (e & (f ^ g)))) + __gpu_const_sha256d_digest_kc[i]) + m[(i & 15)]);
      t2 = (((((a >> 2) | (a << 30)) ^ ((a >> 13) | (a << 19))) ^ ((a >> 22) | (a << 10))) + ((a & b) ^ (c & (a ^ b))));
      h = g;
      g = f;
      f = e;
      e = (d + t1);
      d = c;
      c = b;
      b = a;
      a = (t1 + t2);
      i = (i + 1);
    }
    o = (gid * 8);
    out[o] = (1779033703 + a);
    out[(o + 1)] = (3144134277 + b);
    out[(o + 2)] = (1013904242 + c);
    out[(o + 3)] = (2773480762 + d);
    out[(o + 4)] = (1359893119 + e);
    out[(o + 5)] = (2600822924 + f);
    out[(o + 6)] = (528734635 + g);
    out[(o + 7)] = (1541459225 + h);
  }
}

