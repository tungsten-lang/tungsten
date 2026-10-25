# spec: slow
# Regression coverage for the pure-Tungsten regex engine (core/regex.w).
#
# COMPILED-ONLY + SELF-CONTAINED. The engine derives its private untagged i64[]
# character payloads from String#codes, a runtime primitive that does not run
# under the tree-walk interpreter — so this is neither a parity fixture nor a
# `use assert` test (assert.w is interpreter-only). Run it compiled:
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

# ── structured numbered/named captures + codepoint offsets ──────────────
named = Regex.new("(?<major>\\d+)-(?<minor>\\d+)")
md = named.match_data("v 12-345!")
ok = check("match-data-whole", md[0], "12-345") && ok
ok = check("match-data-numbered", md[2], "345") && ok
ok = check("match-data-name-string", md["major"], "12") && ok
ok = check("match-data-name-symbol", md[:minor], "345") && ok
ok = check("match-data-captures", md.captures(), ["12", "345"]) && ok
ok = check("match-data-offset", md.offset("minor"), [5, 8]) && ok
ok = check("match-data-bounds", [md.begin_offset(), md.end_offset()], [2, 8]) && ok
ok = check("match-data-unknown", md["missing"], nil) && ok

optional_md = Regex.new("(a)?(b)").match_data("b")
ok = check("match-data-unmatched-group", optional_md[1], nil) && ok
ok = check("match-data-unmatched-offset", optional_md.offset(1), nil) && ok
empty_md = Regex.new("(a*)").match_data("b")
ok = check("match-data-empty-offset", empty_md.offset(1), [0, 0]) && ok
unicode_md = Regex.new("(?<word>\\w+)").match_data("é猫!")
ok = check("match-data-codepoint-offset", unicode_md.offset(:word), [0, 2]) && ok

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

# ── ascii_only? predicate ───────────────────────────────────────────────
ok = check("ascii-only-plain", /hello_[0-9]+/.ascii_only?(), true) && ok
ok = check("ascii-only-escapes", /\a\e\f\v\x41\cA/.ascii_only?(), true) && ok
ok = check("ascii-only-prop-ascii", /\p{ASCII}+/.ascii_only?(), true) && ok
ok = check("ascii-only-prop-basic-latin", /\p{In_Basic_Latin}+/.ascii_only?(), true) && ok
ok = check("ascii-only-false-lit", /héllo/.ascii_only?(), false) && ok
ok = check("ascii-only-false-u", /\u03B1/.ascii_only?(), false) && ok
ok = check("ascii-only-false-prop", /\p{Lu}+/.ascii_only?(), false) && ok
ok = check("ascii-only-false-R", /\R/.ascii_only?(), false) && ok

# ── character escapes (\a \e \f \v \0 \xNN \uNNNN \u{...} \cX \h \H \R \X)
s_aefv = 7.chr() + 27.chr() + 12.chr() + 11.chr()
ok = check("esc-bel-esc-ff-vt", Regex.new("\\a\\e\\f\\v").match(s_aefv), [s_aefv]) && ok
s_oct = "a\0b" + 7.chr() + "c"
md_oct = Regex.new("a\\0b\\07c").match_data(s_oct)
ok = check("esc-octal-nul", md_oct.offset(0), [0, 5]) && ok
ok = check("esc-hex-xNN", m("\\x41\\x62\\x{3b1}", "Abα"), ["Abα"]) && ok
ok = check("esc-uNNNN", m("\\u03b1\\u03b2", "αβ"), ["αβ"]) && ok
ok = check("esc-u-braced-multi", m("\\u{61 62 63}", "xabcy"), ["abc"]) && ok
s_ctrl = 1.chr() + 1.chr() + 127.chr() + 2.chr()
ok = check("esc-ctrl", Regex.new("\\cA\\ca\\c?\\C-b").match(s_ctrl), [s_ctrl]) && ok
ok = check("esc-hex-class-h", m("\\h+", "zzdeadBEEF09zz"), ["deadBEEF09"]) && ok
ok = check("esc-hex-class-H", m("\\H+", "dead!@#BEEF"), ["!@#"]) && ok
ok = check("esc-R-crlf", m("a\\Rb", "a\r\nb"), ["a\r\nb"]) && ok
ok = check("esc-R-lf", m("a\\Rb", "a\nb"), ["a\nb"]) && ok
ok = check("esc-X-combining", m("\\X", "e\u0301x"), ["e\u0301"]) && ok

