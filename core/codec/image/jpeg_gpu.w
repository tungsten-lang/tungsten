# core/codec/image/jpeg_gpu — the JPEG decoder's IDCT, upsampling and colour
# conversion on the GPU (Huffman / arithmetic decoding stays on the CPU).
#
#   jpeg_gpu_finish(dec_state…) → true when the GPU produced the RGBA (see JpegDecoder#finish)
#
# Bit-exact with the CPU path in core/codec/image/jpeg: the same libjpeg
# "islow" integer IDCT (32-bit arithmetic for blocks whose dequantised
# coefficients are in the range valid 8-bit data produces, 64-bit for the
# rest, so even damaged files match the CPU's i64 maths), the same MCU-local
# "fancy" 2x1 / 2x2 chroma upsampling and the same Q16 YCbCr → RGB. One
# command buffer per image: one IDCT dispatch per component (one thread per
# 8x8 block), then one thread per output pixel for upsampling + colour.
# Used for 8-bit 3-component YCbCr / RGB images of at least JPEG_GPU_MIN
# pixels whose chroma is full size, 2x1 or 2x2; everything else (greyscale,
# CMYK, 12-bit, other subsampling, small images) stays on the CPU.
#
use core/metal
use core/codec/gpu

JPEG_GPU_MIN = 1000000
JPEG_GPU_USED = [0]          # images converted on the GPU (tests, benchmarks)

