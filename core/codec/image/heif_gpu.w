# core/codec/image/heif_gpu — HEIF/AVIF chroma upsampling + Y'CbCr → sRGB8 on the GPU.
#
# The GPU twin of core/codec/image/heif_color's common path (hc_upsample in
# every mode, including grid tiles whose chroma must not be interpolated
# across tile edges, then hc_convert_int: Kr/Kb or monochrome matrices, any
# bit depth, limited or full range, pictures already in sRGB). One thread per
# output pixel; bit-exact with the CPU (same integer maths). Pictures that
# need colour management, GBR / YCgCo matrices or are smaller than
# HEIF_GPU_MIN pixels stay on the CPU.
#
use core/metal
use core/codec/gpu

HEIF_GPU_MIN = 1000000
HEIF_GPU_USED = [0]          # images converted on the GPU (tests, benchmarks)

-> heif_gpu_msl
  <<~MSL
    #include <metal_stdlib>
    using namespace metal;

    // the chroma value hc_upsample stores for output (x, y) (16x the sample)
    static long hc_up(device const ushort *src, int cw, int ch, int x, int y,
                      int ssx, int ssy, int mode, int tw, int th) {
      int cy0 = y >> ssy, cy1 = cy0;
      long wy0 = 4, wy1 = 0;
      if (ssy == 1 && mode == 3) {
        if ((y & 1) == 1) {
          wy0 = 2; wy1 = 2;
          cy1 = cy0 + 1;
          if (cy1 >= ch) cy1 = ch - 1;
          if (th > 0 && ((y + 1) % th) == 0) cy1 = cy0;
        }
      } else if (ssy == 1 && mode != 1) {
        wy0 = 3; wy1 = 1;
        cy1 = (y & 1) == 0 ? cy0 - 1 : cy0 + 1;
        if (cy1 < 0) cy1 = 0;
        if (cy1 >= ch) cy1 = ch - 1;
      }
      if (cy0 >= ch) cy0 = ch - 1;
      device const ushort *r0 = src + cy0 * cw;
      device const ushort *r1 = src + cy1 * cw;
      if (ssx == 0) return (r0[x] * wy0 + r1[x] * wy1) * 4;
      int cx0 = x >> 1;
      if (mode == 1) {
        if (cx0 >= cw) cx0 = cw - 1;
        return (r0[cx0] * wy0 + r1[cx0] * wy1) * 4;
      }
      if (mode == 2 || mode == 3) {
        if (cx0 >= cw) cx0 = cw - 1;
        long a = r0[cx0] * wy0 + r1[cx0] * wy1;
        if ((x & 1) == 0) return a * 4;
        int cx1 = cx0 + 1;
        if (cx1 >= cw) cx1 = cw - 1;
        if (tw > 0 && ((x + 1) % tw) == 0) cx1 = cx0;
        long b = r0[cx1] * wy0 + r1[cx1] * wy1;
        return (a + b) * 2;
      }
      int cx1;
      if ((x & 1) == 0) { cx1 = cx0 - 1; if (cx1 < 0) cx1 = 0; }
      else { cx1 = cx0 + 1; if (cx1 >= cw) cx1 = cw - 1; }
      if (cx0 >= cw) cx0 = cw - 1;
      long a = r0[cx0] * wy0 + r1[cx0] * wy1;
      long b = r0[cx1] * wy0 + r1[cx1] * wy1;
      return a * 3 + b;
    }

    // p: w, h, cw, ch, ssx, ssy, mode, tw, th, mono, ky, krv, kbu, kgu, kgv, yoff, coff
    kernel void heif_ycc(device const ushort *yp [[buffer(0)]], device const ushort *cbp [[buffer(1)]],
                         device const ushort *crp [[buffer(2)]], device uint *out [[buffer(3)]],
                         constant int *p [[buffer(4)]], uint gid [[thread_position_in_grid]]) {
      int w = p[0];
      if (int(gid) >= w * p[1]) return;
      int x = int(gid) % w, y = int(gid) / w;
      long yy = (long(yp[gid]) - p[15]) * long(p[10]) + 524288;
      long r = yy, g = yy, b = yy;
      if (p[9] == 0) {
        long u = hc_up(cbp, p[2], p[3], x, y, p[4], p[5], p[6], p[7], p[8]) - p[16];
        long v = hc_up(crp, p[2], p[3], x, y, p[4], p[5], p[6], p[7], p[8]) - p[16];
        r = yy + long(p[11]) * v;
        b = yy + long(p[12]) * u;
        g = yy - long(p[13]) * u - long(p[14]) * v;
      }
      int ri = int(clamp(r >> 20, 0l, 255l));
      int gi = int(clamp(g >> 20, 0l, 255l));
      int bi = int(clamp(b >> 20, 0l, 255l));
      out[gid] = uint(ri) | (uint(gi) << 8) | (uint(bi) << 16) | 0xFF000000u;
    }
  MSL

HEIF_GPU_KERNELS = ["heif_ycc"]

# Upsample + convert pic into rgba on the GPU (ik as hc_convert_int's, um the
# upsampling mode). False when the kernels are not ready or the picture is
# below the size threshold: the caller converts on the CPU.
-> heif_gpu_convert(pic, ik, um, rgba)
  w = pic.width
  h = pic.height
  return false if w * h < codec_gpu_min(HEIF_GPU_MIN)
  g = codec_gpu_lib("heif", heif_gpu_msl(), HEIF_GPU_KERNELS)
  return false if g == nil
  dev = g[:device]
  q = g[:queue]
  yb = metal_buffer_for(dev, pic.planes[0])
  mono = pic.mono
  cbb = mono ? yb : metal_buffer_for(dev, pic.planes[1])
  crb = mono ? yb : metal_buffer_for(dev, pic.planes[2])
  out = metal_buffer_for(dev, rgba)
  pv = [w, h, mono ? 1 : pic.cw, mono ? 1 : pic.ch, mono ? 0 : pic.ssx, mono ? 0 : pic.ssy, um,
    pic.tile_w, pic.tile_h, mono ? 1 : 0, ik[0], ik[1], ik[2], ik[3], ik[4], ik[5], ik[6]]
  pb = codec_gpu_params(dev, pv)
  metal_dispatch_n(q, g[:pipes]["heif_ycc"], [yb, cbb, crb, out, pb], w * h)
  metal_sync_array(rgba, out)
  HEIF_GPU_USED[0] += 1
  metal_buffer_release(yb)
  if !mono
    metal_buffer_release(cbb)
    metal_buffer_release(crb)
  metal_buffer_release(out)
  metal_buffer_release(pb)
  true
