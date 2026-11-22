# core/codec/image/webp_gpu — WebP lossy (VP8) fancy upsampling + Y'CbCr → RGBA on the GPU.
#
# The GPU twin of vp8_to_rgba in core/codec/image/webp_vp8 (libwebp's
# "fancy" 9-3-3-1 chroma upsampling and its 14-bit fixed-point colour
# conversion), one thread per output pixel, bit-exact with the CPU. The VP8
# reconstruction itself (intra prediction feeds on reconstructed neighbours)
# and the loop filter stay on the CPU. Frames below WEBP_GPU_MIN pixels stay
# on the CPU too.
#
use core/metal
use core/codec/gpu

WEBP_GPU_MIN = 1000000
WEBP_GPU_USED = [0]          # images converted on the GPU (tests, benchmarks)

-> webp_gpu_msl
  <<~MSL
    #include <metal_stdlib>
    using namespace metal;

    static inline uint vp8_c(int v) { return (v & -16384) == 0 ? uint(v >> 6) : (v < 0 ? 0u : 255u); }

    // p: w, h, ys, uvs
    kernel void webp_yuv(device const uchar *yp [[buffer(0)]], device const uchar *up [[buffer(1)]],
                         device const uchar *vp [[buffer(2)]], device uint *out [[buffer(3)]],
                         constant int *p [[buffer(4)]], uint gid [[thread_position_in_grid]]) {
      int w = p[0], h = p[1];
      if (int(gid) >= w * h) return;
      int X = int(gid) % w, Y = int(gid) / w;
      // the chroma row nearest this output row and the other one it blends with
      int nr, fr;
      if (Y == 0) { nr = 0; fr = 0; }
      else if ((Y & 1) == 1) {
        nr = (Y - 1) >> 1;
        fr = (Y == h - 1) ? nr : nr + 1;
      } else { nr = Y >> 1; fr = nr - 1; }
      device const uchar *nu = up + nr * p[3], *fu = up + fr * p[3];
      device const uchar *nv = vp + nr * p[3], *fv = vp + fr * p[3];
      int u, v;
      int last = (w - 1) >> 1;
      if (X == 0 || (X == w - 1 && (w & 1) == 0)) {
        int x0 = X == 0 ? 0 : last;
        u = (3 * nu[x0] + fu[x0] + 2) >> 2;
        v = (3 * nv[x0] + fv[x0] + 2) >> 2;
      } else {
        int x = (X + 1) >> 1;
        int nlu = nu[x - 1], nru = nu[x], flu = fu[x - 1], fru = fu[x];
        int nlv = nv[x - 1], nrv = nv[x], flv = fv[x - 1], frv = fv[x];
        int au = nlu + nru + flu + fru + 8, av = nlv + nrv + flv + frv + 8;
        if ((X & 1) == 1) {
          u = (((au + 2 * (nru + flu)) >> 3) + nlu) >> 1;
          v = (((av + 2 * (nrv + flv)) >> 3) + nlv) >> 1;
        } else {
          u = (((au + 2 * (nlu + fru)) >> 3) + nru) >> 1;
          v = (((av + 2 * (nlv + frv)) >> 3) + nrv) >> 1;
        }
      }
      int yy = (int(yp[Y * p[2] + X]) * 19077) >> 8;
      int r = yy + ((v * 26149) >> 8) - 14234;
      int g = yy - ((u * 6419) >> 8) - ((v * 13320) >> 8) + 8708;
      int b = yy + ((u * 33050) >> 8) - 17685;
      out[gid] = vp8_c(r) | (vp8_c(g) << 8) | (vp8_c(b) << 16) | 0xFF000000u;
    }
  MSL

WEBP_GPU_KERNELS = ["webp_yuv"]

-> webp_gpu_wanted?(w, h)
  w * h >= codec_gpu_min(WEBP_GPU_MIN) && codec_gpu_enabled?()

# vp8_to_rgba on the GPU; false (nothing written) when the kernels are not ready.
-> webp_gpu_to_rgba(yp, up, vp, ys, uvs, w, h, rgba)
  g = codec_gpu_lib("webp", webp_gpu_msl(), WEBP_GPU_KERNELS)
  return false if g == nil
  dev = g[:device]
  bufs = [metal_buffer_for(dev, yp), metal_buffer_for(dev, up), metal_buffer_for(dev, vp), metal_buffer_for(dev, rgba), codec_gpu_params(dev, [w, h, ys, uvs])]
  metal_dispatch_n(g[:queue], g[:pipes]["webp_yuv"], bufs, w * h)
  metal_sync_array(rgba, bufs[3])
  bufs.each ->(b) metal_buffer_release(b)
  WEBP_GPU_USED[0] += 1
  true
