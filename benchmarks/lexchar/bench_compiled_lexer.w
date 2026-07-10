# LexChar benchmark — compiled Tungsten lexer throughput
use ../compiler/lib/lexer

args = argv()
if args.size() == 0
  << "usage: bench_compiled_lexer.w <file.w> [rounds]"
  exit(1)

file = args[0]
rounds = 10
if args.size() > 1
  rounds = args[1].to_i()

source = read_file(file)
char_count = source.size()
<< "LexChar — compiled lexer benchmark"
<< "  file: [file] ([char_count] chars)"

# Warmup
i = 0
while i < 3
  Lexer.new(source, file).tokenize()
  i = i + 1

# Benchmark
t0 = ccall("__w_clock_ms")
total_tokens = 0 ## i64
i = 0
while i < rounds
  tokens = Lexer.new(source, file).tokenize()
  total_tokens = total_tokens + tokens.size()
  i = i + 1

t1 = ccall("__w_clock_ms")
ms = t1 - t0
secs = ms / 1000

chars_total = char_count * rounds
tokens_per_round = total_tokens / rounds

<< ""
<< "  [rounds] rounds in [ms]ms"
<< "  [chars_total / ms * 1000 / 1000000]M chars/sec"
<< "  [total_tokens / ms * 1000 / 1000000]M tokens/sec"
<< "  [tokens_per_round] tokens per lex"
<< ""
