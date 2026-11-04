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
# Load with `use core/graphics` (not autoloaded). The real backend is macOS
# only; other targets link weak runtime stubs that raise when called. Window
# creation, polling, and presentation must remain on the process main thread.

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
# the render kernel has finished writing the buffer. Presentation is
# asynchronous: callers must not assume the buffer is safe to overwrite when
# this function returns. Returns true when a drawable was presented, false if
# the layer had no drawable available.
-> gfx_present(window, buffer, width, height)
  ccall("w_gfx_present", window, buffer, width, height)

# Present the same RGBA8 buffer and wait for the blit command to finish. When
# this function returns, the caller may safely reuse or overwrite `buffer`.
# This blocking path is intended for deterministic CPU-authored previews;
# throughput-oriented render loops can continue to use `gfx_present` with
# their own in-flight resource management. It returns the same success flag.
-> gfx_present_wait(window, buffer, width, height)
  ccall("w_gfx_present_wait", window, buffer, width, height)

# ---- Editor-style windows: flags, events, menus, panels ----
#
# An editor wants more than held keys and mouse deltas: where the pointer
# is, which button went down and how many clicks, scroll and trackpad
# deltas, typed text with its modifiers, the window's size and backing
# scale as they change, a menu bar, and open/save panels. All of it is
# below; the game-style calls above keep working on every window.
#
#   win = gfx_window_open(metal_device(), "Title", 1200, 800, GFX_HIDPI + GFX_KEEP_OPEN)   # flags add up (bits)
#   gfx_menu_add(win, "File", "Open…", "o", 0, 1)
#   while running
#     gfx_wait(win, ~0.25)                      # sleeps until input arrives
#     e = gfx_next_event(win)
#     while e != nil
#       …                                       # e[:kind] is a GFX_EV_* constant
#       e = gfx_next_event(win)
#     # draw only when something changed; present gfx_pixel_width x gfx_pixel_height
#
# Positions are points from the content's top-left (multiply by
# gfx_scale(win) for pixels on a GFX_HIDPI window).

# Window flags for gfx_window_open.
GFX_HIDPI     = 1   # drawable = content points x backing scale, following resizes
GFX_HIDDEN    = 2   # never shown or activated (specs, headless runs)
GFX_BGRA      = 4   # BGRA8 layer: present CoreGraphics/cairo-order pixels as they are
GFX_KEEP_OPEN = 8   # close button and Quit post GFX_EV_CLOSE; gfx_close closes

# Event kinds (e[:kind]).
GFX_EV_NONE       = 0
GFX_EV_KEY_DOWN   = 1   # :key (keyCode), :mods, :repeat, :text (the key's characters)
GFX_EV_KEY_UP     = 2
GFX_EV_TEXT       = 3   # :text typed (printable, not a Command/Control shortcut)
GFX_EV_MOUSE_DOWN = 4   # :x, :y, :button (0 left, 1 right, 2+ other), :clicks, :mods
GFX_EV_MOUSE_UP   = 5
GFX_EV_MOUSE_MOVE = 6   # :x, :y, :dx, :dy (moves coalesce)
GFX_EV_MOUSE_DRAG = 7   # :x, :y, :dx, :dy, :button
GFX_EV_SCROLL     = 8   # :dx, :dy points (natural direction), :precise (trackpad), :phase
GFX_EV_MAGNIFY    = 9   # :dx = magnification step (pinch), :phase
GFX_EV_RESIZE     = 10  # :w, :h content points, :scale
GFX_EV_CLOSE      = 11  # :id 1 when it came from Quit
GFX_EV_MENU       = 12  # :id of the item
GFX_EV_FOCUS      = 13  # :id 1 gained, 0 lost
GFX_EV_MODS       = 14  # modifier keys changed: :mods

# Modifier bits (e[:mods]; gfx_menu_add's mods).
GFX_MOD_SHIFT = 1
GFX_MOD_CTRL  = 2
GFX_MOD_ALT   = 4
GFX_MOD_CMD   = 8
GFX_MOD_CAPS  = 16
GFX_MOD_FN    = 32