-> jpeg_gpu_msl
  <<~MSL
    #include <metal_stdlib>
    using namespace metal;

    template <typename T>
    static void jpg_idct_block(device const int *co, int o, device const int *qt, int qo,
                               device uchar *out, int oo, int stride) {
      T ws[64];
      for (int c = 0; c < 8; c++) {
        int i = o + c, q = qo + c;
        if (co[i + 8] == 0 && co[i + 16] == 0 && co[i + 24] == 0 && co[i + 32] == 0 &&
            co[i + 40] == 0 && co[i + 48] == 0 && co[i + 56] == 0) {
          T dc = (T(co[i]) * T(qt[q])) << 2;
          for (int k = 0; k < 8; k++) ws[c + 8 * k] = dc;
          continue;
        }
        T z2 = T(co[i + 16]) * T(qt[q + 16]);
        T z3 = T(co[i + 48]) * T(qt[q + 48]);
        T z1 = (z2 + z3) * 4433;
        T tmp2 = z1 - z3 * 15137;
        T tmp3 = z1 + z2 * 6270;
        z2 = T(co[i]) * T(qt[q]);
        z3 = T(co[i + 32]) * T(qt[q + 32]);
        T tmp0 = (z2 + z3) << 13;
        T tmp1 = (z2 - z3) << 13;
        T tmp10 = tmp0 + tmp3, tmp13 = tmp0 - tmp3, tmp11 = tmp1 + tmp2, tmp12 = tmp1 - tmp2;
        tmp0 = T(co[i + 56]) * T(qt[q + 56]);
        tmp1 = T(co[i + 40]) * T(qt[q + 40]);
        tmp2 = T(co[i + 24]) * T(qt[q + 24]);
        tmp3 = T(co[i + 8]) * T(qt[q + 8]);
        z1 = tmp0 + tmp3; z2 = tmp1 + tmp2; z3 = tmp0 + tmp2;
        T z4 = tmp1 + tmp3;
        T z5 = (z3 + z4) * 9633;
        tmp0 = tmp0 * 2446; tmp1 = tmp1 * 16819; tmp2 = tmp2 * 25172; tmp3 = tmp3 * 12299;
        z1 = z1 * -7373; z2 = z2 * -20995; z3 = z3 * -16069 + z5; z4 = z4 * -3196 + z5;
        tmp0 += z1 + z3; tmp1 += z2 + z4; tmp2 += z2 + z3; tmp3 += z1 + z4;
        ws[c] = (tmp10 + tmp3 + 1024) >> 11;
        ws[c + 56] = (tmp10 - tmp3 + 1024) >> 11;
        ws[c + 8] = (tmp11 + tmp2 + 1024) >> 11;
        ws[c + 48] = (tmp11 - tmp2 + 1024) >> 11;
        ws[c + 16] = (tmp12 + tmp1 + 1024) >> 11;
        ws[c + 40] = (tmp12 - tmp1 + 1024) >> 11;
        ws[c + 24] = (tmp13 + tmp0 + 1024) >> 11;
        ws[c + 32] = (tmp13 - tmp0 + 1024) >> 11;
      }
      for (int r = 0; r < 8; r++) {
        int w = r * 8;
        device uchar *p = out + oo + r * stride;
        if (ws[w + 1] == 0 && ws[w + 2] == 0 && ws[w + 3] == 0 && ws[w + 4] == 0 &&
            ws[w + 5] == 0 && ws[w + 6] == 0 && ws[w + 7] == 0) {
          uchar v = uchar(clamp(T((ws[w] + 16) >> 5) + 128, T(0), T(255)));
          for (int k = 0; k < 8; k++) p[k] = v;
          continue;
        }
        T z2 = ws[w + 2], z3 = ws[w + 6];
        T z1 = (z2 + z3) * 4433;
        T tmp2 = z1 - z3 * 15137;
        T tmp3 = z1 + z2 * 6270;
        T tmp0 = (ws[w] + ws[w + 4]) << 13;
        T tmp1 = (ws[w] - ws[w + 4]) << 13;
        T tmp10 = tmp0 + tmp3, tmp13 = tmp0 - tmp3, tmp11 = tmp1 + tmp2, tmp12 = tmp1 - tmp2;
        tmp0 = ws[w + 7]; tmp1 = ws[w + 5]; tmp2 = ws[w + 3]; tmp3 = ws[w + 1];
        z1 = tmp0 + tmp3; z2 = tmp1 + tmp2; z3 = tmp0 + tmp2;
        T z4 = tmp1 + tmp3;
        T z5 = (z3 + z4) * 9633;
        tmp0 = tmp0 * 2446; tmp1 = tmp1 * 16819; tmp2 = tmp2 * 25172; tmp3 = tmp3 * 12299;
        z1 = z1 * -7373; z2 = z2 * -20995; z3 = z3 * -16069 + z5; z4 = z4 * -3196 + z5;
        tmp0 += z1 + z3; tmp1 += z2 + z4; tmp2 += z2 + z3; tmp3 += z1 + z4;
        p[0] = uchar(clamp(((tmp10 + tmp3 + 131072) >> 18) + 128, T(0), T(255)));
        p[7] = uchar(clamp(((tmp10 - tmp3 + 131072) >> 18) + 128, T(0), T(255)));
        p[1] = uchar(clamp(((tmp11 + tmp2 + 131072) >> 18) + 128, T(0), T(255)));
        p[6] = uchar(clamp(((tmp11 - tmp2 + 131072) >> 18) + 128, T(0), T(255)));
        p[2] = uchar(clamp(((tmp12 + tmp1 + 131072) >> 18) + 128, T(0), T(255)));
        p[5] = uchar(clamp(((tmp12 - tmp1 + 131072) >> 18) + 128, T(0), T(255)));
        p[3] = uchar(clamp(((tmp13 + tmp0 + 131072) >> 18) + 128, T(0), T(255)));
        p[4] = uchar(clamp(((tmp13 - tmp0 + 131072) >> 18) + 128, T(0), T(255)));
      }
    }

    // p: base, bw, nbx, nby, qo, out_off, stride
    kernel void jpg_idct(device const int *co [[buffer(0)]], device const int *qt [[buffer(1)]],
                         device uchar *out [[buffer(2)]], constant int *p [[buffer(3)]],
                         uint gid [[thread_position_in_grid]]) {
      int nbx = p[2];
      int by = int(gid) / nbx, bx = int(gid) % nbx;
      if (by >= p[3]) return;
      int o = p[0] + (by * p[1] + bx) * 64;
      int qo = p[4];
      // 32-bit maths is exact while every dequantised coefficient stays within
      // what 8-bit data produces; anything larger (damaged data) takes 64 bits
      bool wide = false;
      for (int k = 0; k < 64; k++) {
        int v = co[o + k] * qt[qo + k];
        if (abs(co[o + k]) > 32767 || v > 16383 || v < -16384) { wide = true; break; }
      }
      int oo = p[5] + by * 8 * p[6] + bx * 8;
      if (wide) jpg_idct_block<long>(co, o, qt, qo, out, oo, p[6]);
      else jpg_idct_block<int>(co, o, qt, qo, out, oo, p[6]);
    }

    // chroma sample at output (x, y): kind 0 full size, 1 2x1, 2 2x2 (MCU-local fancy upsampling)
    static int jpg_chroma(device const uchar *pl, int off, int ss, int kind, int cw, int chh, int x, int y) {
      if (kind == 0) return pl[off + y * ss + x];
      int i = x >> 1;
      bool odd = (x & 1) != 0;
      if (kind == 1) {
        device const uchar *s = pl + off + y * ss;
        if (!odd) return i == 0 ? s[0] : (s[i] * 3 + s[i - 1] + 1) >> 2;
        return i == cw - 1 ? s[i] : (s[i] * 3 + s[i + 1] + 2) >> 2;
      }
      int r = y >> 1;
      int o = (y & 1) ? r + 1 : r - 1;
      r = min(r, chh - 1);
      o = clamp(o, 0, chh - 1);
      if ((o >> 3) != (r >> 3)) o = r;
      device const uchar *s0 = pl + off + r * ss;
      device const uchar *s1 = pl + off + o * ss;
      int k = i >> 3;
      int n8 = min(8, cw - k * 8);
      int li = i - k * 8;
      int t = s0[i] * 3 + s1[i];
      if (n8 == 1) return odd ? (t * 4 + 7) >> 4 : (t * 4 + 8) >> 4;
      if (li == 0) return odd ? (t * 3 + s0[i + 1] * 3 + s1[i + 1] + 7) >> 4 : (t * 4 + 8) >> 4;
      if (li == n8 - 1) return odd ? (t * 4 + 7) >> 4 : (t * 3 + s0[i - 1] * 3 + s1[i - 1] + 8) >> 4;
      return odd ? (t * 3 + s0[i + 1] * 3 + s1[i + 1] + 7) >> 4 : (t * 3 + s0[i - 1] * 3 + s1[i - 1] + 8) >> 4;
    }

    // p: w, h, mode, y_off, y_stride, cb_off, cb_stride, cb_kind, cb_cw, cb_chh, cr_off, cr_stride, cr_kind, cr_cw, cr_chh
    kernel void jpg_color(device const uchar *pl [[buffer(0)]], device uint *out [[buffer(1)]],
                          constant int *p [[buffer(2)]], uint gid [[thread_position_in_grid]]) {
      int w = p[0];
      if (int(gid) >= w * p[1]) return;
      int x = int(gid) % w, y = int(gid) / w;
      int yy = pl[p[3] + y * p[4] + x];
      int cb = jpg_chroma(pl, p[5], p[6], p[7], p[8], p[9], x, y);
      int cr = jpg_chroma(pl, p[10], p[11], p[12], p[13], p[14], x, y);
      int r, g, b;
      if (p[2] == 1) {
        r = yy; g = cb; b = cr;
      } else {
        cb -= 128; cr -= 128;
        r = clamp(yy + ((91881 * cr + 32768) >> 16), 0, 255);
        g = clamp(yy + ((-22554 * cb - 46802 * cr + 32768) >> 16), 0, 255);
        b = clamp(yy + ((116130 * cb + 32768) >> 16), 0, 255);
      }
      out[gid] = uint(r) | (uint(g) << 8) | (uint(b) << 16) | 0xFF000000u;
    }
  MSL

