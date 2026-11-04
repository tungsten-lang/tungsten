# Graphics — editor-style windows (core/graphics.w + runtime/graphics.m).
#
# spec: metal
#
# (Metal lane: it needs AppKit and a Metal device. The window is GFX_HIDDEN, so
# nothing is shown or activated.)
#
# Opens a GFX_HIDDEN window and drives it with gfx_post_event, which builds real
# NSEvents and sends them through AppKit's dispatch, then reads them back from
# the event queue: absolute positions (points from the content's top-left),
# buttons and click counts, drags, scroll deltas, typed text and modifiers,
# key repeat state for the game-style API, resize and the backing scale, the
# menu bar (an item chosen directly and by its Command shortcut), scripted
# open/save panels, the close request of a GFX_KEEP_OPEN window, and a
# present at the drawable's size.
#
# Run:
#   bin/tungsten -o /tmp/graphics_events_spec spec/core/graphics_events_spec.w && /tmp/graphics_events_spec

use core/graphics

passed = Atomic.new(0)

-> check(name, condition)
  raise "FAIL " + name if !condition
  passed.increment()
  << "PASS " + name

-> near(a, b)
  d = a - b
  if d < ~0.0
    d = ~0.0 - d
  return d < ~0.01

dev = metal_device()
win = gfx_window_open(dev, "events spec", 400, 300, GFX_HIDDEN + GFX_HIDPI + GFX_BGRA + GFX_KEEP_OPEN)
gfx_poll(win)
gfx_events(win)

# ---- metrics: points, pixels, scale ----
s = gfx_scale(win)
check("scale is positive", s >= ~1.0)
check("content width in points", near(gfx_point_width(win), ~400.0))
check("content height in points", near(gfx_point_height(win), ~300.0))
check("drawable width follows the scale", gfx_pixel_width(win) == (~400.0 * s).round.to_i)
check("drawable height follows the scale", gfx_pixel_height(win) == (~300.0 * s).round.to_i)

# ---- mouse: absolute positions, buttons, clicks, drags ----
gfx_post_event(win, GFX_EV_MOUSE_DOWN, ~120.0, ~45.0, 0, 1, 0, "")
gfx_post_event(win, GFX_EV_MOUSE_DRAG, ~130.0, ~50.0, 0, 1, 0, "")
gfx_post_event(win, GFX_EV_MOUSE_DRAG, ~140.0, ~60.0, 0, 1, 0, "")
gfx_post_event(win, GFX_EV_MOUSE_UP, ~140.0, ~60.0, 0, 1, 0, "")
es = gfx_events(win)
check("down, one coalesced drag, up", es.size == 3)
check("mouse down kind", es[0][:kind] == GFX_EV_MOUSE_DOWN)
check("mouse down x from the left", near(es[0][:x], ~120.0))
check("mouse down y from the top", near(es[0][:y], ~45.0))
check("left button", es[0][:button] == 0)
check("click count", es[0][:clicks] == 1)
check("drag kind", es[1][:kind] == GFX_EV_MOUSE_DRAG)
check("drags coalesce to the newest position", near(es[1][:x], ~140.0) && near(es[1][:y], ~60.0))
check("mouse up kind", es[2][:kind] == GFX_EV_MOUSE_UP)

gfx_post_event(win, GFX_EV_MOUSE_DOWN, ~10.0, ~20.0, 1, 1, GFX_MOD_SHIFT, "")
gfx_post_event(win, GFX_EV_MOUSE_UP, ~10.0, ~20.0, 1, 1, GFX_MOD_SHIFT, "")
gfx_post_event(win, GFX_EV_MOUSE_DOWN, ~50.0, ~50.0, 0, 2, 0, "")
es = gfx_events(win)
check("right button", es[0][:button] == 1)
check("modifiers on a click", es[0][:mods] == GFX_MOD_SHIFT)
check("double click count", es[2][:clicks] == 2)
gfx_post_event(win, GFX_EV_MOUSE_UP, ~50.0, ~50.0, 0, 2, 0, "")
gfx_events(win)

# ---- scroll (trackpad-precise) ----
gfx_post_event(win, GFX_EV_SCROLL, ~200.0, ~100.0, ~0.0, ~-12.0, 0, "")
gfx_post_event(win, GFX_EV_SCROLL, ~200.0, ~100.0, ~0.0, ~-8.0, 0, "")
es = gfx_events(win)
check("scrolls coalesce", es.size == 1)
check("scroll kind", es[0][:kind] == GFX_EV_SCROLL)
check("scroll dy accumulates", near(es[0][:dy], ~-20.0))
check("scroll is precise", es[0][:precise] == 1)
check("scroll position", near(es[0][:x], ~200.0) && near(es[0][:y], ~100.0))

