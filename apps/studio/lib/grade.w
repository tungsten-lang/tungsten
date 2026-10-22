# studio/grade — the per-pixel look of a graded picture behind one interface with two implementations:
#
#   CpuGrade  the reference: raster.w's kernels (render.py's grade, grain, vignette, bloom, flicker, rain, fog and
#             particles), called exactly as the renderer always called them.
#   MetalGrade the same pipeline as Metal compute kernels (MSL below), one command buffer per graded picture. The
#             GPU reads the source canvases and writes the layer canvas in place (their mmap'd pixel memory is
#             wrapped as no-copy Metal buffers), so no pixel crosses the bus or a CPU loop.
#
# The renderer drives either one the same way: a source (load / lerp2 / wipe of active-picture canvases), then the
# fx in order (scale, rain, fog, particles, clip), then grade(...) into the layer. CpuGrade runs each step at once
# into the engine's float working image; MetalGrade records them and encodes everything at grade().
#
# MetalGrade computes in f32 where the CPU path uses f64 between its f32 planes, so a code value can differ by one
# where the exact value sits at a rounding boundary (`studio gradecheck` measures it). Segment keys carry the grade
# implementation (GRADE in resolve.w) so cached segments say which one made them.

use core/metal
use raster

GRADE_SHADER = <<~MSL
#include <metal_stdlib>
using namespace metal;

// k_src: source (0 load, 1 lerp2, 2 wipe) -> flicker scale -> rain -> fog [-> clip, luma when `fin`].
// pi: w h stride mode glow flags(1 scale, 2 rain, 4 fog) rain_h2 rain_off fog_fw fog_off fin
// pf: t pos scale
kernel void k_src(device const uchar *sa [[buffer(0)]], device const uchar *sb [[buffer(1)]],
                  device const float *rain [[buffer(2)]], device const float *fog [[buffer(3)]],
                  device float4 *wb [[buffer(4)]], device const int *pi [[buffer(5)]],
                  device const float *pf [[buffer(6)]], uint gid [[thread_position_in_grid]]) {
  int w = pi[0], h = pi[1];
  if (gid >= (uint)(w * h)) return;
  int x = gid % w, y = gid / w;
  int p = y * pi[2] + x * 4;
  int mode = pi[3], flags = pi[5];
  float3 v;
  float3 a = float3(sa[p], sa[p + 1], sa[p + 2]);
  if (mode == 0) {
    v = a / 255.0f;
  } else {
    float3 b = float3(sb[p], sb[p + 1], sb[p + 2]);
    if (mode == 1) {
      float t = pf[0];
      v = (a * (1.0f - t) + b * t) / 255.0f;
    } else {
      float pos = pf[1];
      float xf = float(x);
      float m = clamp((pos - xf) / 60.0f + 0.5f, 0.0f, 1.0f);
      v = (a / 255.0f) * (1.0f - m) + (b / 255.0f) * m;
      if (pi[4] != 0) {
        float d = (xf - pos) / 9.0f;
        float g = exp(-d * d) * 0.8f;
        v = clamp(v + g * float3(1.0f, 0.85f, 0.5f), 0.0f, 1.0f);
      }
    }
  }
  if (flags & 1) v = v * pf[2];
  if (flags & 2) {
    int h2 = pi[6];
    int sy = (y - pi[7]) % h2;
    if (sy < 0) sy += h2;
    float r = rain[sy * w + x] * 0.22f;
    v = v + (1.0f - v) * r * float3(0.8f, 0.9f, 1.0f);
  }
  if (flags & 4) {
    float f = fog[y * pi[8] + pi[9] + x] * 0.26f;
    v = v + (0.75f - v) * f;
  }
  float l = 0.0f;
  if (pi[10] != 0) {
    v = clamp(v, 0.0f, 1.0f);
    l = v.x * 0.2126f + v.y * 0.7152f + v.z * 0.0722f;
  }
  wb[gid] = float4(v, l);
}

