# core/codec/video/yuv_gpu — VideoFrame → a window's GPU texture, converted on the GPU.
#
#   vt = YuvTexture.new(window)
#   vt.upload(frame)          # true: frame is now in vt.id; false: not GPU-presentable (use yuv_to_rgba)
#   layers: kind GFX_LAYER_TEX with tex id vt.id (vt.width x vt.height source pixels)
#   vt.free
#
# The frame's planes are copied into R8 (8-bit) or R16 (9..16-bit) textures,
# one memcpy per plane; the compositor's fragment shader does the Y'CbCr → RGB
# conversion (same matrix / range coefficients as core/codec/video/yuv) with
# bilinear chroma upsampling while it draws the quad, so a frame costs no CPU
# colour conversion, no RGBA buffer and no CanvasImage. Wide-gamut and HDR
# frames get core/codec/cicp's conversion (EOTF, primaries matrix, PQ/HLG
# shoulder, sRGB OETF) in the same shader.
#
use core/graphics
use core/codec/video/yuv

# True when the GPU can present the frame: a chroma layout the shader knows
# and a colour description it can convert (everything yuv_to_rgba handles).
-> yuv_gpu_presentable?(frame)
  ch = frame.chroma
  ch == "420" || ch == "422" || ch == "444" || ch == "400"

YUV_GPU_CICP = {}

# [transfer, m00 .. m22] for frames yuv_cicp would convert (nil: output is sRGB).
-> yuv_gpu_cicp(frame)
  p = frame.primaries
  t = frame.transfer
  return nil if (p == 1 || p == 2) && (t == 1 || t == 2 || t == 6 || t == 13 || t == 14 || t == 15)
  key = p * 1000 + t
  return YUV_GPU_CICP[key] if YUV_GPU_CICP.has_key?(key)
  tr = cicp_transform(p, t)
  r = nil
  if tr != nil
    m = tr.matrix
    r = [tr.transfer.to_f]
    i = 0
    while i < 9
      r.push(m[i].to_f)
      i += 1
  YUV_GPU_CICP[key] = r
  r

# The shader parameters for gfx_tex_upload_yuv (15, or 25 with a CICP conversion).
-> yuv_gpu_params(frame, cw, ch)
  c = frame.crop
  cx = c == nil ? 0 : c[0]
  cy = c == nil ? 0 : c[1]
  chm = frame.chroma
  sx = chm == "420" || chm == "422" ? 1 : 0
  sy = chm == "420" ? 1 : 0
  st = frame.strides
  d = frame.bit_depth
  scale = d > 8 ? ~65535.0 : ~255.0
  k = yuv_coeffs(frame)
  grey = chm == "400" || frame.planes.size < 3
  q = ~65536.0
  r = nil
  if grey
    ys = k == nil ? ~1.0 : k[0].to_f / q
    yo = k == nil ? ~0.0 : k[1].to_f
    r = [st[0].to_f, (st.size > 1 ? st[1] : st[0]).to_f, cx.to_f, cy.to_f, ~0.0, ~0.0, scale, ys, yo, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~1.0]
  elsif k == nil
    # identity matrix (GBR planes): code (2^d - 1) maps to 255
    g = ~255.0 / ((1 << d) - 1).to_f
    r = [st[0].to_f, st[1].to_f, cx.to_f, cy.to_f, (cx >> sx).to_f, (cy >> sy).to_f, scale, g, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~2.0]
  else
    r = [st[0].to_f, st[1].to_f, cx.to_f, cy.to_f, (cx >> sx).to_f, (cy >> sy).to_f, scale,
      k[0].to_f / q, k[1].to_f, k[6].to_f, k[2].to_f / q, k[3].to_f / q, k[4].to_f / q, k[5].to_f / q, ~0.0]
  cc = yuv_gpu_cicp(frame)
  if cc != nil
    cc.each ->(v) r.push(v)
  r

+ YuvTexture
  ro :id, :width, :height, :uploads

  -> new(@win)
    @id = nil
    @width = 0
    @height = 0
    @cw = 0
    @ch = 0
    @sixteen = false
    @uploads = 0

  # Copy frame into the texture (re-created when the size or depth changed).
  # false when the frame is not GPU-presentable (the caller converts on the CPU).
  -> upload(frame)
    return false if !yuv_gpu_presentable?(frame)
    c = frame.crop
    w = c == nil ? frame.width : c[2]
    h = c == nil ? frame.height : c[3]
    return false if w <= 0 || h <= 0
    chm = frame.chroma
    sx = chm == "420" || chm == "422" ? 1 : 0
    sy = chm == "420" ? 1 : 0
    cw = chm == "400" ? 1 : (w + (1 << sx) - 1) >> sx
    ch = chm == "400" ? 1 : (h + (1 << sy) - 1) >> sy
    if chm != "400" && frame.planes.size >= 3
      # never read past a plane: clamp to what the strides / sizes hold
      cx0 = c == nil ? 0 : c[0] >> sx
      cy0 = c == nil ? 0 : c[1] >> sy
      cs = frame.strides[1]
      cw = cs - cx0 if cx0 + cw > cs
      rows = frame.planes[1].size / cs
      ch = rows - cy0 if cy0 + ch > rows
      return false if cw <= 0 || ch <= 0
    sixteen = frame.bit_depth > 8
    if @id == nil || w != @width || h != @height || cw != @cw || ch != @ch || sixteen != @sixteen
      gfx_tex_free(@win, @id) if @id != nil
      @id = gfx_tex_new_yuv(@win, w, h, cw, ch, sixteen)
      @width = w
      @height = h
      @cw = cw
      @ch = ch
      @sixteen = sixteen
    pl = frame.planes
    planes = pl.size >= 3 ? [pl[0], pl[1], pl[2]] : [pl[0], pl[0], pl[0]]
    gfx_tex_upload_yuv(@win, @id, planes, yuv_gpu_params(frame, cw, ch))
    @uploads += 1
    true

  -> free
    gfx_tex_free(@win, @id) if @id != nil
    @id = nil
    nil
