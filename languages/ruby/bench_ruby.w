# languages/ruby/bench_ruby.w — Head-to-head Ruby 4.0.9 performance benchmark
# comparing Tungsten Ruby (`core/ruby`) vs CRuby 4.0.9 (`--disable-yjit` and `+YJIT`).

use core/ruby

CRUBY_BIN = "/Users/erik/.rubies/ruby-4.0.9/bin/ruby"

BENCHMARKS = [
  ["fib(28) recursive", '
def fib(n)
  return n if n < 2
  fib(n - 1) + fib(n - 2)
end
fib(28)
'],
  ["tight while loop sum (200k)", '
def sum_to(n)
  s = 0
  i = 1
  while i <= n
    s += i
    i += 1
  end
  s
end
sum_to(200000)
'],
  ["sieve of Eratosthenes (20k)", '
def sieve(n)
  a = Array.new(n + 1, true)
  i = 2
  while i * i <= n
    if a[i]
      j = i * i
      while j <= n
        a[j] = false
        j += i
      end
    end
    i += 1
  end
  c = 0
  k = 2
  while k <= n
    c += 1 if a[k]
    k += 1
  end
  c
end
sieve(20000)
'],
  ["ackermann(3, 6)", '
def ack(m, n)
  return n + 1 if m == 0
  return ack(m - 1, 1) if n == 0
  ack(m - 1, ack(m, n - 1))
end
ack(3, 6)
'],
  ["string concat loop (20k)", '
def build_str(n)
  s = ""
  i = 0
  while i < n
    s << "ab"
    i += 1
  end
  s.length
end
build_str(20000)
'],
  ["array map/select (5k)", '
(1..5000).to_a.map { |x| x * 3 + 1 }.select { |x| x % 2 == 0 }.size
'],
  ["regex scan + named captures (2k)", '
rx = /(?<k>[a-z]+)=(?<v>\d+)/
s = "alpha=10 beta=20 gamma=30 delta=40"
tot = 0
i = 0
while i < 2000
  m = rx.match(s)
  tot += m[:v].to_i if m
  i += 1
end
tot
']
]

-> bench_cruby(flags, code)
  # Measure internal wall time inside CRuby so process startup isn't counted against CRuby!
  wrapper = "t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)\n" +
            "res = begin\n" + code + "\nend\n" +
            "dt = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000.0\n" +
            "puts \"#{dt.round(2)}|#{res}\"\n"
  File.write("/tmp/rb_bench_case.rb", wrapper)
  out = OS.capture(CRUBY_BIN + " " + flags + " /tmp/rb_bench_case.rb 2>/dev/null").to_s.strip
  parts = out.split("|")
  [parts[0].to_f, parts.size > 1 ? parts[1] : ""]

<< "========================================================================================"
<< "  Ruby 4.0.9 Head-to-Head Benchmark: Tungsten Ruby vs CRuby 4.0.9 (Interp & YJIT)"
<< "  (Pure execution time in ms, excluding process startup)"
<< "========================================================================================"

BENCHMARKS.each ->(b)
  name = b[0]
  code = b[1]
  # Parse once, measure eval (same as CRuby's internal timer)
  vm = Ruby.vm
  ast = Ruby.parse(code)
  t0 = clock()
  got = vm.eval_node(ast, vm.top_env)
  w_ms = (clock() - t0) * ~1000.0
  w_res = got.to_s

  c_int = bench_cruby("--disable-yjit", code)
  c_yjit = bench_cruby("--yjit", code)
  ok = w_res == c_int[1] ? "OK" : ("MISMATCH(" + w_res + " vs " + c_int[1] + ")")
  ratio_int = c_int[0] > ~0.01 ? (w_ms / c_int[0]) : ~0.0
  << name + '  [' + ok + ']'
  << "  Tungsten Ruby: " + ((w_ms * ~100.0).round / ~100.0).to_s + " ms" +
     "  |  CRuby 4.0.9 (interp): " + c_int[0].to_s + " ms" +
     "  |  CRuby 4.0.9 (+YJIT): " + c_yjit[0].to_s + " ms" +
     "  |  vs CRuby interp: " + ((ratio_int * ~100.0).round / ~100.0).to_s + "x"

# Lexer throughput benchmark (LexChar WValue + packed 64-bit Token stream)
sample = ""
k = 0
while k < 200
  sample = sample + "class Order#{k}\n  def calc(price, qty)\n    total = price * qty\n    total > 100 ? total * 0.9 : total\n  end\nend\n"
  k += 1
t0 = clock()
iters = 20
ii = 0
tok_n = 0
while ii < iters
  ts = RbLexer.new(sample).tokenize
  tok_n = ts.size
  ii += 1
lex_ms = (clock() - t0) * ~1000.0
mb_s = (sample.size * iters).to_f / (~1024.0 * ~1024.0) / (lex_ms / ~1000.0)
<< "----------------------------------------------------------------------------------------"
<< "LexChar + Packed Token Lexer: " + (sample.size * iters).to_s + " bytes (" + (tok_n * iters).to_s + " tokens) in " +
   ((lex_ms * ~100.0).round / ~100.0).to_s + " ms (" + ((mb_s * ~10.0).round / ~10.0).to_s + " MB/s)"