// k_disc: particle discs (px, py, r, fill per particle), max coverage per pixel.  pi: w h np
kernel void k_disc(device const float4 *parts [[buffer(0)]], device float *pb [[buffer(1)]],
                   device const int *pi [[buffer(2)]], uint gid [[thread_position_in_grid]]) {
  int w = pi[0], h = pi[1], np = pi[2];
  if (gid >= (uint)(w * h)) return;
  float cx = float(gid % w) + 0.5f, cy = float(gid / w) + 0.5f;
  float best = 0.0f;
  for (int k = 0; k < np; k++) {
    float4 q = parts[k];
    float dx = cx - q.x, dy = cy - q.y, lim = q.z + 0.5f;
    if (fabs(dx) >= lim || fabs(dy) >= lim) continue;
    float cov = lim - sqrt(dx * dx + dy * dy);
    if (cov > 0.0f) {
      float v = min(cov, 1.0f) * q.w;
      best = max(best, v);
    }
  }
  pb[gid] = best;
}

// k_screen: 7x7 gaussian of the discs, screened over the image: x += (1 - x) * a * col * op [-> clip, luma].
// pi: w h fin   pf: cr cg cb op   gk: 49 weights
kernel void k_screen(device const float *pb [[buffer(0)]], device float4 *wb [[buffer(1)]],
                     device const float *gk [[buffer(2)]], device const int *pi [[buffer(3)]],
                     device const float *pf [[buffer(4)]], uint gid [[thread_position_in_grid]]) {
  int w = pi[0], h = pi[1];
  if (gid >= (uint)(w * h)) return;
  int x = gid % w, y = gid / w;
  float a = 0.0f;
  for (int j = -3; j <= 3; j++) {
    int sy = y + j;
    if (sy < 0 || sy >= h) continue;
    for (int i = -3; i <= 3; i++) {
      int sx = x + i;
      if (sx < 0 || sx >= w) continue;
      a += pb[sy * w + sx] * gk[(j + 3) * 7 + i + 3];
    }
  }
  float3 v = wb[gid].xyz;
  if (a > 0.0f) v = v + (1.0f - v) * a * float3(pf[0], pf[1], pf[2]) * pf[3];
  float l = 0.0f;
  if (pi[2] != 0) {
    v = clamp(v, 0.0f, 1.0f);
    l = v.x * 0.2126f + v.y * 0.7152f + v.z * 0.0722f;
  }
  wb[gid] = float4(v, l);
}

// k_grid: per cell of the gw x gh bloom grid, the mean of floor(255 * clip((l - thr) / (1 - thr))) over the pixels
// (x, y) with x * gw / w == gx and y * gh / h == gy (integer division), as rs_grade1.  pi: w h gw gh  pf: thr
kernel void k_grid(device const float4 *wb [[buffer(0)]], device float *grid [[buffer(1)]],
                   device const int *pi [[buffer(2)]], device const float *pf [[buffer(3)]],
                   uint gid [[thread_position_in_grid]]) {
  int w = pi[0], h = pi[1], gw = pi[2], gh = pi[3];
  if (gid >= (uint)(gw * gh)) return;
  int gx = gid % gw, gy = gid / gw;
  int x0 = (gx * w + gw - 1) / gw, x1 = ((gx + 1) * w + gw - 1) / gw;
  int y0 = (gy * h + gh - 1) / gh, y1 = ((gy + 1) * h + gh - 1) / gh;
  float thr = pf[0], inv = 1.0f / (1.0f - thr);
  float s = 0.0f, c = 0.0f;
  for (int y = y0; y < y1; y++) {
    for (int x = x0; x < x1; x++) {
      float hi = clamp((wb[y * w + x].w - thr) * inv, 0.0f, 1.0f);
      s += floor(hi * 255.0f);
      c += 1.0f;
    }
  }
  grid[gid] = c > 0.0f ? s / c : 0.0f;
}

// k_blur: one separable gaussian pass on the grid, edges clamped.  pi: gw gh rad dir(0 rows, 1 columns)
// wt: 2 rad + 1 normalized weights
kernel void k_blur(device const float *src [[buffer(0)]], device float *dst [[buffer(1)]],
                   device const float *wt [[buffer(2)]], device const int *pi [[buffer(3)]],
                   uint gid [[thread_position_in_grid]]) {
  int gw = pi[0], gh = pi[1], rad = pi[2], dir = pi[3];
  if (gid >= (uint)(gw * gh)) return;
  int x = gid % gw, y = gid / gw;
  float acc = 0.0f;
  for (int k = -rad; k <= rad; k++) {
    int sx = x, sy = y;
    if (dir == 0) sx = clamp(x + k, 0, gw - 1); else sy = clamp(y + k, 0, gh - 1);
    acc += src[sy * gw + sx] * wt[k + rad];
  }
  dst[gid] = acc;
}

