# Benchmark the alternate packed Tungsten lexer spikes.
#
# Compile first:
#   bin/tungsten compile compiler/bench_lex.w --out /tmp/tungsten-lex-bench
# Then run:
#   /tmp/tungsten-lex-bench compiler/tungsten.w 20

use lib/lexer
use ../languages/tungsten/lexers/regex
use ../languages/tungsten/lexers/lex32
use ../languages/tungsten/lexers/wtoken32

# See compiler/lex_parity.w: keep the gated LexChar tables linked even though
# String#lchs reaches the runtime through an unnamed inline-cache slot.
-> lexchars_link_marker
  nil

args = argv()
if args.size() == 0
  << "usage: bench_lex <file.w> [rounds]"
  exit(1)

file = args[0]
rounds = 10
if args.size() > 1
  rounds = args[1].to_i()

source = read_file(file)
byte_count = source.size()

lc64 = source.lchs("tungsten")
count64 = lc64.size()
tokens64 = i64[count64 + 2048]
indents64 = i64[1024]

lc32 = source.lchs("tungsten", bits: 32)
count32 = lc32.size()
tokens32 = i64[count32 + 2048]
indents32 = i64[1024]
tokens32_token = u32[count32 + 2048]
lengths32_token = u8[count32 + 2048]
indents32_token = i64[1024]

<< "Tungsten alternate lexer benchmark"
<< "  file: [file]"
<< "  chars: [count64]  bytes: [byte_count]  rounds: [rounds]"

# Warmup
t64 = tungsten_tokenize_fast64(lc64, count64, tokens64, indents64)
t32 = tungsten_tokenize_fast32(lc32, count32, tokens32, indents32)
t32_token = tungsten_tokenize_wtoken32(lc32, count32, tokens32_token, lengths32_token, indents32_token)
tcurrent = RegexLexer.new(source, file).tokenize().size()

t0 = ccall("__w_clock_ms")
total64 = 0
r = 0
while r < rounds
  total64 += tungsten_tokenize_fast64(lc64, count64, tokens64, indents64)
  r += 1
t1 = ccall("__w_clock_ms")

total32 = 0
r = 0
while r < rounds
  total32 += tungsten_tokenize_fast32(lc32, count32, tokens32, indents32)
  r += 1
t2 = ccall("__w_clock_ms")

total32_token = 0
r = 0
while r < rounds
  total32_token += tungsten_tokenize_wtoken32(lc32, count32, tokens32_token, lengths32_token, indents32_token)
  r += 1
t2_token = ccall("__w_clock_ms")

total_current = 0
r = 0
while r < rounds
  total_current += RegexLexer.new(source, file).tokenize().size()
  r += 1
t2_current = ccall("__w_clock_ms")

ms64 = t1 - t0
if ms64 == 0
  ms64 = 1
ms32 = t2 - t1
if ms32 == 0
  ms32 = 1
ms32_token = t2_token - t2
if ms32_token == 0
  ms32_token = 1
ms_current = t2_current - t2_token
if ms_current == 0
  ms_current = 1

bytes_total = byte_count * rounds
mb64 = bytes_total * 1000 / ms64 / 1000000
mb32 = bytes_total * 1000 / ms32 / 1000000
mb32_token = bytes_total * 1000 / ms32_token / 1000000
mb_current = bytes_total * 1000 / ms_current / 1000000

<< ""
<< "  lex64: [ms64]ms  tokens/round: [total64 / rounds]  throughput: [mb64] MB/s"
<< "  lex32: [ms32]ms  tokens/round: [total32 / rounds]  throughput: [mb32] MB/s"
<< "  wtoken32: [ms32_token]ms  tokens/round: [total32_token / rounds]  throughput: [mb32_token] MB/s"
<< "  regex lexer: [ms_current]ms  tokens/round: [total_current / rounds]  throughput: [mb_current] MB/s"
<< "  warmup tokens: lex64=[t64] lex32=[t32] wtoken32=[t32_token] regex=[tcurrent]"

# End-to-end timing includes lchs() materialization. Output token/indent buffers
# are call-site reused so the scan loop measures steady-state scratch reuse.
t3 = ccall("__w_clock_ms")
total64_e2e = 0
r = 0
while r < rounds
  lc64_e2e = source.lchs("tungsten")
  count64_e2e = lc64_e2e.size()
  tokens64_e2e = i64[count64_e2e + 2048] ## reuse
  indents64_e2e = i64[1024] ## reuse
  total64_e2e += tungsten_tokenize_fast64(lc64_e2e, count64_e2e, tokens64_e2e, indents64_e2e)
  r += 1
t4 = ccall("__w_clock_ms")

total32_e2e = 0
r = 0
while r < rounds
  lc32_e2e = source.lchs("tungsten", bits: 32)
  count32_e2e = lc32_e2e.size()
  tokens32_e2e = i64[count32_e2e + 2048] ## reuse
  indents32_e2e = i64[1024] ## reuse
  total32_e2e += tungsten_tokenize_fast32(lc32_e2e, count32_e2e, tokens32_e2e, indents32_e2e)
  r += 1
t5 = ccall("__w_clock_ms")

total32_token_e2e = 0
r = 0
while r < rounds
  lc32_token_e2e = source.lchs("tungsten", bits: 32)
  count32_token_e2e = lc32_token_e2e.size()
  tokens32_token_e2e = u32[count32_token_e2e + 2048] ## reuse
  lengths32_token_e2e = u8[count32_token_e2e + 2048] ## reuse
  indents32_token_e2e = i64[1024] ## reuse
  total32_token_e2e += tungsten_tokenize_wtoken32(lc32_token_e2e, count32_token_e2e, tokens32_token_e2e, lengths32_token_e2e, indents32_token_e2e)
  r += 1
t5_token = ccall("__w_clock_ms")

ms64_e2e = t4 - t3
if ms64_e2e == 0
  ms64_e2e = 1
ms32_e2e = t5 - t4
if ms32_e2e == 0
  ms32_e2e = 1
ms32_token_e2e = t5_token - t5
if ms32_token_e2e == 0
  ms32_token_e2e = 1

mb64_e2e = bytes_total * 1000 / ms64_e2e / 1000000
mb32_e2e = bytes_total * 1000 / ms32_e2e / 1000000
mb32_token_e2e = bytes_total * 1000 / ms32_token_e2e / 1000000

<< ""
<< "  e2e lex64: [ms64_e2e]ms  tokens/round: [total64_e2e / rounds]  throughput: [mb64_e2e] MB/s"
<< "  e2e lex32: [ms32_e2e]ms  tokens/round: [total32_e2e / rounds]  throughput: [mb32_e2e] MB/s"
<< "  e2e wtoken32: [ms32_token_e2e]ms  tokens/round: [total32_token_e2e / rounds]  throughput: [mb32_token_e2e] MB/s"
