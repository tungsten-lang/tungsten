# Scaler — high-quality resampling of RGBA frames: Lanczos-3, bicubic or
# bilinear, with premultiplied alpha, crops and pads, on the GPU (Metal), the
# CPU vector units (vImage) or plain C.
#
#   sc = Scaler.new(1920, 1080, 1280, 720)                       # a 720p share copy
#   small = sc.scale(canvas)                                     # -> a new ByteArray (RGBA, 1280 x 720)
#   sc.scale(canvas, buf)                                        # or into a u8[] / ByteArray / address you own
#   up = Scaler.new(1920, 1080, 3840, 2160, filter: :lanczos3)   # 4K from a 1080p render
#   v = Scaler.new(1920, 1080, 1080, 1920, fit: :cover)          # vertical: centre crop, no bars
#   p = Scaler.new(1920, 1080, 1080, 1920, fit: :contain)        # vertical: the whole frame, black bars
#
# Geometry. crop: [x, y, w, h] is the source region (fractional values are
# exact, not rounded), rect: [x, y, w, h] the destination region it lands in;
# fill: [r, g, b, a] (default opaque black) colours the rest. fit: computes
# both from the sizes: :stretch (default: whole source onto the whole
# destination), :contain (the whole source, centred, bars of fill colour) or
# :cover (fill the destination, cropping the source's centre). Pixel centres
# map exactly: destination x samples the source at
# crop_x + (x - rect_x + 0.5) * crop_w / rect_w - 0.5, so a 2x upscale is
# phase-correct and a crop is not shifted by half a pixel.
#
# Filters (separable, normalised, edge samples repeated): :lanczos3 (default;
# sinc windowed by sinc, radius 3), :bicubic (Keys a = -0.5, Catmull-Rom,
# radius 2), :bilinear. When downscaling the kernel is widened by the scale
# factor, so it stays a low-pass filter at the output rate (no aliasing).
#
# Alpha. alpha: :premultiplied (default; what Canvas holds) filters the four
# channels as they are, then clamps each colour to the alpha (ringing could
# otherwise push it above, which is not a valid premultiplied pixel).
# :straight premultiplies on load and divides on store, so transparent
# pixels' colours do not bleed into their neighbours. :opaque ignores the
# input alpha and writes 255; :none treats the channels as plain data. Any
# channel order with alpha last works (RGBA, BGRA).
#
# Backends: :auto (default) picks the fastest available for the job (Metal,
# measured in doc/media.md); :metal, :vimage (Accelerate's vImageScale:
# Lanczos-3, whole-pixel crops only) and :cpu (multithreaded C) force one.
# Metal and the CPU share the weight tables and agree to within one code;
# vImage has its own Lanczos. Scaler.backends lists what this machine has.

+ Scaler
  ro :src_w, :src_h, :width, :height, :crop, :rect, :filter, :handle

  # Scaler.new(src_w, src_h, width, height, filter: :lanczos3, fit: :stretch,
  # crop: nil, rect: nil, fill: [0, 0, 0, 255], alpha: :premultiplied,
  # backend: :auto, layout: :rgba)
  -> new(@src_w, @src_h, @width, @height, opts = {})
    @filter = Scaler.opt(opts, :filter, "lanczos3").to_s
    g = Scaler.fit(@src_w, @src_h, @width, @height, Scaler.opt(opts, :fit, "stretch"))
    @crop = Scaler.opt(opts, :crop, g[:crop])
    @rect = Scaler.opt(opts, :rect, g[:rect])
    fill = Scaler.opt(opts, :fill, [0, 0, 0, 255])
    spec = [@src_w, @src_h, @width, @height, @filter, @crop, @rect, fill, Scaler.opt(opts, :alpha, "premultiplied").to_s,
            Scaler.opt(opts, :backend, "auto").to_s, Scaler.opt(opts, :layout, "rgba").to_s]
    @handle = ccall("w_media_scaler_new", spec)

  -> .opt(opts, key, fallback)
    if opts == nil || !opts.has_key?(key) || opts[key] == nil
      return fallback
    opts[key]

  # Crop and rect for a fit mode: {crop: [x, y, w, h], rect: [x, y, w, h]}.
  # :contain and :cover keep the destination rect on even pixels (4:2:0
  # video); :cover's crop may be fractional.
  -> .fit(sw, sh, dw, dh, mode = "stretch")
    m = mode.to_s
    if m == "contain" || m == "fit" || m == "pad"
      # the larger of the two scale factors that fit
      if dw * sh <= dh * sw
        rw = dw
        rh = ((dw * sh * 2 + sw * 2) / (sw * 4)) * 2
      else
        rh = dh
        rw = ((dh * sw * 2 + sh * 2) / (sh * 4)) * 2
      rw = dw if rw > dw
      rh = dh if rh > dh
      rx = ((dw - rw) / 4) * 2
      ry = ((dh - rh) / 4) * 2
      return {crop: [0, 0, sw, sh], rect: [rx, ry, rw, rh]}
    if m == "cover" || m == "fill" || m == "crop"
      if dw * sh >= dh * sw
        cw = sw.to_f
        ch = (sw * dh).to_f / dw.to_f
      else
        ch = sh.to_f
        cw = (sh * dw).to_f / dh.to_f
      return {crop: [(sw.to_f - cw) / ~2.0, (sh.to_f - ch) / ~2.0, cw, ch], rect: [0, 0, dw, dh]}
    if m != "stretch"
      raise "Scaler: unknown fit '[m]' (stretch, contain, cover)"
    {crop: [0, 0, sw, sh], rect: [0, 0, dw, dh]}

  # Backends available here, fastest first: some of "metal", "vimage", "cpu".
  -> .backends
    ccall("w_media_scaler_info", nil, "backends")

  # Scale one frame. src: a Canvas, an address, a ByteArray / u8[] or an
  # Mmap (src_stride: bytes per row, default width x 4). dst: nil (returns
  # a new ByteArray), a Canvas of the output size, an address, a ByteArray
  # or u8[] (dst_stride default width x 4). Returns dst.
  -> scale(src, dst = nil, src_stride = nil, dst_stride = nil)
    ss = src_stride
    sp = src
    if type(src) == "Canvas"
      sp = src.data_pointer
      ss = src.stride
    ds = dst_stride
    dp = dst
    if dst != nil && type(dst) == "Canvas"
      dp = dst.data_pointer
      ds = dst.stride
    r = ccall("w_media_scaler_run", @handle, sp, 0, ss, dp, 0, ds)
    dst == nil ? r : dst

  # The backend the last scale used (or will use): "metal", "vimage" or "cpu".
  -> backend
    ccall("w_media_scaler_info", @handle, "backend")

  # [taps x, taps y]
  -> taps
    ccall("w_media_scaler_info", @handle, "taps")

  -> runs
    ccall("w_media_scaler_info", @handle, "runs")

  # Wall seconds spent scaling so far.
  -> seconds
    ccall("w_media_scaler_info", @handle, "seconds")

  # Per output column (or row): [first source sample, weights...].
  -> weights(axis = :x)
    ccall("w_media_scaler_info", @handle, axis.to_s == "y" ? "weights_y" : "weights_x")

  # Free the native plan (and its GPU buffers) now; there are no finalizers.
  -> free
    ccall("w_media_scaler_free", @handle)
