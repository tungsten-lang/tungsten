# Interpolation vs the ANSI CSI prefix — language ruling 2026-07-22:
# a [ immediately preceded by ESC (0x1B) never starts interpolation,
# however the ESC got into the string (\e escape, \u001b escape). Brackets
# preceded by anything else keep interpolating, and \[ stays the escaped
# literal form.
#
# Run: `bin/tungsten -o /tmp/sie spec/compiler/string_interp_esc_bracket_spec.w && /tmp/sie`

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

k = 7
r = 240
g = 217
b = 181

check("esc.k_literal", "\e[K".size(), 3)
check("esc.bracket_expr_literal", "\e[k]".size(), 4)
check("esc.unicode_esc_literal", "\u001b[k]".size(), 4)
check("esc.unicode_esc_first_byte", "\u001b[k]".bytes()[0], 27)
check("esc.at_end", "\e[".size(), 2)
check("esc.color_idiom_interpolates", "\e[48;2;[r];[g];[b]m".size(), 19)
check("esc.color_idiom_content", "\e[48;2;[r];[g];[b]m".bytes()[8], 52)

check("interp.plain_start", "[k]", "7")
check("interp.mid", "x[k]", "x7")
check("interp.after_nonesc", "m[k]n", "m7n")
check("interp.escaped_bracket", "\[k]".size(), 3)
check("interp.empty_literal", "[]".size(), 2)