# ── Unicode properties \p{...} and \P{...} (Categories, Scripts, Blocks) ──
ok = check("prop-Lu", m("\\p{Lu}+", "abcDEFghi"), ["DEF"]) && ok
ok = check("prop-Ll", m("\\p{Ll}+", "ABCdefGHI"), ["def"]) && ok
ok = check("prop-Nd", m("\\p{Nd}+", "abc123def"), ["123"]) && ok
ok = check("prop-Sc", m("\\p{Sc}+", "price €£$10"), ["€£$"]) && ok
ok = check("prop-Sm", m("\\p{Sm}+", "a + b = c"), ["+"]) && ok
ok = check("prop-P", m("\\p{P}+", "hello, world!"), [","]) && ok
ok = check("prop-Emoji", m("\\p{Emoji}+", "hi 😀🚀!"), ["😀🚀"]) && ok
ok = check("prop-neg-P", m("\\P{Nd}+", "123abc456"), ["abc"]) && ok
ok = check("prop-caret-neg", m("\\p{^Nd}+", "123abc456"), ["abc"]) && ok
ok = check("prop-Script-Greek", m("\\p{Greek}+", "abcαβγΩdef"), ["αβγΩ"]) && ok
ok = check("prop-Script-Han", m("\\p{Han}+", "abc漢字def"), ["漢字"]) && ok
ok = check("prop-Script-Hiragana", m("\\p{Hiragana}+", "abcひらがなdef"), ["ひらがな"]) && ok
ok = check("prop-Script-Cyrillic", m("\\p{Cyrillic}+", "abcПриветdef"), ["Привет"]) && ok
ok = check("prop-Block-Currency", m("\\p{In_Currency_Symbols}+", "x€y"), ["€"]) && ok
ok = check("prop-Block-Math", m("\\p{In_Mathematical_Operators}+", "x∀∃∈y"), ["∀∃∈"]) && ok
ok = check("prop-in-char-class", m("\[\\p{Greek}\\d]+", "aα1β2b"), ["α1β2"]) && ok

# ── Anchors \A \z \Z \G and Keep \K ─────────────────────────────────────
ok = check("anchor-A-z", Regex.new("\\Aabc\\z", "m").match("abc"), ["abc"]) && ok
ok = check("anchor-A-z-multiline-fail", Regex.new("\\Aabc\\z", "m").match("x\nabc\ny"), nil) && ok
ok = check("anchor-Z-trailing-nl", m("\\Aabc\\Z", "abc\n"), ["abc"]) && ok
ok = check("anchor-Z-two-nl-fail", m("\\Aabc\\Z", "abc\n\n"), nil) && ok
ok = check("anchor-G-scan", "1122 33".scan(/\G\d\d/), ["11", "22"]) && ok
md_keep = Regex.new("foo\\Kbar").match_data("foobar!")
ok = check("keep-K-match", md_keep[0], "bar") && ok
ok = check("keep-K-offset-pre-post", [md_keep.offset(0), md_keep.pre_match(), md_keep.post_match()], [[3, 6], "foo", "!"]) && ok

# ── Backreferences \1..\9, \k<name>, and Subexpression Calls \g<name> ───
ok = check("backref-numbered", m("(\\w+)-\\1", "ha-ha"), ["ha-ha", "ha"]) && ok
ok = check("backref-numbered-nomatch", m("(\\w+)-\\1", "ha-ho"), nil) && ok
ok = check("backref-icase", Regex.new("(\[a-z]+)-\\1", "i").match("Ha-hA"), ["Ha-hA", "Ha"]) && ok
ok = check("backref-named", m("(?<tag>\\w+)<\\k<tag>>", "div<div>"), ["div<div>", "div"]) && ok
ok = check("subcall-named", m("(?<d>\\d+)-\\g<d>", "12-345"), ["12-345", "345"]) && ok
ok = check("subcall-recursive-group", m("\\A(?<p>\\(\\g<p>*\\))\\z", "((())())"), ["((())())", "((())())"]) && ok
ok = check("subcall-recursive-unbalanced", m("\\A(?<p>\\(\\g<p>*\\))\\z", "((())"), nil) && ok
ok = check("subcall-g0-recursive", m("a\\g<0>?b", "aaabbb"), ["aaabbb"]) && ok

