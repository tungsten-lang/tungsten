# Backslash escape coverage in string literals — function-local, module-level
# constant, interpolation-adjacent, and torture combinations.
#
# Context (2026-07-22): a report claimed literals containing `\\` were
# miscompiled into corrupted string objects (the chessbot repo carries a
# `92.chr` workaround for its Postgres COPY `\x`/`\N` byteas). The claim did
# NOT reproduce at f8b236ce in any of these shapes, dev or --release; this
# spec pins them all so any hidden trigger or future regression surfaces
# here instead of in downstream projects.
#
# Run: `bin/tungsten -o /tmp/seb spec/compiler/string_escape_backslash_spec.w && /tmp/seb`

BS_CONST = "\\"
PREFIX_CONST = "\\x"
NULL_CONST = "\\N"

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

-> emit_row(hex)
  BS_CONST + BS_CONST + "x" + hex + "\t" + NULL_CONST

check("bs.single", "a\\b".size(), 3)
check("bs.double", "\\\\".size(), 2)
check("bs.literal_n", "\\n".size(), 2)
check("bs.literal_t", "a\\tb".size(), 4)
check("bs.hexish", "\\x41".size(), 4)
check("bs.null_marker", "\\N".size(), 2)
check("bs.trailing", "end\\".size(), 4)
check("bs.const.size", BS_CONST.size(), 1)
check("bs.const.prefix", PREFIX_CONST.size(), 2)
check("bs.chr_equiv", BS_CONST, 92.chr())

h = "ff"
check("bs.then_interp", "\\x[h]".size(), 4)
check("bs.escaped_bracket_vs_interp", "\\[h]".size(), 3)

row = "\\x[h]\t7\t\\N\n"
check("bs.copy_row", row.size(), 10)
check("bs.emit_row", emit_row("ff"), "\\" + "\\xff\t" + "\\N")

many = ""
i = 0
while i < 64
  many = many + "\\"
  i += 1
check("bs.sixty_four", many.size(), 64)
