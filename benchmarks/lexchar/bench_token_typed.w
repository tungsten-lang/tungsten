# Token benchmark — typed i64[] array, zero boxing
#
# Pre-shifted type constants + raw i64 storage = no tags, no boxing

use ../compiler/lib/lexer

# Pre-shifted token type bases
T_EOF = 0
T_ID  = 1 << 32
T_INT = 2 << 32
T_WS  = 3 << 32
T_NL  = 4 << 32
T_OP  = 5 << 32
T_STR = 6 << 32
T_OTH = 7 << 32

## i64: count
fn tokenize_typed(lc, chars, count)
  tokens = i64[count]
  pos = 0 ## i64
  token_count = 0 ## i64

  while pos < count
    v = lc[pos] ## i64
    flags = (v & 127) ## i64

    # Whitespace — skip
    if (flags & 16) != 0
      pos += 1
      while pos < count && (lc[pos] & 16) != 0
        pos += 1
      next

    # Newline — skip
    if chars[pos] == "\n"
      pos += 1
      next

    # Identifier
    if (flags & 64) != 0
      start = pos ## i64
      pos += 1
      while pos < count && (lc[pos] & 32) != 0
        pos += 1
      tokens[token_count] = T_ID | ((pos - start) << 20) | start
      token_count += 1
      next

    # Integer
    if ((v >> 7) & 15) != 15
      start = pos ## i64
      pos += 1
      while pos < count && ((lc[pos] >> 7) & 15) != 15
        pos += 1
      tokens[token_count] = T_INT | ((pos - start) << 20) | start
      token_count += 1
      next

    # Everything else — single char
    tokens[token_count] = T_OTH | (1 << 20) | pos
    token_count += 1
    pos += 1

  token_count

# Benchmark
args = argv()
if args.length() == 0
  << "usage: bench_token_typed.w <file.w> [rounds]"
  exit(1)

file = args[0]
rounds = 20
if args.length() > 1
  rounds = args[1].to_i()

source = read_file(file)
lc = source.lchs()
chars = source.chars()
char_count = source.length()
lc_count = lc.length()

<< "Token typed i64[] benchmark"
<< "  file: [file] ([char_count] chars, [rounds] rounds)"

# Warmup
tokenize_typed(lc, chars, lc_count)

# Benchmark: typed i64 tokens
t0 = ccall("__w_clock_ms")
total_typed = 0 ## i64
r = 0 ## i64
while r < rounds
  total_typed += tokenize_typed(lc, chars, lc_count)
  r += 1
t1 = ccall("__w_clock_ms")
ms_typed = t1 - t0

# Benchmark: hash tokens (current lexer)
t2 = ccall("__w_clock_ms")
total_hash = 0 ## i64
r = 0
while r < rounds
  toks = Lexer.new(source, file).tokenize()
  total_hash += toks.length()
  r += 1
t3 = ccall("__w_clock_ms")
ms_hash = t3 - t2

typed_mchars = char_count * rounds / ms_typed * 1000 / 1000000
hash_mchars = char_count * rounds / ms_hash * 1000 / 1000000

<< ""
<< "  typed i64[]: [ms_typed]ms  [typed_mchars]M chars/sec  ([total_typed / rounds] tokens/lex)"
<< "  hash tokens: [ms_hash]ms  [hash_mchars]M chars/sec  ([total_hash / rounds] tokens/lex)"
<< "  Speedup: [ms_hash / ms_typed]x"
<< ""
