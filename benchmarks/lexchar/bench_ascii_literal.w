# Long-string benchmark for the production Lex64 string paths.
#
# The packed token format has a 12-bit length field, so the default 4,090
# character body stays just below the 4,095-character token limit. Repeating
# the literal builds a multi-megabyte source without exercising overflow.
#
# Build and run, for example:
#   TUNGSTEN_C_INCLUDES=runtime/lexchar_tables.c bin/tungsten compile \
#     benchmarks/lexchar/bench_ascii_literal.w --release --native \
#     --out /tmp/bench-ascii-literal
#   /tmp/bench-ascii-literal ascii 300 10
#   /tmp/bench-ascii-literal double-ascii 300 10
#   /tmp/bench-ascii-literal double-unicode-chars 300 10
#   /tmp/bench-ascii-literal double-unicode-bytes 300 10

use ../../compiler/lib/lexer

# Keep the LexChar dependency visible in ordinary builds. Release-mode WIRE
# pruning can remove this no-op marker, which is why the reproducible release
# command above explicitly includes runtime/lexchar_tables.c.
-> lexchars_link_marker
  nil

lexchars_link_marker()

args = argv()
if args.size() == 0
  << "usage: bench_ascii_literal <ascii|double-ascii|double-unicode-chars|double-unicode-bytes> [scan-rounds] [full-rounds]"
  exit(1)

kind = args[0]
scan_rounds = 300
if args.size() > 1
  scan_rounds = args[1].to_i()
full_rounds = 10
if args.size() > 2
  full_rounds = args[2].to_i()

body_chars = 4090
literal_count = 512
quote = "\""
body_char = "a"
label = "double-quoted ASCII payload"

if kind == "ascii"
  quote = "'"
  label = "single-quoted ASCII literal"
elsif kind == "double-unicode-chars"
  body_char = "é"
  label = "double-quoted Unicode, matched codepoints"
elsif kind == "double-unicode-bytes"
  body_char = "é"
  body_chars = 2045
  label = "double-quoted Unicode, matched source bytes"
elsif kind != "double-ascii"
  << "unknown case: [kind]"
  exit(1)

body_buffer = StringBuffer(8192)
i = 0
while i < body_chars
  body_buffer << body_char
  i += 1
body = body_buffer.to_s()

line = quote + body + quote + "\n"
source_buffer = StringBuffer(4_300_000)
i = 0
while i < literal_count
  source_buffer << line
  i += 1
source = source_buffer.to_s()
source_bytes = source.size()
chars = source.lchs("tungsten")
char_count = chars.size()
tokens = i64[char_count + 2048]
indents = i64[1024]

# Warm both the scanner and the full token materialization path, and fail the
# benchmark early if this input is not accepted by the production lexer.
warm_scan_tokens = tungsten_tokenize_fast64(chars, char_count, tokens, indents)
warm_full_tokens = Lexer.new(source, "<ascii-literal-benchmark>").tokenize()

scan_sum = 0
i = 0
scan_start = ccall("__w_clock_ms")
while i < scan_rounds
  scan_sum += tungsten_tokenize_fast64(chars, char_count, tokens, indents)
  i += 1
scan_ms = ccall("__w_clock_ms") - scan_start
if scan_ms == 0
  scan_ms = 1

full_sum = 0
i = 0
full_start = ccall("__w_clock_ms")
while i < full_rounds
  full_sum += Lexer.new(source, "<ascii-literal-benchmark>").tokenize()
  i += 1
full_ms = ccall("__w_clock_ms") - full_start
if full_ms == 0
  full_ms = 1

scan_bytes = source_bytes * scan_rounds
scan_chars = char_count * scan_rounds
full_bytes = source_bytes * full_rounds
full_chars = char_count * full_rounds

<< "[kind]: [label]"
<< "  source: [source_bytes] bytes, [char_count] lex chars, [literal_count] literals, [body.size()] body bytes"
<< "  scan: [scan_ms] ms, [scan_bytes * 1000 / scan_ms / 1000000] MB/s, [scan_chars * 1000 / scan_ms / 1000000] Mchar/s, [scan_sum / scan_rounds] tokens/round"
<< "  full: [full_ms] ms, [full_bytes * 1000 / full_ms / 1000000] MB/s, [full_chars * 1000 / full_ms / 1000000] Mchar/s, [full_sum / full_rounds] tokens/round"
<< "  warmup: scan=[warm_scan_tokens] full=[warm_full_tokens]"