// k_grade: rs_grade2. pi: w h gw gh vw vh vx0 gox goy fade_rows stride ox oy
// pf: gp[0..14] fade_to alpha
kernel void k_grade(device const float4 *wb [[buffer(0)]], device const float *grid [[buffer(1)]],
                    device const float *vig [[buffer(2)]], device const float *grain [[buffer(3)]],
                    device uchar *dst [[buffer(4)]], device const int *pi [[buffer(5)]],
                    device const float *pf [[buffer(6)]], uint gid [[thread_position_in_grid]]) {
  int w = pi[0], h = pi[1];
  if (gid >= (uint)(w * h)) return;
  int x = gid % w, y = gid / w;
  int gw = pi[2], gh = pi[3], vw = pi[4], vh = pi[5], vx = pi[6] + x, fade_rows = pi[9];
  float sxs = float(gw) / float(vw), sys = float(gh) / float(vh);
  float fy = max((float(y) + 0.5f) * sys - 0.5f, 0.0f);
  int y0 = int(floor(fy));
  int y1 = min(y0 + 1, gh - 1);
  float ty = fy - float(y0);
  float fx = max((float(vx) + 0.5f) * sxs - 0.5f, 0.0f);
  int x0 = int(floor(fx));
  int x1 = min(x0 + 1, gw - 1);
  float tx = fx - float(x0);
  float bl = ((grid[y0 * gw + x0] * (1.0f - tx) + grid[y0 * gw + x1] * tx) * (1.0f - ty) +
              (grid[y1 * gw + x0] * (1.0f - tx) + grid[y1 * gw + x1] * tx) * ty) / 255.0f;
  float4 px = wb[gid];
  float l = px.w;
  float sh = (1.0f - l) * (1.0f - l);
  float hl = l * l;
  float3 c = px.xyz + sh * float3(pf[0], pf[1], pf[2]) + hl * float3(pf[3], pf[4], pf[5]);
  float3 s = clamp(c * c * (3.0f - 2.0f * c), 0.0f, 1.0f);
  float cmix = pf[6];
  c = c * (1.0f - cmix) + s * cmix;
  c = l + (c - l) * pf[7];
  c = c + bl * float3(pf[8], pf[9], pf[10]);
  c = pf[11] + c * pf[12];
  float v = vig[y * vw + vx];
  float gr = grain[((y + pi[8]) % vh) * vw + (vx + pi[7]) % vw] * (pf[13] + pf[14] * l * (1.0f - l));
  c = clamp(c * v + gr, 0.0f, 1.0f);
  float rowfade = 1.0f;
  if (fade_rows > 0 && y >= h - fade_rows) {
    int k = y - (h - fade_rows);
    rowfade = 1.0f + (pf[15] - 1.0f) * float(k) / float(fade_rows - 1);
  }
  c = c * (rowfade * pf[16]);
  int p = (pi[12] + y) * pi[10] + (pi[11] + x) * 4;
  dst[p] = uchar(floor(c.x * 255.0f + 0.5f));
  dst[p + 1] = uchar(floor(c.y * 255.0f + 0.5f));
  dst[p + 2] = uchar(floor(c.z * 255.0f + 0.5f));
  dst[p + 3] = 255;
}
MSL

# ---------------------------------------------------------------------------------------------- choice

# The Metal grade's id in recipes: bump it whenever the kernels' output changes.
METAL_GRADE_ID = "metal1"

# The grade implementation in force: STUDIO_GRADE=cpu|metal, else the cut's "grade_impl", else metal when a Metal
# device is present. Returns "cpu" or METAL_GRADE_ID.
-> grade_impl(cut)
  g = env("STUDIO_GRADE")
  g = get(cut, "grade_impl", "") if g == nil || g == ""
  g = "metal" if g == nil || g == ""
  die("unknown grade implementation " + g + " (cpu | metal)") if g != "cpu" && g != "metal"
  return "cpu" if g == "cpu" || !metal_available?()
  METAL_GRADE_ID

-> metal_available?
  ccall("w_metal_device_default") != nil

# ---------------------------------------------------------------------------------------------- CPU

