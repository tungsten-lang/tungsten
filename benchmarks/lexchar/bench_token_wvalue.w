# Token WValue benchmark — zero-copy tokenization
#
# Compares two approaches:
# 1. Current: build token value strings char-by-char, emit hash per token
# 2. WValue Token: record offset+length, emit packed WValue per token
#
# Token WValue layout (0xFFFC subtype 00):
#   bits 45-40: flags (6 bits)
#   bits 39-32: type (8 bits)
#   bits 31-20: length (12 bits)
#   bits 19-0:  offset (20 bits)

use ../compiler/lib/lexer

# Token type IDs for packing
T_EOF = 0
T_ID = 1
T_INT = 2
T_WHITESPACE = 3
T_NEWLINE = 4
T_OP = 5
T_STRING = 6
T_OTHER = 7

# Fast tokenizer — emits packed Token WValues (offset+length)
# Only handles common tokens: identifiers, integers, whitespace, operators
-> tokenize_fast(source)
  lc = source.lchs()
  chars = source.chars()
  count = lc.size()
  tokens = []
  pos = 0 ## i64

  while pos < count
    v = lc[pos]
    flags = v & 127

    # Whitespace
    if (flags & 16) != 0
      pos += 1
      while pos < count && (lc[pos] & 16) != 0
        pos += 1
      next

    # Newline
    ch = chars[pos]
    if ch == "\n"
      pos += 1
      next

    # Identifier
    if (flags & 64) != 0
      start = pos
      pos += 1
      while pos < count && (lc[pos] & 32) != 0
        pos += 1
      # Pack as Token WValue: type=ID, offset=start, length=pos-start
      tokens.push((1 << 32) | ((pos - start) << 20) | start)
      next

    # Integer
    if ((v >> 7) & 15) != 15
      start = pos
      pos += 1
      while pos < count && ((lc[pos] >> 7) & 15) != 15
        pos += 1
      tokens.push((2 << 32) | ((pos - start) << 20) | start)
      next

    # Everything else — single char
    tokens.push((7 << 32) | (1 << 20) | pos)
    pos += 1

  tokens

# Benchmark
args = argv()
if args.size() == 0
  << "usage: bench_token_wvalue.w <file.w> [rounds]"
  exit(1)

file = args[0]
rounds = 10
if args.size() > 1
  rounds = args[1].to_i()

source = read_file(file)
char_count = source.size()

<< "Token WValue benchmark"
<< "  file: [file] ([char_count] chars, [rounds] rounds)"

# Warmup
tokenize_fast(source)
Lexer.new(source, file).tokenize()

# Benchmark: WValue tokens (fast tokenizer)
t0 = ccall("__w_clock_ms")
total_fast = 0 ## i64
r = 0 ## i64
while r < rounds
  toks = tokenize_fast(source)
  total_fast += toks.size()
  r += 1
t1 = ccall("__w_clock_ms")
ms_fast = t1 - t0

# Benchmark: hash tokens (current lexer)
t2 = ccall("__w_clock_ms")
total_hash = 0 ## i64
r = 0
while r < rounds
  toks = Lexer.new(source, file).tokenize()
  total_hash += toks.size()
  r += 1
t3 = ccall("__w_clock_ms")
ms_hash = t3 - t2

fast_mchars = char_count * rounds / ms_fast * 1000 / 1000000
hash_mchars = char_count * rounds / ms_hash * 1000 / 1000000

<< ""
<< "  WValue tokens: [ms_fast]ms  [fast_mchars]M chars/sec  ([total_fast / rounds] tokens/lex)"
<< "  Hash tokens:   [ms_hash]ms  [hash_mchars]M chars/sec  ([total_hash / rounds] tokens/lex)"
<< "  Speedup: [ms_hash / ms_fast]x"
<< ""