# ── Free-spacing mode /x ────────────────────────────────────────────────
rx_x = Regex.new("(?<year> \\d{4} ) - # year part\n  (?<month> \\d{2} ) # month part", "x")
ok = check("extended-x-multiline", rx_x.match("2026-10"), ["2026-10", "2026", "10"]) && ok
ok = check("extended-x-literal", (/hello \s+ world # comment/x).match("hello   world"), ["hello   world"]) && ok
ok = check("extended-x-escaped-space-hash", (/a\ b\#c # comment/x).match("a b#c"), ["a b#c"]) && ok
ok = check("extended-x-char-class-space", (/[a b#]+/x).match("a b#"), ["a b#"]) && ok

# ── Lookaround Assertions (?=...) (?!...) (?<=...) (?<!...) ─────────────
ok = check("lookahead-pos", m("\\w+(?=:)", "foo:bar"), ["foo"]) && ok
ok = check("lookahead-pos-capture", m("(?=(\\w+))\\w", "hello"), ["h", "hello"]) && ok
ok = check("lookahead-neg-backtrack", m("\\d+(?!px)", "10px 20em"), ["1"]) && ok
ok = check("lookahead-neg-possessive", m("\\d++(?!px)", "10px 20em"), ["20"]) && ok
ok = check("lookahead-neg-word", m("\\bfoo(?!bar)\\w*", "foobar foobaz"), ["foobaz"]) && ok
ok = check("lookbehind-pos-fixed", m("(?<=\\$)\\d+", "EUR10 $250"), ["250"]) && ok
ok = check("lookbehind-pos-alt-len", m("(?<=foo|foobar)\\d+", "foobar42"), ["42"]) && ok
ok = check("lookbehind-pos-varlen", m("(?<=\\w+:)\\d+", "id:987"), ["987"]) && ok
ok = check("lookbehind-pos-capture", m("(?<=(\\w+):)\\d+", "key:42"), ["42", "key"]) && ok
ok = check("lookbehind-neg-fixed", m("(?<!\\$)\\b\\d+", "$10 25"), ["25"]) && ok
ok = check("lookbehind-neg-start", m("(?<!a)b", "b"), ["b"]) && ok
ok = check("lookbehind-neg-fail", m("(?<!a)b", "ab"), nil) && ok
ok = check("lookaround-combined", m("(?<=<)\\w+(?=>)", "x <tag> y"), ["tag"]) && ok

# ── Atomic Grouping (?>...) and Possessive Quantifiers *+ ++ ?+ {m,n}+ ──
ok = check("atomic-group-no-backtrack", m("(?>a+)a", "aaa"), nil) && ok
ok = check("atomic-group-match", m("(?>a+)b", "aaab"), ["aaab"]) && ok
ok = check("atomic-alt-first-wins", m("(?>a|ab)c", "abc"), nil) && ok
ok = check("atomic-alt-longer-first", m("(?>ab|a)c", "abc"), ["abc"]) && ok
ok = check("possessive-plus-fail", m("a++a", "aaa"), nil) && ok
ok = check("possessive-plus-match", m("a++b", "aaab"), ["aaab"]) && ok
ok = check("possessive-star-fail", m("\\d*+1", "1231"), nil) && ok
ok = check("possessive-group-plus", m("(ab)++ab", "ababab"), nil) && ok
ok = check("possessive-qmark-fail", m("a?+a", "a"), nil) && ok
ok = check("possessive-brace-fail", m("a{1,3}+a", "aaa"), nil) && ok

# ── Inline Comments (?#...) and Scoped/Inline Flags (?imx-imx:...) ──────
ok = check("inline-comment", m("foo(?# ignore this )bar", "foobar"), ["foobar"]) && ok
ok = check("inline-flag-i", m("(?i)hello", "HeLLo"), ["HeLLo"]) && ok
ok = check("scoped-flag-i", m("(?i:foo)bar", "FOObar"), ["FOObar"]) && ok
ok = check("scoped-flag-i-outer-cs", m("(?i:foo)bar", "FOOBAR"), nil) && ok
ok = check("scoped-flag-neg-i", Regex.new("foo(?-i:bar)", "i").match("FOObar"), ["FOObar"]) && ok
ok = check("scoped-flag-neg-i-fail", Regex.new("foo(?-i:bar)", "i").match("FOOBAR"), nil) && ok

# ── String#scan Fast Path (scan_all) and Regex#sub / #gsub / #split ─────
ok = check("scan-1-group", "a1 b22 c333".scan(/([a-z])\d+/), [["a"], ["b"], ["c"]]) && ok
ok = check("scan-2-groups", "a1 b22".scan(/([a-z])(\d+)/), [["a", "1"], ["b", "22"]]) && ok
ok = check("regex-sub", (/\d+/).sub("a1b22c333", "#"), "a#b22c333") && ok
ok = check("regex-gsub", (/\d+/).gsub("a1b22c333", "#"), "a#b#c#") && ok
ok = check("regex-split", (/\s*,\s*/).split("a, b , c,  d"), ["a", "b", "c", "d"]) && ok

if ok
  << "regex_features: all 153 checks passed"
else
  << "regex_features: FAILURES (see above)"
  exit 1