# The reference: the engine's buffers and raster.w's kernels, exactly as render.py's port always ran them.
+ CpuGrade
  -> new(@aw, @ah, @wb, @lb, @grid, @gcnt, @gtmp, @gp, @pbuf, @bbuf, @gk)

  -> id
    "cpu"

  -> load(src, stride, w, h)
    rs_load(src, stride, w, h, @wb)

  -> lerp2(a, b, stride, w, h, t)
    rs_lerp2(a, b, stride, w, h, t, @wb)

  -> wipe(a, b, stride, w, h, pos, glow)
    rs_wipe(a, b, stride, w, h, pos, glow, @wb)

  -> scale(n, s)
    rs_scale(@wb, n, s)

  -> rain(field, key, h2, off)
    rs_rain(@wb, @aw, @ah, field, h2, off)

  -> fog(field, key, fw, off)
    rs_fog(@wb, @aw, @ah, field, fw, off)

  -> particles(parts, np, t, snow)
    rs_particles(@wb, @aw, @ah, parts, np, t, snow, @pbuf, @bbuf, @gk)

  -> clip(n)
    rs_clip(@wb, n)

  # Grade the working image (w x h) into the destination canvas at (ox, oy): bloom grid, blur, then the grade.
  -> grade(pl, gi, gox, goy, sigma, w, h, vx0, fade_rows, fade_to, alpha, dst, stride, ox, oy)
    gw = w / 8
    gh = h / 8
    rs_grade1(@wb, w, h, @lb, @grid, @gcnt, gw, gh, @gp[15])
    rs_blur_grid(@grid, @gtmp, gw, gh, sigma)
    rs_grade2(@wb, @lb, w, h, @grid, gw, gh, @gp, pl[0], pl[1][gi], @aw, @ah, vx0, gox, goy, fade_rows, fade_to, alpha, dst, stride, ox, oy)
    nil

# ---------------------------------------------------------------------------------------------- Metal

-> mg_particle_pos(parts, k, w, h, t, snow, out) (f64[] i64 i64 i64 f64 i64 f32[]) i64
  wf = w ## f64
  hf = h ## f64
  x0 = parts[k * 5]
  y0 = parts[k * 5 + 1]
  sz = parts[k * 5 + 2]
  sp = parts[k * 5 + 3]
  ph = parts[k * 5 + 4]
  px = ~0.0
  py = ~0.0
  r = ~0.0
  fill = ~0.0
  if snow != 0
    py = (y0 * hf + t * (~40.0 + ~70.0 * sp)) % hf
    px = (x0 * wf + ~25.0 * Math.sin(t * ~0.8 + ph * ~6.28) + t * ~12.0) % wf
    r = ~1.0 + sz * ~3.0
    fill = (~120.0 + ~120.0 * sz) / ~255.0
  else
    px = (x0 * wf + t * (~6.0 + ~10.0 * sp) + ~18.0 * Math.sin(t * ~0.3 + ph * ~6.28)) % wf
    py = (y0 * hf - t * (~3.0 + ~6.0 * sp) + ~10.0 * Math.cos(t * ~0.4 + ph * ~6.28)) % hf
    r = ~0.8 + sz * ~2.2
    fill = (~60.0 + ~120.0 * sz) / ~255.0
  px = px + wf if px < ~0.0
  py = py + hf if py < ~0.0
  out[k * 4] = px ## f32
  out[k * 4 + 1] = py ## f32
  out[k * 4 + 2] = r ## f32
  out[k * 4 + 3] = fill ## f32
  0

# A canvas's pixel memory as a u8 view (the Metal wrap needs a typed array; the canvas owns the memory).
-> mg_canvas_view(ptr, nbytes)
  p ## i64 = ptr
  n ## i64 = nbytes
  ccall("w_array_view_raw", p, 8, n)

