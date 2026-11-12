# spec: metal -- native AppKit menu/title conversion
use core/graphics
use core/metal

-> check(name, value)
  if !value
    << "FAIL " + name
    exit 1
  << "PASS " + name

win = gfx_window_open(metal_device(), "Rope menu check", 320, 240, GFX_HIDDEN)
part = "O Holy Night — Érard piano.arr"
dir = Env.get("ARRANGER_MENU_TEST_DIR", "/Users/example/Music/Christmas arrangements/")
label = part + "  —  " + dir + "14-o-holy-night"
gfx_menu_add(win, "File/Open Recent", label, "", 0, 1201)
titles = gfx_menu_items(win, "File/Open Recent")
check("recent filename/directory label survives concatenation", titles.size == 1 && titles[0] == label)
path = "Instruments/" + "Historical keyboard instruments"
gfx_menu_add(win, path, "Choose " + part + " from " + dir, "", 0, 1202)
check("concatenated submenu path and title", gfx_menu_items(win, path)[0] == "Choose " + part + " from " + dir)
gfx_menu_clear(win, path)
check("concatenated menu path clears the intended submenu", gfx_menu_items(win, path).size == 0)
gfx_close(win)