# Cursors (gfx_set_cursor).
GFX_CURSOR_ARROW       = 0
GFX_CURSOR_IBEAM       = 1
GFX_CURSOR_POINTING    = 2
GFX_CURSOR_OPEN_HAND   = 3
GFX_CURSOR_CLOSED_HAND = 4
GFX_CURSOR_CROSSHAIR   = 5
GFX_CURSOR_RESIZE_LR   = 6
GFX_CURSOR_RESIZE_UD   = 7

# Open a window of `width` x `height` content points with GFX_* flags, added
# together (GFX_HIDPI + GFX_BGRA; `|` is the unit pipe in Tungsten).
-> gfx_window_open(device, title, width, height, flags)
  ccall("w_gfx_window_open", device, title, width, height, flags)

# Pump the OS queue, sleeping up to `seconds` until input arrives (at once
# when events are already queued). Returns how many events are queued.
-> gfx_wait(window, seconds)
  ccall("w_gfx_wait", window, seconds)

# The oldest queued event as a hash, or nil when the queue is empty.
-> gfx_next_event(window)
  k = ccall("w_gfx_next_event", window)
  if k == 0
    return nil
  {kind: k, x: ccall("w_gfx_event_field", window, 1), y: ccall("w_gfx_event_field", window, 2), dx: ccall("w_gfx_event_field", window, 3), dy: ccall("w_gfx_event_field", window, 4), button: ccall("w_gfx_event_field", window, 5), clicks: ccall("w_gfx_event_field", window, 6), mods: ccall("w_gfx_event_field", window, 7), key: ccall("w_gfx_event_field", window, 8), repeat: ccall("w_gfx_event_field", window, 9), phase: ccall("w_gfx_event_field", window, 10), precise: ccall("w_gfx_event_field", window, 11), w: ccall("w_gfx_event_field", window, 12), h: ccall("w_gfx_event_field", window, 13), scale: ccall("w_gfx_event_field", window, 14), id: ccall("w_gfx_event_field", window, 15), text: ccall("w_gfx_event_text", window)}

# Every queued event, oldest first.
-> gfx_events(window)
  out = []
  e = gfx_next_event(window)
  while e != nil
    out.push(e)
    e = gfx_next_event(window)
  out

# The drawable in pixels (what to present), the content in points, and the
# backing scale between them (1 unless the window was opened GFX_HIDPI).
-> gfx_pixel_width(window)
  ccall("w_gfx_metric", window, 0)

-> gfx_pixel_height(window)
  ccall("w_gfx_metric", window, 1)

-> gfx_point_width(window)
  ccall("w_gfx_metric", window, 2)

-> gfx_point_height(window)
  ccall("w_gfx_metric", window, 3)

-> gfx_scale(window)
  ccall("w_gfx_metric", window, 4)

-> gfx_set_title(window, title)
  ccall("w_gfx_set_title", window, title)

# Resize the content to width x height points (a GFX_EV_RESIZE follows).
-> gfx_set_size(window, width, height)
  ccall("w_gfx_set_size", window, width, height)

-> gfx_set_cursor(window, kind)
  ccall("w_gfx_set_cursor", window, kind)

# Close the window now (after a GFX_EV_CLOSE the program has handled).
-> gfx_close(window)
  ccall("w_gfx_close", window)

# Add an item to the top-level menu `menu` (made on first use, left to
# right in the order first used, between the application menu and Window),
# or to a submenu by path ("File/Open Recent": made on first use at the end
# of its parent). `key` is one character or a name (up, down, left, right,
# return, tab, space, delete, escape, home, end, pageup, pagedown, f1-f12),
# "" for none; `mods` GFX_MOD_* bits (0 = Command, -1 = the plain key).
# Choosing it posts GFX_EV_MENU with `id`.
#
# The first item a program adds also makes the standard menu bar around it,
# wired to AppKit's own roles: the application menu (named by the bundle's
# CFBundleName, else the process): About <App> (the standard About panel:
# CFBundleShortVersionString and the build, CFBundleVersion), Settings…
# (Command-comma: GFX_EV_MENU with id GFX_MENU_SETTINGS), Services, Hide
# <App> (Command-H), Hide Others (Option-Command-H), Show All, Quit <App>
# (Command-Q: terminate:, which a GFX_KEEP_OPEN program receives as
# GFX_EV_CLOSE with :id 1 to confirm, also from the Dock and at log out);
# Window: Minimize (Command-M), Zoom, Bring All to Front; Help: <App> Help
# (Command-?: GFX_EV_MENU with id GFX_MENU_HELP).
-> gfx_menu_add(window, menu, title, key, mods, id)
  ccall("w_gfx_menu_add", window, menu, title, key, mods, id)

