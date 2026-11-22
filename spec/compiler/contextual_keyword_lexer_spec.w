# spec: compiled -- the tree-walker cannot run the packed LexChar Lexer
# `go`, `fn` and `on` are contextual keywords (contextual_keyword_at? in
# languages/tungsten/lexers/regex_helpers.w). Both lexers, the packed
# production Lexer and the reference RegexLexer, give the word KEYWORD only
# where its grammar applies and ID everywhere else.
# contextual_keyword_spec.w checks the keyword forms at run time, and
# spec/parity/{go_identifier,contextual_keywords}_spec.w the identifier
# uses on every engine.

use ../../compiler/lib/lexer
use ../../languages/tungsten/lexers/regex

-> expect(name, cond)
  if cond
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

# The type each lexer gives the first `word` token in `src` (nil: none).
-> production_word_type(src, word)
  lx = Lexer.new(src, "keyword_probe.w")
  lx.tokenize()
  vals = lx.values()
  packed = lx.packed_tokens()
  i = 0
  while i < vals.size()
    if vals[i] == word
      return ((packed[i] >> 38) & 0xFF) == 26 ? :KEYWORD : :ID
    i += 1
  nil

-> regex_word_type(src, word)
  found = nil
  RegexLexer.new(src, "keyword_probe.w").tokenize().each -> (t)
    if found == nil && t[:value] == word
      found = t[:type]
  found

-> check(word, src, want)
  label = word + " " + (want == nil ? "absent" : want.to_s()) + ": " + src.gsub("\n", "\\n")
  expect("lexer " + label, production_word_type(src, word) == want)
  expect("regex " + label, regex_word_type(src, word) == want)

["go -> 1", "go ->\n  1", "x = go -> 1", "go\t-> 1", "f(go -> 1)"].each -> (src)
  check("go", src, :KEYWORD)
["go = 1", "go += 1", "-> go(x)", "-> f(go)", "x.go", "x.go -> 1", "x&.go", "{go: 1}", "go(1)", "go + 1", "\[go]", "go\n-> f"].each -> (src)
  check("go", src, :ID)
check("go", "gopher -> 1", nil)

["fn twice(x)\n  x", "fn  f\n  1", "@gpu fn k(a)\n  a", "fn\tf"].each -> (src)
  check("fn", src, :KEYWORD)
["fn = 1", "fn.call(1)", "-> fn(x)", "-> f(fn)", "x.fn", "x.fn y", "{fn: 1}", "fn(1)", "fn + 1", "fn"].each -> (src)
  check("fn", src, :ID)

["on macos\n  1", "on macos && arm64\n  1", "on (linux || macos) && !windows with metal with simd\n  1", "on !windows\n  1", "on macos # guard\n\n  # body\n  1", "x = 1\non macos\n  1", "if a\n  on macos\n    1"].each -> (src)
  check("on", src, :KEYWORD)
["on = 1", "on\n  1", "-> pause(on)", "x.on", "x.on y\n  1", "{on: 1}", "on(1)", "on + 1", "on macos", "on macos\n1", "on macos\n  .foo", "x = on y\n  1", "f(on)", "on x, y\n  1", "on x = 1\n  1"].each -> (src)
  check("on", src, :ID)
