# Windows: core/graphics

`core/graphics.w` opens a Cocoa window backed by a `CAMetalLayer` and presents
pixel buffers to it (`runtime/graphics.m`). It is macOS-only and compiled-only;
other targets link weak stubs that raise on the first call. Load it with
`use core/graphics`. Every call must run on the process main thread.

There are two input models, and every window supports both.

## Game style

```tungsten
use core/graphics
dev = metal_device()
win = gfx_window(dev, "Viewer", 1280, 720)      # 1280 x 720 pixels, RGBA8, shown at once
buf = metal_buffer(dev, 1280 * 720 * 4)
while !gfx_should_close(win)
  gfx_poll(win)
  fwd = gfx_key_down(win, KEY_W)                 # held state, by hardware keyCode
  look = gfx_mouse_dx(win)                       # relative motion since the last read
  # … a @gpu kernel writes buf …
  gfx_present(win, buf, 1280, 720)
```

`gfx_key_down` also reports the modifier keys (`KEY_SHIFT`, `KEY_COMMAND`,
`KEY_OPTION`, `KEY_CONTROL`) while they are held.

## Editor style

An editor needs absolute positions, buttons, scrolling, typed text, resizing,
Retina pixels, a menu bar and file panels. Open the window with flags, which
add up (`|` is the unit pipe in Tungsten):

| Flag | Effect |
| --- | --- |
| `GFX_HIDPI` | the drawable is the content's points times the backing scale, and follows resizes |
| `GFX_HIDDEN` | never shown or activated: specs, headless and scripted runs |
| `GFX_BGRA` | a BGRA8 layer, so CoreGraphics or cairo pixels present without a swizzle |
| `GFX_KEEP_OPEN` | the close button and Quit post `GFX_EV_CLOSE`; the program calls `gfx_close` |

```tungsten
win = gfx_window_open(dev, "Arranger", 1440, 900, GFX_HIDPI + GFX_BGRA + GFX_KEEP_OPEN)
gfx_menu_add(win, "File", "Open…", "o", 0, 1)
gfx_menu_add(win, "File", "Save", "s", 0, 2)
running = true
while running
  gfx_wait(win, ~0.5)                            # sleeps until input arrives
  e = gfx_next_event(win)
  while e != nil
    if e[:kind] == GFX_EV_MOUSE_DOWN
      select_at(e[:x] * gfx_scale(win), e[:y] * gfx_scale(win))
    elsif e[:kind] == GFX_EV_MENU && e[:id] == 1
      path = gfx_open_panel(win, "Open a piece", "arr,txt", "")
    elsif e[:kind] == GFX_EV_CLOSE
      running = false
    e = gfx_next_event(win)
  # draw only if something changed, at gfx_pixel_width x gfx_pixel_height
gfx_close(win)
```

An event is a hash with `:kind` and the fields that kind uses. Positions are
points from the content's top-left; multiply by `gfx_scale(win)` for pixels.

