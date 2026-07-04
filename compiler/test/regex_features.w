# Regression coverage for the pure-Tungsten regex engine (core/regex.w).
#
# COMPILED-ONLY + SELF-CONTAINED. The engine matches on String#codes (Char
# WValues + raw bit ops), a runtime primitive that does not run under the
# tree-walk interpreter — so this is neither a parity fixture nor a `use
# assert` test (assert.w is interpreter-only). Run it compiled:
#
#   bin/tungsten -o /tmp/rxf compiler/test/regex_features.w && /tmp/rxf
#
# Prints a FAIL line per mismatch and exits non-zero; silent-but-summary on
# success. NB: `[` opens string interpolation in .w source, so a literal `[`
# in a pattern is written `\[` (the engine receives a plain `[`).

-> m(pat, subj)
  Regex.new(pat).match(subj)

# Compares a match result against the expected array (or nil); on mismatch
# prints a FAIL line and returns false, else true. Accumulate with `&& ok`
# so one run reports every failure and the process still exits 1.
#
# Compares canonical string forms, not the arrays directly: compiled Array
# `==` is identity-based (two distinct ["cat"] objects are not `==`), so a
# structural check needs to_s. nil is handled explicitly so a nil result is
# never confused with an empty/structural form.
-> check(label, got, want)
  gs = "nil"
  if got != nil
    gs = got.to_s()
  ws = "nil"
  if want != nil
    ws = want.to_s()
  if gs == ws
    return true
  << "FAIL " + label + ": got " + gs + " want " + ws
  false

ok = true

# ── literals, dot, escapes ──────────────────────────────────────────────
ok = check("literal", m("cat", "the cat sat"), ["cat"]) && ok
ok = check("dot-any", m("a.b", "axb"), ["axb"]) && ok
ok = check("escaped-dot", m("a\\.b", "a.b"), ["a.b"]) && ok
ok = check("escaped-dot-nomatch", m("a\\.b", "axb"), nil) && ok

# ── greedy quantifiers ──────────────────────────────────────────────────
ok = check("star", m("a*", "aaab"), ["aaa"]) && ok
ok = check("plus", m("a+", "baaa"), ["aaa"]) && ok
ok = check("optional", m("a?b", "b"), ["b"]) && ok
ok = check("count-n", m("a{2}", "aaaa"), ["aa"]) && ok
ok = check("count-n-plus", m("a{2,}", "aaaa"), ["aaaa"]) && ok
ok = check("count-n-m", m("a{2,3}", "aaaa"), ["aaa"]) && ok

# ── lazy quantifiers ────────────────────────────────────────────────────
ok = check("lazy-plus", m("a+?", "aaa"), ["a"]) && ok
ok = check("lazy-star", m("a*?b", "aaab"), ["aaab"]) && ok

# ── anchors ─────────────────────────────────────────────────────────────
ok = check("caret", m("^abc", "abc"), ["abc"]) && ok
ok = check("caret-nomatch", m("^cat", "the cat"), nil) && ok
ok = check("dollar", m("abc$", "xabc"), ["abc"]) && ok
ok = check("word-boundary", m("\\bcat\\b", "a cat!"), ["cat"]) && ok
ok = check("non-word-boundary", m("\\Bcat", "scat"), ["cat"]) && ok

# ── character classes ───────────────────────────────────────────────────
ok = check("class-set", m("\[abc]+", "xbcay"), ["bca"]) && ok
ok = check("class-neg", m("\[^abc]+", "abcXYZ"), ["XYZ"]) && ok
ok = check("class-range", m("\[a-z]+", "AB cd"), ["cd"]) && ok
ok = check("class-mixed", m("\[a-zA-Z0-9_]+", "  hi_42!"), ["hi_42"]) && ok

