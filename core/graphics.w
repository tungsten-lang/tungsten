# core/graphics.w — Tungsten surface for windowed Metal rendering.
#
# The compute facade in core/metal.w can dispatch `@gpu fn` kernels into
# buffers but has no way to show them. This module is the windowing half:
# a thin facade over runtime/graphics.m (NSWindow + CAMetalLayer + input)
# plus a couple of small data structures (Camera, key constants) for
# building an interactive 3D viewer.
#
# Rendering model: a `@gpu` kernel renders one pixel per thread into an
# RGBA8 Metal buffer (one u32 per pixel, 0xAABBGGRR little-endian to match
# MTLPixelFormatRGBA8Unorm), and `gfx_present` blits that buffer into the
# window's next drawable. No vertex/fragment pipeline — compute straight
# to the screen.
#
# Load with `use core/graphics` (not autoloaded). macOS only — the
# w_gfx_* symbols live in runtime/graphics.m, compiled on darwin.

use core/metal

# ---- Window lifecycle ----

# Open a window of `width` x `height` pixels titled `title`, backed by a
# CAMetalLayer on `device` (get one from `metal_device()`). Returns an
# opaque window handle. macOS only.
-> gfx_window(device, title, width, height)
  ccall("w_gfx_window_new", device, title, width, height)

# Pump the OS event queue once — call at the top of every frame so key /
# mouse / close events are delivered into the window's input state.
-> gfx_poll(window)
  ccall("w_gfx_poll", window)

# True while the named hardware key is held. Use the KEY_* constants
# below (hardware keyCodes, so WASD tracks physical key positions
# regardless of keyboard layout).
-> gfx_key_down(window, keycode)
  ccall("w_gfx_key_down", window, keycode)

# Relative mouse motion (in points) accumulated since the last call;
# reading resets the accumulator. Exactly the per-frame delta a
# mouse-look camera wants. dx = horizontal, dy = vertical.
-> gfx_mouse_dx(window)
  ccall("w_gfx_mouse_dx", window)

-> gfx_mouse_dy(window)
  ccall("w_gfx_mouse_dy", window)

# True once the window has been asked to close (red button / Cmd-Q).
-> gfx_should_close(window)
  ccall("w_gfx_should_close", window)

# Hide the cursor and decouple it from mouse motion for FPS-style look
# (relative deltas keep flowing without the cursor hitting screen edges).
# Accepts a bool; the runtime shim takes an int, so normalize here.
-> gfx_set_mouse_capture(window, enabled)
  ccall("w_gfx_set_mouse_capture", window, enabled ? 1 : 0)

# Present an RGBA8 buffer (width*height u32 pixels, row-major) to the
# window by blitting it into the next drawable. Call once per frame after
# the render kernel has finished writing the buffer.
-> gfx_present(window, buffer, width, height)
  ccall("w_gfx_present", window, buffer, width, height)

# ---- Hardware keyCode constants (ANSI layout positions) ----

KEY_A     =  0
KEY_S     =  1
KEY_D     =  2
KEY_W     = 13
KEY_Q     = 12
KEY_E     = 14
KEY_SPACE = 49
KEY_ESC   = 53
KEY_LEFT  = 123
KEY_RIGHT = 124
KEY_DOWN  = 125
KEY_UP    = 126
KEY_SHIFT =  56

# ---- Camera: position + yaw/pitch, with a quaternion orientation ----
#
# A first-person fly/walk camera. State is a Vec3 position plus yaw
# (around world +Y) and pitch (around the camera's local right axis).
# The basis vectors are derived with trig (robust + branch-free); the
# `orientation` method exposes the same rotation as a unit Quaternion
# from the hypercomplex tower, which the renderer hands to the GPU as a
# scalar-last QuaternionMetal (float4) when it needs the rotation on
# device.
+ Camera
  - data
    rw pos       # Vec3<f64> eye position
    rw yaw       # radians, heading around +Y (0 = looking toward -Z)
    rw pitch     # radians, clamped to roughly +/- 85 degrees

  -> new(@pos, @yaw, @pitch)

  # Look direction (unit Vec3). Right-handed: yaw 0 looks down -Z.
  -> forward
    cp = Math.cos(pitch)
    Vec3<f64>.new([
      Math.sin(yaw) * cp,
      Math.sin(pitch),
      ~0.0 - Math.cos(yaw) * cp
    ] ## f64[3])

  # Right vector (unit, horizontal — independent of pitch).
  -> right
    Vec3<f64>.new([
      Math.cos(yaw),
      ~0.0,
      Math.sin(yaw)
    ] ## f64[3])

  # Up vector = right × forward (re-orthonormalized via cross product).
  -> up
    self.right.cross(self.forward)

  # The camera orientation as a unit Quaternion: yaw about +Y composed
  # with pitch about the local right axis. Hands the hypercomplex tower a
  # real job and gives the renderer a single float4 to upload.
  -> orientation
    qyaw = Quaternion<f64>.from_axis_angle(Vec3<f64>.new([~0.0, ~1.0, ~0.0] ## f64[3]), yaw)
    qpitch = Quaternion<f64>.from_axis_angle(Vec3<f64>.new([~1.0, ~0.0, ~0.0] ## f64[3]), pitch)
    (qyaw * qpitch).normalize

  # Advance yaw/pitch by mouse deltas (radians), clamping pitch so the
  # camera can't flip over the poles. Mutates in place (`@field = …`).
  -> look(dyaw, dpitch)
    @yaw = yaw + dyaw
    np = pitch + dpitch
    if np > ~1.48
      np = ~1.48
    if np < (~0.0 - ~1.48)
      np = ~0.0 - ~1.48
    @pitch = np

  # Move along the camera basis: f forward, s strafe-right, u world-up.
  -> move(f, s, u)
    fwd = self.forward
    rt = self.right
    @pos = Vec3<f64>.new([
      pos.x + fwd.x * f + rt.x * s,
      pos.y + fwd.y * f + rt.y * s + u,
      pos.z + fwd.z * f + rt.z * s
    ] ## f64[3])