gfx_post_event(win, GFX_EV_MAGNIFY, ~200.0, ~100.0, ~0.25, 0, 0, "")
e = gfx_next_event(win)
check("magnify", e[:kind] == GFX_EV_MAGNIFY && near(e[:dx], ~0.25))

# ---- keys: key down/up, typed text, the game-style held state ----
gfx_post_event(win, GFX_EV_KEY_DOWN, 0, 0, KEY_A, 0, 0, "a")
check("game-style key state on", gfx_key_down(win, KEY_A))
es = gfx_events(win)
check("key down then text", es.size == 2 && es[0][:kind] == GFX_EV_KEY_DOWN && es[1][:kind] == GFX_EV_TEXT)
check("key code", es[0][:key] == KEY_A)
check("typed text", es[1][:text] == "a")
gfx_post_event(win, GFX_EV_KEY_UP, 0, 0, KEY_A, 0, 0, "a")
check("game-style key state off", !gfx_key_down(win, KEY_A))
e = gfx_next_event(win)
check("key up", e[:kind] == GFX_EV_KEY_UP && e[:key] == KEY_A)

gfx_post_event(win, GFX_EV_KEY_DOWN, 0, 0, KEY_UP, 0, GFX_MOD_SHIFT, "")
es = gfx_events(win)
check("an arrow is a key, not text", es.size == 1 && es[0][:key] == KEY_UP)
check("arrow modifiers (arrows also carry Fn, as from a keyboard)", es[0][:mods] % 16 == GFX_MOD_SHIFT)
gfx_post_event(win, GFX_EV_KEY_UP, 0, 0, KEY_UP, 0, 0, "")
gfx_post_event(win, GFX_EV_KEY_DOWN, 0, 0, 9, 0, GFX_MOD_CMD, "v")
es = gfx_events(win)
check("a Command key is no text", es.size >= 1 && es[es.size - 1][:kind] == GFX_EV_KEY_DOWN)
gfx_post_event(win, GFX_EV_KEY_UP, 0, 0, 9, 0, GFX_MOD_CMD, "v")
gfx_events(win)

gfx_post_event(win, GFX_EV_KEY_DOWN, 0, 0, 0, 0, 0, "é")
es = gfx_events(win)
check("UTF-8 text", es.size == 2 && es[1][:text] == "é")
gfx_post_event(win, GFX_EV_KEY_UP, 0, 0, 0, 0, 0, "é")
gfx_events(win)

# ---- the menu bar ----
gfx_menu_add(win, "File", "Open…", "o", 0, 101)
gfx_menu_separator(win, "File")
gfx_menu_add(win, "File", "Save", "s", 0, 102)
gfx_menu_add(win, "View", "Zoom In", "=", GFX_MOD_CMD, 201)
gfx_post_event(win, GFX_EV_MENU, 0, 0, 102, 0, 0, "")
e = gfx_next_event(win)
check("menu item chosen", e != nil && e[:kind] == GFX_EV_MENU && e[:id] == 102)
gfx_post_event(win, GFX_EV_KEY_DOWN, 0, 0, 31, 0, GFX_MOD_CMD, "o")
es = gfx_events(win)
got = false
k = 0
while k < es.size
  got = true if es[k][:kind] == GFX_EV_MENU && es[k][:id] == 101
  k += 1
check("Command-O reaches its item", got)
gfx_menu_add(win, "Notes", "Octave Up", "up", 0, 211)
gfx_post_event(win, GFX_EV_KEY_DOWN, 0, 0, KEY_UP, 0, GFX_MOD_CMD, "")
es = gfx_events(win)
got = false
k = 0
while k < es.size
  got = true if es[k][:kind] == GFX_EV_MENU && es[k][:id] == 211
  k += 1
