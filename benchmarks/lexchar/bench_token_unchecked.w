# Token benchmark — unchecked raw pointer access
#
# Uses w_i64_array_ptr + w_ptr_get_i64 to bypass bounds checking.

use ../compiler/lib/lexer

# Pre-shifted token type bases
T_ID  = 1 << 32
T_INT = 2 << 32
T_OTH = 7 << 32

## i64: lc_ptr, count
fn tokenize_unchecked(lc_ptr, chars, count)
  tokens = i64[count]
  tok_ptr = ccall("w_i64_array_ptr", tokens)
  pos = 0 ## i64
  token_count = 0 ## i64

  while pos < count
    v = ccall("w_ptr_get_i64", lc_ptr, pos) ## i64
    flags = (v & 127) ## i64

    # Whitespace — skip
    if (flags & 16) != 0
      pos += 1
      while pos < count && (ccall("w_ptr_get_i64", lc_ptr, pos) & 16) != 0
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
      while pos < count && (ccall("w_ptr_get_i64", lc_ptr, pos) & 32) != 0
        pos += 1
      ccall("w_ptr_set_i64", tok_ptr, token_count, T_ID | ((pos - start) << 20) | start)
      token_count += 1
      next

    # Integer
    if ((v >> 7) & 15) != 15
      start = pos ## i64
      pos += 1
      while pos < count && ((ccall("w_ptr_get_i64", lc_ptr, pos) >> 7) & 15) != 15
        pos += 1
      ccall("w_ptr_set_i64", tok_ptr, token_count, T_INT | ((pos - start) << 20) | start)
      token_count += 1
      next

    # Everything else — single char
    ccall("w_ptr_set_i64", tok_ptr, token_count, T_OTH | (1 << 20) | pos)
    token_count += 1
    pos += 1

  token_count

# Benchmark
args = argv()
if args.length() == 0
  << "usage: bench_token_unchecked.w <file.w> [rounds]"
  exit(1)

file = args[0]
rounds = 20
if args.length() > 1
  rounds = args[1].to_i()

source = read_file(file)
lc = source.lchs()
lc_ptr = ccall("w_i64_array_ptr", lc) ## i64
chars = source.chars()
char_count = source.length()
lc_count = lc.length()

<< "Token unchecked pointer benchmark"
<< "  file: [file] ([char_count] chars, [rounds] rounds)"

# Warmup
tokenize_unchecked(lc_ptr, chars, lc_count)

# Benchmark: unchecked pointer tokens
t0 = ccall("__w_clock_ms")
total = 0 ## i64
r = 0 ## i64
while r < rounds
  total += tokenize_unchecked(lc_ptr, chars, lc_count)
  r += 1
t1 = ccall("__w_clock_ms")
ms = t1 - t0

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

mchars = char_count * rounds / ms * 1000 / 1000000
hash_mchars = char_count * rounds / ms_hash * 1000 / 1000000

<< ""
<< "  unchecked ptr: [ms]ms  [mchars]M chars/sec  ([total / rounds] tokens/lex)"
<< "  hash tokens:   [ms_hash]ms  [hash_mchars]M chars/sec  ([total_hash / rounds] tokens/lex)"
<< "  Speedup: [ms_hash / ms]x"
<< ""
