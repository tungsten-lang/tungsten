# LexChar-enabled lexer — uses integer codepoints + bitmask classification
# This is a benchmark variant of compiler/lib/lexer.w

# LexChar bitmask constants
LC_DIGIT = 1
LC_LOWER = 2
LC_UPPER = 4
LC_HEX = 8
LC_IDENT_START = 16
LC_IDENT_CHAR = 32
LC_NAME_CHAR = 64
LC_WHITESPACE = 128

# LexChar table (128 entries, ASCII only)
LEXCHAR = [
  0, 0, 0, 0, 0, 0, 0, 0, 0, 128, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  128, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  105, 105, 105, 105, 105, 105, 105, 105, 105, 105, 0, 0, 0, 0, 0, 0,
  0, 76, 76, 76, 76, 76, 76, 68, 68, 68, 68, 68, 68, 68, 68, 68,
  68, 68, 68, 68, 68, 68, 68, 68, 68, 68, 68, 0, 0, 0, 0, 112,
  0, 122, 122, 122, 122, 122, 122, 114, 114, 114, 114, 114, 114, 114, 114, 114,
  114, 114, 114, 114, 114, 114, 114, 114, 114, 114, 114, 0, 0, 0, 0, 0
]

-> lc(cp)
  if cp < 128
    return LEXCHAR[cp]
  0

-> lc_digit?(cp)
  cp < 128 && (LEXCHAR[cp] & 1) != 0

-> lc_lower?(cp)
  cp < 128 && (LEXCHAR[cp] & 2) != 0

-> lc_upper?(cp)
  cp < 128 && (LEXCHAR[cp] & 4) != 0

-> lc_alpha?(cp)
  cp < 128 && (LEXCHAR[cp] & 6) != 0

-> lc_hex?(cp)
  cp < 128 && (LEXCHAR[cp] & 8) != 0

-> lc_ident_start?(cp)
  cp < 128 && (LEXCHAR[cp] & 16) != 0

-> lc_ident_char?(cp)
  cp < 128 && (LEXCHAR[cp] & 32) != 0

-> lc_name_char?(cp)
  cp < 128 && (LEXCHAR[cp] & 64) != 0

-> lc_whitespace?(cp)
  cp < 128 && (LEXCHAR[cp] & 128) != 0

# Benchmark: classify every character in a source file N times
args = argv()
if args.length() == 0
  << "usage: lexer_lexchar.w <file.w> [rounds]"
  exit(1)

file = args[0]
rounds = 10
if args.length() > 1
  rounds = args[1].to_i()

source = read_file(file)
codes = source.codes()
char_count = codes.length()

<< "LexChar benchmark"
<< "  file: [file] ([char_count] chars, [rounds] rounds)"

# Warmup
i = 0 ## i64
while i < char_count
  lc_digit?(codes[i])
  i += 1

# Benchmark: classify every codepoint
t0 = ccall("__w_clock_ms")
total = 0 ## i64
r = 0 ## i64
while r < rounds
  i = 0
  while i < char_count
    cp = codes[i]
    if lc_ident_char?(cp)
      total += 1
    elsif lc_digit?(cp)
      total += 1
    elsif lc_whitespace?(cp)
      total += 1
    i += 1
  r += 1

t1 = ccall("__w_clock_ms")
ms = t1 - t0
chars_total = char_count * rounds

<< ""
<< "  LexChar classify: [ms]ms"
<< "  [chars_total / ms * 1000 / 1000000]M chars/sec"
<< "  total classified: [total]"
<< ""