| Kind | Fields |
| --- | --- |
| `GFX_EV_KEY_DOWN`, `GFX_EV_KEY_UP` | `:key` (keyCode), `:mods`, `:repeat`, `:text` (the key's characters) |
| `GFX_EV_TEXT` | `:text`, typed and printable (not a Command or Control shortcut) |
| `GFX_EV_MOUSE_DOWN`, `GFX_EV_MOUSE_UP` | `:x`, `:y`, `:button` (0 left, 1 right, 2+ other), `:clicks`, `:mods` |
| `GFX_EV_MOUSE_MOVE`, `GFX_EV_MOUSE_DRAG` | `:x`, `:y`, `:dx`, `:dy` (`:button` for drags) |
| `GFX_EV_SCROLL` | `:dx`, `:dy` in points (natural direction), `:precise` (trackpad), `:phase` |
| `GFX_EV_MAGNIFY` | `:dx`, the pinch's magnification step, and `:phase` |
| `GFX_EV_RESIZE` | `:w`, `:h` in content points, `:scale` |
| `GFX_EV_CLOSE` | `:id` 1 when it came from Quit |
| `GFX_EV_MENU` | `:id` of the chosen item |
| `GFX_EV_FOCUS` | `:id` 1 when the window gained focus, 0 when it lost it |
| `GFX_EV_MODS` | `:mods` after a modifier key changed |
| `GFX_EV_OPEN` | `:path`, a file to open: a double-click in Finder, a drop on the Dock icon, `open -a`, at launch or while running |

Modifier bits: `GFX_MOD_SHIFT`, `GFX_MOD_CTRL`, `GFX_MOD_ALT`, `GFX_MOD_CMD`,
`GFX_MOD_CAPS`, `GFX_MOD_FN` (AppKit sets Fn on the arrows and the other
function keys; `mods % 16` leaves Caps Lock and Fn out). Scroll phases: 0 none, 1 began, 2 changed,
3 ended, 4 momentum. Consecutive moves, drags and scrolls coalesce into one
event, and a full queue (1,024 events) drops its oldest.

| Call | Does |
| --- | --- |
| `gfx_wait(win, seconds)` | pumps the OS queue, sleeping up to `seconds` for input; returns the queued count |
| `gfx_next_event(win)`, `gfx_events(win)` | the oldest event (nil when none), or all of them |
| `gfx_pixel_width/height(win)`, `gfx_point_width/height(win)`, `gfx_scale(win)` | the drawable, the content, the scale between them |
| `gfx_set_title`, `gfx_set_size(win, w, h)`, `gfx_set_cursor(win, GFX_CURSOR_*)`, `gfx_close` | the window |
| `gfx_menu_add(win, menu, title, key, mods, id)`, `gfx_menu_separator`, `gfx_menu_set(win, id, enabled, checked)` | the menu bar: the program's menus between the standard application menu and Window/Help; `menu` may be a path (`"File/Open Recent"`) for a submenu |
| `gfx_menu_clear(win, menu)`, `gfx_menu_items(win, menu)` | empty a menu or submenu to refill it; the titles of its items (`""` the bar's menus) |
| `gfx_prompt(win, message, info, default, buttons)`, `gfx_choose(win, message, info, items, buttons)`, `gfx_prompt_answer(win, button, text, item)` | modal: a line of text → `[button, text]`; a pop-up choice → `[button, item]`; the scripted answer for hidden windows |
| `gfx_open_panel(win, title, types, dir)`, `gfx_save_panel(win, title, name, types, dir)` | modal panels: a path, or nil when cancelled |
| `gfx_panel_answer(win, path)` | the next panel returns `path` without showing (specs, scripts) |
| `gfx_alert(win, message, info, "Save,Don't Save,Cancel")`, `gfx_alert_answer(win, i)` | a modal alert: the chosen button's index (-1 on a hidden window); a scripted answer |
| `gfx_post_event(win, kind, x, y, a, b, mods, text)` | synthesized input through the view's handlers (specs, scripts) |
| `gfx_present(win, buf, w, h)`, `gfx_present_wait(…)` | blit a buffer to the next drawable (clipped to it) |

The first item a program adds also makes the standard macOS menus around
its own, wired to AppKit's roles: the application menu, named by the
bundle's `CFBundleName` (else the process): About (the standard About panel
with `CFBundleShortVersionString` and the build, `CFBundleVersion`),
Settings… (⌘, — a `GFX_EV_MENU` with id `GFX_MENU_SETTINGS`), Services,
Hide (⌘H), Hide Others (⌥⌘H), Show All and Quit (⌘Q, `terminate:`: a
`GFX_KEEP_OPEN` program gets it as `GFX_EV_CLOSE` with `:id` 1 to confirm
— from the Dock and at log out too); Window: Minimize (⌘M), Zoom, Bring All
to Front; Help: <App> Help (`GFX_MENU_HELP`). The bar is made once and
replaces whatever main menu AppKit already holds: on macOS 27
`finishLaunching` gives a regular (visible) app without a nib a placeholder,
an application item with an empty menu (until 2026-11-04 the runtime took that
for its own bar, so a launched app had no Quit and no Window or Help menus;
hidden-window runs are accessory apps and never get the placeholder, so the
spec below cannot see it: check a launched app's menu bar for real).

**Opening documents.** The runtime's application delegate takes
`application:openURLs:` (installed before `finishLaunching`, so the files an
app is launched with reach it too, instead of `NSDocumentController`, which
has no document class and says the app cannot open the format) and queues a
`GFX_EV_OPEN` per file on the first window opened that is still open; paths
that arrive at launch, before any window, are queued when the first window
opens. The program opens the file as File ▸ Open would (asking to save its
edits first). For Finder to route a type to the app, its Bitfile `app` line
names it: `documents: "arr"` makes the bundle's `CFBundleDocumentTypes`
(role Editor, `LSHandlerRank` Owner, `LSItemContentTypes`) and an exported
type `<id>.<ext>` (`UTExportedTypeDeclarations`, conforming to `public.data`
and `public.content`, with the extension). `gfx_post_event(win, GFX_EV_OPEN, 0, 0,
0, 0, 0, path)` sends a path through the same delegate method (scripts,
specs).

A menu key is one character or a name: `up`, `down`, `left`, `right`,
`return`, `tab`, `space`, `delete`, `escape`, `home`, `end`, `pageup`,
`pagedown`, `f1`–`f12`. Mods 0 means Command, -1 the plain key.

`spec/core/graphics_events_spec.w` (the Metal lane) drives a hidden window
through all of this.