+ MetalGrade
  -> new(@aw, @ah, @gk, @gp)
    @dev = metal_device()
    @lib = metal_compile_source(@dev, GRADE_SHADER, true)
    @k_src = metal_pipeline(@lib, "k_src")
    @k_disc = metal_pipeline(@lib, "k_disc")
    @k_screen = metal_pipeline(@lib, "k_screen")
    @k_grid = metal_pipeline(@lib, "k_grid")
    @k_blur = metal_pipeline(@lib, "k_blur")
    @k_grade = metal_pipeline(@lib, "k_grade")
    @q = metal_queue(@dev)
    n = @aw * @ah
    @wb = metal_buffer(@dev, n * 16)
    @pb = metal_buffer(@dev, n * 4)
    @grid = metal_buffer(@dev, (@aw / 8) * (@ah / 8) * 4 + 64)
    @gtmp = metal_buffer(@dev, (@aw / 8) * (@ah / 8) * 4 + 64)
    @dummy = metal_buffer(@dev, 64)
    @gkb = metal_buffer(@dev, 49 * 4)
    gkv = metal_buffer_view(@gkb, -32, 49)
    j = 0
    while j < 49
      gkv[j] = @gk[j]
      j += 1
    # parameter blocks, one per dispatch of a picture's command buffer (the GPU reads them when it runs):
    # 0 k_src, 1-4 two particle passes (k_disc, k_screen), 5 k_grid, 6-7 k_blur, 8 k_grade
    @pi = []
    @piv = []
    @pf = []
    @pfv = []
    s = 0
    while s < 9
      bi = metal_buffer(@dev, 64 * 4)
      bf = metal_buffer(@dev, 64 * 4)
      @pi.push(bi)
      @piv.push(metal_buffer_view(bi, 33, 64))
      @pf.push(bf)
      @pfv.push(metal_buffer_view(bf, -32, 64))
      s += 1
    @wt = metal_buffer(@dev, 64 * 4)
    @wtv = metal_buffer_view(@wt, -32, 64)
    @parts = []
    @partsv = []
    s = 0
    while s < 2
      bp = metal_buffer(@dev, 256 * 16)
      @parts.push(bp)
      @partsv.push(metal_buffer_view(bp, -32, 256 * 4))
      s += 1
    @canvases = {}
    @fields = {}
    @planes = {}
    reset()

  -> id
    METAL_GRADE_ID

  -> reset
    @mode = 0
    @sa = nil
    @sb = nil
    @stride = 0
    @t = ~0.0
    @pos = ~0.0
    @glow = 0
    @scale = ~1.0
    @flags = 0
    @rain = nil
    @fog = nil
    @rain_h2 = 1
    @rain_off = 0
    @fog_fw = 1
    @fog_off = 0
    @np = []
    @snow = []
    nil

  # The no-copy Metal buffer over the first h rows of a canvas's pixels (made once per canvas and extent; the
  # engine's canvases live as long as it does).
  -> canvas_buffer(ptr, stride, h)
    key = ptr.to_s + ":" + h.to_s
    b = @canvases[key]
    if b == nil
      page = 16384
      bytes = ((stride * h + page - 1) / page) * page
      b = metal_buffer_for(@dev, mg_canvas_view(ptr, bytes))
      @canvases[key] = b
    b

  -> field_buffer(field, key)
    b = @fields[key]
    if b == nil
      b = metal_buffer_for(@dev, field)
      @fields[key] = b
    b

  -> load(src, stride, w, h)
    reset()
    @mode = 0
    @sa = canvas_buffer(src, stride, h)
    @sb = @sa
    @stride = stride

  -> lerp2(a, b, stride, w, h, t)
    reset()
    @mode = 1
    @sa = canvas_buffer(a, stride, h)
    @sb = canvas_buffer(b, stride, h)
    @stride = stride
    @t = t

  -> wipe(a, b, stride, w, h, pos, glow)
    reset()
    @mode = 2
    @sa = canvas_buffer(a, stride, h)
    @sb = canvas_buffer(b, stride, h)
    @stride = stride
    @pos = pos
    @glow = glow

  -> scale(n, s)
    @scale = @scale * s
    @flags = @flags | 1

  -> rain(field, key, h2, off)
    @rain = field_buffer(field, key)
    @rain_h2 = h2
    @rain_off = off
    @flags = @flags | 2

  -> fog(field, key, fw, off)
    @fog = field_buffer(field, key)
    @fog_fw = fw
    @fog_off = off
    @flags = @flags | 4

  -> particles(parts, np, t, snow)
    slot = @np.size
    die("MetalGrade: at most two particle passes") if slot >= 2
    pv = @partsv[slot]
    k = 0
    while k < np
      mg_particle_pos(parts, k, @aw, @ah, t, snow, pv)
      k += 1
    @np.push(np)
    @snow.push(snow)

  -> clip(n)
    nil

  -> plane_buffers(pl)
    key = pl[2]
    b = @planes[key]
    if b == nil
      gb = []
      pl[1].each ->(g)
        gb.push(metal_buffer_for(@dev, g))
      b = [metal_buffer_for(@dev, pl[0]), gb]
      @planes[key] = b
    b

  -> threads(n)
    (n + 255) / 256

  -> dispatch(pipe, bufs, n)
    groups = threads(n)
    tpg = 256
    ccall("w_metal_dispatch_groups", @q, pipe, bufs, groups, tpg)

  # Encode the whole picture (source, fx, bloom grid, blur, grade) into one command buffer and wait for it.
  -> grade(pl, gi, gox, goy, sigma, w, h, vx0, fade_rows, fade_to, alpha, dst, stride, ox, oy)
    n = w * h
    gw = w / 8
    gh = h / 8
    pb = plane_buffers(pl)
    out = canvas_buffer(dst, stride, oy + h)
    rad = Math.ceil(sigma * ~3.0).to_i
    die("MetalGrade: bloom radius " + rad.to_s + " over 31") if rad > 31
    ws = ~0.0
    k = 0 - rad
    while k <= rad
      ws += Math.exp(~0.0 - (k * k + ~0.0) / (~2.0 * sigma * sigma))
      k += 1
    k = 0 - rad
    while k <= rad
      @wtv[k + rad] = Math.exp(~0.0 - (k * k + ~0.0) / (~2.0 * sigma * sigma)) / ws
      k += 1
    npass = @np.size
    # k_src
    pi = @piv[0]
    pi[0] = w
    pi[1] = h
    pi[2] = @stride
    pi[3] = @mode
    pi[4] = @glow
    pi[5] = @flags
    pi[6] = @rain_h2
    pi[7] = @rain_off
    pi[8] = @fog_fw
    pi[9] = @fog_off
    pi[10] = npass == 0 ? 1 : 0
    pf = @pfv[0]
    pf[0] = @t
    pf[1] = @pos
    pf[2] = @scale
    rb = @rain
    rb = @dummy if rb == nil
    fb = @fog
    fb = @dummy if fb == nil
    ccall("w_metal_batch_begin", @q)
    dispatch(@k_src, [@sa, @sb, rb, fb, @wb, @pi[0], @pf[0]], n)
    s = 0
    while s < npass
      pi = @piv[1 + s * 2]
      pi[0] = w
      pi[1] = h
      pi[2] = @np[s]
      dispatch(@k_disc, [@parts[s], @pb, @pi[1 + s * 2]], n)
      pi = @piv[2 + s * 2]
      pi[0] = w
      pi[1] = h
      pi[2] = s == npass - 1 ? 1 : 0
      pf = @pfv[2 + s * 2]
      if @snow[s] != 0
        pf[0] = ~0.9
        pf[1] = ~0.95
        pf[2] = ~1.0
        pf[3] = ~0.55
      else
        pf[0] = ~1.0
        pf[1] = ~0.85
        pf[2] = ~0.6
        pf[3] = ~0.35
      dispatch(@k_screen, [@pb, @wb, @gkb, @pi[2 + s * 2], @pf[2 + s * 2]], n)
      s += 1
    pi = @piv[5]
    pi[0] = w
    pi[1] = h
    pi[2] = gw
    pi[3] = gh
    pf = @pfv[5]
    pf[0] = @gp[15]
    dispatch(@k_grid, [@wb, @grid, @pi[5], @pf[5]], gw * gh)
    pi = @piv[6]
    pi[0] = gw
    pi[1] = gh
    pi[2] = rad
    pi[3] = 0
    dispatch(@k_blur, [@grid, @gtmp, @wt, @pi[6]], gw * gh)
    pi = @piv[7]
    pi[0] = gw
    pi[1] = gh
    pi[2] = rad
    pi[3] = 1
    dispatch(@k_blur, [@gtmp, @grid, @wt, @pi[7]], gw * gh)
    pi = @piv[8]
    pi[0] = w
    pi[1] = h
    pi[2] = gw
    pi[3] = gh
    pi[4] = @aw
    pi[5] = @ah
    pi[6] = vx0
    pi[7] = gox
    pi[8] = goy
    pi[9] = fade_rows
    pi[10] = stride
    pi[11] = ox
    pi[12] = oy
    pf = @pfv[8]
    j = 0
    while j < 15
      pf[j] = @gp[j]
      j += 1
    pf[15] = fade_to
    pf[16] = alpha
    dispatch(@k_grade, [@wb, @grid, pb[0], pb[1][gi], out, @pi[8], @pf[8]], n)
    ccall("w_metal_batch_commit", @q)
    reset()
    nil
