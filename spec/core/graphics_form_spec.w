# Native multi-field form values, cancellation and script isolation.
# spec: metal
use core/graphics

-> check(name, ok)
  raise "FAIL " + name if !ok
  << "PASS " + name

dev = metal_device()
win = gfx_window_open(dev, "form spec", 400, 300, GFX_HIDDEN + GFX_KEEP_OPEN)
labels = ["Expression", "Dynamic range"]
defaults = ["1", "1.25"]
r = gfx_form(win, "Expression", "Independent values", labels, defaults, "Apply,Cancel")
check("hidden form cancels and preserves both defaults", r[0] == -1 && r[1] == defaults)
gfx_form_answer(win, 0, ["0.8", "0.9"])
r = gfx_form(win, "Expression", "", labels, defaults, "Apply,Cancel")
check("scripted form returns independent values", r[0] == 0 && r[1] == ["0.8", "0.9"])
check("form leaves caller defaults untouched", defaults == ["1", "1.25"])
r = gfx_form(win, "Expression", "", labels, defaults, "Apply,Cancel")
check("a scripted form answer is consumed once", r[0] == -1 && r[1] == defaults)
gfx_form_answer(win, 1, ["é, Tab\tname", ""])
r = gfx_form(win, "Values", "", labels, defaults, "OK,Cancel")
check("cancel retains Unicode punctuation whitespace and empty values", r[0] == 1 && r[1] == ["é, Tab\tname", ""])
gfx_form_answer(win, 0, ["new", "answer"])
gfx_form_answer(win, 0, ["replacement", "answer"])
r = gfx_form(win, "Values", "", labels, defaults, "OK,Cancel")
check("replacing an answer returns only its replacement", r[1] == ["replacement", "answer"])
gfx_prompt_answer(win, 0, "one field", -1)
gfx_form_answer(win, 0, ["first", "second"])
r = gfx_form(win, "Form", "", labels, defaults, "OK,Cancel")
p = gfx_prompt(win, "Prompt", "", "old", "OK,Cancel")
check("form answers are independent of prompt answers", r[1] == ["first", "second"] && p[1] == "one field")
r = gfx_form(win, "No fields", "", [], [], "OK,Cancel")
check("zero-field hidden form is well-defined", r[0] == -1 && r[1] == [])
gfx_form_answer(win, 0, ["pending", "on close"])
gfx_close(win)
check("close releases a pending answer", true)
