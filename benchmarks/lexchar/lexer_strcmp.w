# String-comparison lexer predicates — baseline benchmark
# Uses the same predicate pattern as the current self-hosted lexer

-> sc_digit?(ch)
  ch >= "0" && ch <= "9"

-> sc_lower?(ch)
  ch >= "a" && ch <= "z"

-> sc_ident_char?(ch)
  sc_lower?(ch) || sc_digit?(ch) || ch == "_"

-> sc_whitespace?(ch)
  ch == " " || ch == "\t"

# Benchmark: classify every character in a source file N times
args = argv()
if args.length() == 0
  << "usage: lexer_strcmp.w <file.w> [rounds]"
  exit(1)

file = args[0]
rounds = 10
if args.length() > 1
  rounds = args[1].to_i()

source = read_file(file)
chars = source.chars()
char_count = chars.length()

<< "String-compare baseline benchmark"
<< "  file: [file] ([char_count] chars, [rounds] rounds)"

# Warmup
i = 0 ## i64
while i < char_count
  sc_digit?(chars[i])
  i += 1

# Benchmark: classify every character
t0 = ccall("__w_clock_ms")
total = 0 ## i64
r = 0 ## i64
while r < rounds
  i = 0
  while i < char_count
    ch = chars[i]
    if sc_ident_char?(ch)
      total += 1
    elsif sc_digit?(ch)
      total += 1
    elsif sc_whitespace?(ch)
      total += 1
    i += 1
  r += 1

t1 = ccall("__w_clock_ms")
ms = t1 - t0
chars_total = char_count * rounds

<< ""
<< "  String classify: [ms]ms"
<< "  [chars_total / ms * 1000 / 1000000]M chars/sec"
<< "  total classified: [total]"
<< ""