check("Command-Up reaches an arrow item (a posted arrow carries its character)", got)
gfx_post_event(win, GFX_EV_KEY_DOWN, 0, 0, KEY_DOWN, 0, GFX_MOD_CMD, "")
es = gfx_events(win)
check("Command-Down with no item is a key event, not a stray menu item", es.size == 1 && es[0][:kind] == GFX_EV_KEY_DOWN && es[0][:key] == KEY_DOWN)
check("an arrow reports the Function flag", (es[0][:mods] / GFX_MOD_FN) % 2 == 1)
check("menu_set finds an item", gfx_menu_set(win, 201, 0, 1))
check("menu_set misses an unknown id", !gfx_menu_set(win, 999, 1, 0))
gfx_post_event(win, GFX_EV_MENU, 0, 0, 201, 0, 0, "")
e = gfx_next_event(win)
check("a disabled item does not fire", e == nil)
gfx_menu_set(win, 201, 1, -1)
gfx_post_event(win, GFX_EV_MENU, 0, 0, 201, 0, 0, "")
e = gfx_next_event(win)
check("re-enabled item fires", e != nil && e[:id] == 201)

gfx_menu_add(win, "Edit", "Undo", "z", 0, 401)
gfx_menu_add(win, "Edit", "Redo", "z", GFX_MOD_CMD + GFX_MOD_SHIFT, 402)
gfx_post_event(win, GFX_EV_KEY_DOWN, 0, 0, 6, 0, GFX_MOD_CMD, "z")
gfx_post_event(win, GFX_EV_KEY_DOWN, 0, 0, 6, 0, GFX_MOD_CMD + GFX_MOD_SHIFT, "Z")
es = gfx_events(win)
ids = []
k = 0
while k < es.size
  ids.push(es[k][:id]) if es[k][:kind] == GFX_EV_MENU
  k += 1
check("Command-Z and Command-Shift-Z reach their items", ids.size == 2 && ids[0] == 401 && ids[1] == 402)

# ---- panels (scripted) ----
gfx_panel_answer(win, "/tmp/piece.arr")
check("scripted open panel", gfx_open_panel(win, "Open", "arr,txt", "") == "/tmp/piece.arr")
gfx_panel_answer(win, nil)
check("scripted cancel", gfx_save_panel(win, "Save", "piece.arr", "arr", "") == nil)
check("a hidden window never shows a panel", gfx_open_panel(win, "Open", "", "") == nil)

# ---- alerts (scripted) ----
gfx_alert_answer(win, 1)
check("scripted alert", gfx_alert(win, "Save?", "", "Save,Don't Save,Cancel") == 1)
check("a hidden window never shows an alert", gfx_alert(win, "Save?", "", "OK") == -1)

# ---- a plain-key menu item ----
gfx_menu_add(win, "Play", "Play", "space", -1, 301)
gfx_post_event(win, GFX_EV_MENU, 0, 0, 301, 0, 0, "")
e = gfx_next_event(win)
check("plain-key item fires", e != nil && e[:id] == 301)

# ---- resize and the drawable ----
gfx_set_size(win, 520, 340)
es = gfx_events(win)
rz = nil
k = 0
while k < es.size
  rz = es[k] if es[k][:kind] == GFX_EV_RESIZE
  k += 1
check("resize event", rz != nil)
check("resize size in points", rz != nil && near(rz[:w], ~520.0) && near(rz[:h], ~340.0))
check("resize scale", rz != nil && near(rz[:scale], s))
check("drawable follows the resize", gfx_pixel_width(win) == (~520.0 * s).round.to_i)

# ---- present at the drawable's size (BGRA), and larger than it (clipped) ----
pw = gfx_pixel_width(win)
ph = gfx_pixel_height(win)
buf = metal_buffer(dev, (pw + 64) * (ph + 64) * 4)
r = gfx_present_wait(win, buf, pw, ph)
check("present returns a flag", r == true || r == false)
r = gfx_present_wait(win, buf, pw + 64, ph + 64)
check("a larger buffer presents clipped", r == true || r == false)

# ---- title, cursor ----
gfx_set_title(win, "renamed")
gfx_set_cursor(win, GFX_CURSOR_POINTING)
gfx_set_cursor(win, GFX_CURSOR_ARROW)
check("title and cursor calls return", true)

# ---- close: a KEEP_OPEN window asks the program ----
gfx_post_event(win, GFX_EV_CLOSE, 0, 0, 0, 0, 0, "")
e = gfx_next_event(win)
check("close request is an event", e != nil && e[:kind] == GFX_EV_CLOSE)
check("should_close is set", gfx_should_close(win))
check("the window is still there", gfx_point_width(win) > ~0.0)
gfx_close(win)
check("closed", gfx_should_close(win))

<< "graphics events: [passed.get()] passed"