-> gfx_menu_separator(window, menu)
  ccall("w_gfx_menu_add", window, menu, "-", "", 0, 0)

# Remove every item of a menu or submenu (by name or path), to refill it
# (an Open Recent list); the menu stays in place.
-> gfx_menu_clear(window, menu)
  ccall("w_gfx_menu_clear", window, menu)

# The titles of a menu's items ("" a separator); with menu "" the menu bar's
# menus, left to right.
-> gfx_menu_items(window, menu)
  ccall("w_gfx_menu_items", window, menu)

# The menu event ids of the runtime's standard items.
GFX_MENU_SETTINGS = -2   # <App> > Settings… (Command-comma)
GFX_MENU_HELP     = -3   # Help > <App> Help

# Enable/disable (1/0) and check/uncheck (1/0) the item `id`; -1 leaves
# either as it is. False when no item has that id.
-> gfx_menu_set(window, id, enabled, checked)
  ccall("w_gfx_menu_set", window, id, enabled, checked)

# Modal panels: the chosen path, or nil when cancelled. `types` is a comma
# list of extensions ("arr,txt"; "" for any), `dir` a starting folder ("").
-> gfx_open_panel(window, title, types, dir)
  ccall("w_gfx_open_panel", window, title, types, dir)

-> gfx_save_panel(window, title, name, types, dir)
  ccall("w_gfx_save_panel", window, title, name, types, dir)

# The next panel returns `path` (nil: cancelled) without showing: specs and
# scripted runs.
-> gfx_panel_answer(window, path)
  ccall("w_gfx_panel_answer", window, path)

# A modal alert: `buttons` a comma list ("Save,Don't Save,Cancel", the first
# the default); returns the chosen button's index (-1 on a hidden window).
-> gfx_alert(window, message, info, buttons)
  ccall("w_gfx_alert", window, message, info, buttons)

# The next alert returns `index` without showing.
-> gfx_alert_answer(window, index)
  ccall("w_gfx_alert_answer", window, index)

# A modal prompt for a line of text: an alert with a field holding `dflt`;
# [button index, text] ([-1, dflt] on a hidden window with no scripted answer).
-> gfx_prompt(window, message, info, dflt, buttons)
  ccall("w_gfx_prompt", window, message, info, dflt, buttons)

# A modal choice from `items` (a comma list, "-" a separator) in a pop-up:
# [button index, item index] ([-1, -1] on a hidden window, unscripted).
-> gfx_choose(window, message, info, items, buttons)
  ccall("w_gfx_choose", window, message, info, items, buttons)

# The next prompt or choice returns [button, text] / [button, item] without
# showing (specs, scripted runs).
-> gfx_prompt_answer(window, button, text, item)
  ccall("w_gfx_prompt_answer", window, button, text, item)

# Build a real input event and hand it to the view's handlers, as if the
# user did it: GFX_EV_MOUSE_* (a = button, b = clicks), GFX_EV_KEY_DOWN/UP
# (a = keyCode, text = its characters; Command shortcuts reach the menu bar),
# GFX_EV_SCROLL (a, b = dx, dy points), GFX_EV_MAGNIFY (a), GFX_EV_MENU
# (a = item id), GFX_EV_CLOSE (the close button).
-> gfx_post_event(window, kind, x, y, a, b, mods, text)
  ccall("w_gfx_post_event", window, kind, x, y, a, b, mods, text)

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
KEY_RETURN     = 36
KEY_TAB        = 48
KEY_DELETE     = 51
KEY_FWD_DELETE = 117
KEY_HOME       = 115
KEY_END        = 119
KEY_PAGE_UP    = 116
KEY_PAGE_DOWN  = 121
KEY_EQUAL      = 24
KEY_MINUS      = 27
KEY_COMMAND    = 55
KEY_OPTION     = 58
KEY_CONTROL    = 59

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
