# spec: compiled -- the tree-walker cannot run the packed LexChar Lexer
# `go` is a contextual keyword: both lexers (the packed production Lexer and
# the reference RegexLexer) give it KEYWORD only where it starts a spawn,
# `go -> body` (not after `.`/`&.`), and ID everywhere else.
# go_contextual_keyword_spec.w checks the spawn form at run time, and
# spec/parity/go_identifier_spec.w the identifier uses on every engine.

use ../../compiler/lib/lexer
use ../../languages/tungsten/lexers/regex

-> expect(name, cond)
  if cond
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

# The type each lexer gives the first `go` word in `src`.
-> production_go_type(src)
  lx = Lexer.new(src, "go_probe.w")
  lx.tokenize()
  vals = lx.values()
  packed = lx.packed_tokens()
  i = 0
  while i < vals.size()
    if vals[i] == "go"
      return ((packed[i] >> 38) & 0xFF) == 26 ? :KEYWORD : :ID
    i += 1
  nil

-> regex_go_type(src)
  found = nil
  RegexLexer.new(src, "go_probe.w").tokenize().each -> (t)
    if found == nil && t[:value] == "go"
      found = t[:type]
  found

keyword_srcs = ["go -> 1", "go ->\n  1", "x = go -> 1", "go\t-> 1", "f(go -> 1)"]
ident_srcs = ["go = 1", "go += 1", "-> go(x)", "-> f(go)", "x.go", "x.go -> 1", "x&.go", "{go: 1}", "go(1)", "go + 1", "\[go]", "go\n-> f", "gopher -> 1"]
keyword_srcs.each -> (src)
  label = src.gsub("\n", "\\n")
  expect("lexer keyword: " + label, production_go_type(src) == :KEYWORD)
  expect("regex keyword: " + label, regex_go_type(src) == :KEYWORD)
ident_srcs.each -> (src)
  label = src.gsub("\n", "\\n")
  want = src.starts_with?("gopher") ? nil : :ID
  expect("lexer ident: " + label, production_go_type(src) == want)
  expect("regex ident: " + label, regex_go_type(src) == want)
