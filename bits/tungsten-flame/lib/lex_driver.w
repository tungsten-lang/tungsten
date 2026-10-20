# lex_driver.w — Profiling harness for `tungsten flame --lex` and `--parse`.
#
# Pre-loads the target source file(s) outside the timed loop, then repeatedly
# runs the self-hosted Lexer (and Parser when mode == "parse") for the
# requested duration so hardware/timer sampling captures steady-state
# lexing/parsing stacks and exits cleanly before the sampler's time limit
# (allowing `atexit` allocation counters from `--alloc` to flush).

use ../../../compiler/lib/lexer
use ../../../compiler/lib/parser

args = argv()
if args.size() < 3
  << "usage: lex_driver <lex|parse> <duration_ms> <file.w> [more.w ...]"
  exit(1)

mode = args[0]
duration_ms = args[1].to_i()
if duration_ms < 100
  duration_ms = 100

paths = []
sources = []
i = 2
while i < args.size()
  p = args[i]
  s = read_file(p)
  if s == nil
    << "lex_driver: cannot read " + p
    exit(1)
  paths.push(p)
  sources.push(s)
  i = i + 1

t0 = ccall("__w_clock_ms")
deadline = t0 + duration_ms
iters = 0
total_tokens = 0

while iters == 0 || ccall("__w_clock_ms") < deadline
  fi = 0
  while fi < sources.size()
    src = sources[fi]
    path = paths[fi]
    lexer = Lexer.new(src, path)
    tok_count = lexer.tokenize()
    total_tokens = total_tokens + tok_count
    if mode == "parse"
      parser = Parser.new(tok_count, lexer.packed_tokens, src, lexer.values, lexer.line_at, lexer.col_at, lexer.file).set_chars(lexer.chars)
      parser.parse()
    fi = fi + 1
  iters = iters + 1