# ── shorthand classes (OP_FLAG fast path + negations) ───────────────────
ok = check("digit", m("\\d+", "x99y"), ["99"]) && ok
ok = check("non-digit", m("\\D+", "99ab9"), ["ab"]) && ok
ok = check("word", m("\\w+", "  foo_1 "), ["foo_1"]) && ok
ok = check("non-word", m("\\W+", "ab--cd"), ["--"]) && ok
ok = check("space", m("\\s+", "a   b"), ["   "]) && ok
ok = check("non-space", m("\\S+", "  zz "), ["zz"]) && ok

# ── groups, nesting, non-capturing, alternation ─────────────────────────
ok = check("group-repeat-keeps-last", m("(ab)+", "ababab"), ["ababab", "ab"]) && ok
ok = check("non-capturing", m("(?:ab)+c", "ababc"), ["ababc"]) && ok
ok = check("nested-groups", m("(a(b)c)", "abc"), ["abc", "abc", "b"]) && ok
ok = check("alternation", m("cat|dog|bird", "see a bird"), ["bird"]) && ok
ok = check("group-alternation", m("(foo|bar)baz", "xbarbaz"), ["barbaz", "bar"]) && ok

# ── prefix-scan correctness (long non-matching lead) + captures ─────────
ok = check("prefix-scan", m("(\\d+)-(\\d+)", "the order id is 4521-9837 today"), ["4521-9837", "4521", "9837"]) && ok
ok = check("decimal", m("\\d+\\.\\d+", "v 3.14 x"), ["3.14"]) && ok
ok = check("no-match", m("\\d+", "no digits here"), nil) && ok

# ── unicode (codepoint-ordered ranges + \w on non-ASCII) ────────────────
ok = check("unicode-word", m("\\w+", "héllo"), ["héllo"]) && ok
ok = check("greek-range", m("\[α-ω]+", "αβγ!"), ["αβγ"]) && ok
ok = check("han-word", m("\\w+", "  中文x  "), ["中文x"]) && ok

# ── nullable-body loops: must TERMINATE (no empty-match stack overflow) ──
# Reaching these lines at all proves the progress guard works — an unguarded
# (a*)* over an empty match recurses until the stack faults (SIGBUS).
ok = check("nullable-star-in-star", m("(a*)*b", "aaab"), ["aaab", "aaa"]) && ok
ok = check("nullable-star-no-match", m("(a*)*b", "aaac"), nil) && ok
ok = check("bare-nullable-star", m("(a*)*", "aaa"), ["aaa", "aaa"]) && ok
ok = check("opt-in-star", m("(a?)*", "aaa"), ["aaa", "a"]) && ok
ok = check("empty-alt-in-star", m("(|a)*", "aaa"), ["aaa", "a"]) && ok
ok = check("alt-in-star", m("(ab|a)*", "ababa"), ["ababa", "a"]) && ok
ok = check("nullable-plus", m("(a+)+b", "aaab"), ["aaab", "aaa"]) && ok

# ── edge cases: empty/zero-width, anchored, greedy vs lazy, dot/newline ──
ok = check("empty-pattern", m("", "abc"), [""]) && ok
ok = check("empty-group", m("()", "abc"), ["", ""]) && ok
ok = check("anchored-empty", m("^$", ""), [""]) && ok
ok = check("anchored-empty-nomatch", m("^$", "x"), nil) && ok
ok = check("anchored-star-full", m("^a*$", "aaa"), ["aaa"]) && ok
ok = check("anchored-star-nomatch", m("^a*$", "aab"), nil) && ok
ok = check("empty-alt-branch", m("(x|)y", "y"), ["y", ""]) && ok
ok = check("dot-stops-at-newline", m("a.b", "a\nb"), nil) && ok
ok = check("greedy-dot", m("<.*>", "<a><b>"), ["<a><b>"]) && ok
ok = check("lazy-dot", m("<.*?>", "<a><b>"), ["<a>"]) && ok

if ok
  << "regex_features: all 56 checks passed"
else
  << "regex_features: FAILURES (see above)"
  exit 1