JPEG_GPU_KERNELS = ["jpg_idct", "jpg_color"]

# Whether the GPU path applies: 3 components, 8-bit, YCbCr or RGB, luma at full
# size and each chroma full size, 2x1 or 2x2 (with the default MCU-local
# upsampling settings), at least min_px pixels.
-> jpeg_gpu_eligible?(ncomp, prec, mode, ci, hmax, vmax, w, h)
  return false if ncomp != 3 || prec != 8 || (mode != 0 && mode != 1)
  return false if w * h < codec_gpu_min(JPEG_GPU_MIN)
  return false if ci[2] != hmax || ci[3] != vmax
  c = 1
  while c < 3
    hs = ci[c * 16 + 2]
    vs = ci[c * 16 + 3]
    k = jpeg_gpu_kind(hs, vs, hmax, vmax)
    return false if k < 0
    c += 1
  true

-> jpeg_gpu_kind(hs, vs, hmax, vmax)
  return 0 if hs == hmax && vs == vmax
  return -1 if hmax % hs != 0 || vmax % vs != 0
  fx = hmax / hs
  fy = vmax / vs
  return 1 if fx == 2 && fy == 1
  return 2 if fx == 2 && fy == 2 && JPEG_H2V2[0] == 1 && JPEG_H2V2[1] == 1 && JPEG_H2V2[2] == 1
  -1

