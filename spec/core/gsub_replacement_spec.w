# String#gsub replacement semantics: with a STRING pattern the replacement
# is LITERAL on every engine. Ruby's native gsub interprets \', \1, \&, ...
# replacement tokens, which leaked through the tree-walker's method
# fallthrough and corrupted shell-quoting helpers (bin/tungsten's polyglot
# trampoline quotes with "'" + s.gsub("'", "'\\''") + "'").
#
# Run: `bin/tungsten -o /tmp/gsubspec spec/core/gsub_replacement_spec.w && /tmp/gsubspec`
# Also engine-parity relevant: run via `bin/tungsten run` and `--ruby` too.

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

bs = 92.chr

check("gsub.plain", "abab".gsub("a", "X"), "XbXb")
check("gsub.backslash.one", "ab".gsub("a", bs + "1x"), bs + "1xb")
check("gsub.postmatch.token", "it's".gsub("'", "'" + bs + "''"), "it'" + bs + "''s")
check("gsub.amp.token", "ab".gsub("a", bs + "&"), bs + "&b")
check("gsub.shell.quote", "'" + "don't".gsub("'", "'" + bs + "''") + "'", "'don'" + bs + "''t'")

<< "gsub replacement: all green"
