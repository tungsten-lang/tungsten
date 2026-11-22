# core/codec/gpu — shared Metal plumbing for the codecs' GPU stages.
#
#   g = codec_gpu_lib("jpeg", msl_source, ["jpg_idct", "jpg_color"])
#   g == nil → use the CPU path (no Metal, disabled, or the kernels are still compiling)
#   g[:device], g[:queue], g[:pipes]["jpg_idct"]
#
# Kernel libraries compile on a background thread the first time they are
# asked for, so no decode waits for the Metal compiler: the request that
# starts the compile waits at most CODEC_GPU_WAIT_MS for it (macOS caches
# compiled shaders by source, so after the first run on a machine this is a
# few ms and the GPU is used at once), and decodes run on the CPU until it is
# ready. Every GPU stage is bit-exact with its CPU counterpart.
#
# Environment: TUNGSTEN_CODEC_GPU=0 disables every GPU stage;
# TUNGSTEN_CODEC_GPU_MIN=<pixels> overrides each stage's size threshold (0:
# use the GPU for every image, as the specs do to check bit-exactness).
#
use core/metal
use core/mutex

CODEC_GPU_WAIT_MS = 40
CODEC_GPU_STATE = [nil]      # nil: not probed; false: unavailable; else {device:, queue:}
CODEC_GPU_LIBS = {}          # name → [status (:compiling / :ready / :failed), channel, pipes]
CODEC_GPU_LOCK = Mutex.new

-> codec_gpu_enabled?
  s = CODEC_GPU_STATE[0]
  return s != false if s != nil
  CODEC_GPU_LOCK.lock
  if CODEC_GPU_STATE[0] == nil
    st = false
    if env("TUNGSTEN_CODEC_GPU") != "0"
      begin
        d = metal_device()
        st = {device: d, queue: metal_queue(d)}
      rescue e
        st = false
    CODEC_GPU_STATE[0] = st
  CODEC_GPU_LOCK.unlock
  CODEC_GPU_STATE[0] != false

# The pixel count from which a stage uses the GPU (its default, or the env override).
-> codec_gpu_min(default)
  v = env("TUNGSTEN_CODEC_GPU_MIN")
  v == nil || v.size == 0 ? default : v.to_i

-> codec_gpu_lib(name, source, kernels)
  return nil if !codec_gpu_enabled?()
  e = nil
  start = false
  CODEC_GPU_LOCK.lock
  e = CODEC_GPU_LIBS[name]
  if e == nil
    e = [:compiling, Channel.unbounded, nil]
    CODEC_GPU_LIBS[name] = e
    start = true
  CODEC_GPU_LOCK.unlock
  if start
    st = CODEC_GPU_STATE[0]
    ch = e[1]
    dev = st[:device]
    Thread.new ->
      res = nil
      begin
        lib = metal_compile_source(dev, source)
        pipes = {}
        kernels.each ->(k) pipes[k] = metal_pipeline(lib, k)
        res = pipes
      rescue err
        res = false
      ch.send(res)
  return codec_gpu_entry(e) if e[0] != :compiling
  r = start ? e[1].receive_result(CODEC_GPU_WAIT_MS) : e[1].try_receive
  if r.received?
    codec_gpu_settle(e, r.value)
  codec_gpu_entry(e)

-> codec_gpu_settle(e, v)
  CODEC_GPU_LOCK.lock
  if e[0] == :compiling
    e[2] = v == false ? nil : v
    e[0] = v == false ? :failed : :ready
  CODEC_GPU_LOCK.unlock
  nil

-> codec_gpu_entry(e)
  return nil if e[0] != :ready
  st = CODEC_GPU_STATE[0]
  {device: st[:device], queue: st[:queue], pipes: e[2]}

# Block until a library has finished compiling (tests, benchmarks).
-> codec_gpu_wait(name, source, kernels)
  g = codec_gpu_lib(name, source, kernels)
  while g == nil && CODEC_GPU_LIBS[name] != nil && CODEC_GPU_LIBS[name][0] == :compiling
    r = CODEC_GPU_LIBS[name][1].receive_result(1000)
    codec_gpu_settle(CODEC_GPU_LIBS[name], r.value) if r.received?
    g = codec_gpu_entry(CODEC_GPU_LIBS[name])
  g

# A 4-byte-per-element parameter buffer from an Array of Integers.
-> codec_gpu_params(dev, vals)
  b = metal_buffer(dev, 4 * vals.size)
  i = 0
  while i < vals.size
    metal_buffer_write_i32(b, i, vals[i])
    i += 1
  b