# A coefficient array for an image: page-aligned (bound to the GPU without a
# copy) when the GPU path may be used.
-> jpeg_gpu_coefs(total, gpu)
  gpu ? metal_array(33, total) : i32[total]

# IDCT + upsample + colour on the GPU into rgba (w * h * 4). False (nothing
# written) when the kernels are not ready; the caller runs the CPU path.
-> jpeg_gpu_run(coefs, ci, qt, w, h, hmax, vmax, mode, rgba)
  g = codec_gpu_lib("jpeg", jpeg_gpu_msl(), JPEG_GPU_KERNELS)
  return false if g == nil
  dev = g[:device]
  q = g[:queue]
  # planes: one u8 buffer, component c at offs[c] (stride bw * 8)
  offs = []
  tot = 0
  c = 0
  while c < 3
    b = c * 16
    offs.push(tot)
    tot += ci[b + 1] * 8 * ci[b + 11] * 8
    c += 1
  planes = metal_buffer(dev, tot)
  qtb = metal_buffer(dev, 4 * 256)
  i = 0
  while i < 256
    metal_buffer_write_i32(qtb, i, qt[i])
    i += 1
  cob = metal_buffer_for(dev, coefs)
  out = metal_buffer_for(dev, rgba)
  pbs = []
  metal_batch_begin(q)
  c = 0
  while c < 3
    b = c * 16
    bw = ci[b + 1]
    bh = ci[b + 11]
    nbx = ci[b + 7] < bw ? ci[b + 7] + 1 : bw
    nby = ci[b + 8] < bh ? ci[b + 8] + 1 : bh
    pb = codec_gpu_params(dev, [ci[b], bw, nbx, nby, ci[b + 6] * 64, offs[c], bw * 8])
    pbs.push(pb)
    metal_dispatch_n(q, g[:pipes]["jpg_idct"], [cob, qtb, planes, pb], nbx * nby)
    c += 1
  metal_batch_barrier(q)
  pv = [w, h, mode, offs[0], ci[1] * 8]
  c = 1
  while c < 3
    b = c * 16
    hs = ci[b + 2]
    vs = ci[b + 3]
    pv.push(offs[c])
    pv.push(ci[b + 1] * 8)
    pv.push(jpeg_gpu_kind(hs, vs, hmax, vmax))
    pv.push((w * hs + hmax - 1) / hmax)
    pv.push((h * vs + vmax - 1) / vmax)
    c += 1
  pc = codec_gpu_params(dev, pv)
  pbs.push(pc)
  metal_dispatch_n(q, g[:pipes]["jpg_color"], [planes, out, pc], w * h)
  metal_batch_commit(q)
  metal_sync_array(rgba, out)
  JPEG_GPU_USED[0] += 1
  pbs.push(planes)
  pbs.push(qtb)
  pbs.push(cob)
  pbs.push(out)
  pbs.each ->(b) metal_buffer_release(b)
  true
