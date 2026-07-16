# Production-shaped public benchmark for String/Symbol#empty?. Compile this
# unchanged source against isolated native-IC and source-method roots. There is
# deliberately no explicit `use`: the public call must trigger core autoload.

CORPUS_SIZE = 16
CORPUS_MASK = CORPUS_SIZE - 1
DEFAULT_ITERS = 30_000_000
WARMUP_ITERS = 5_000_000

-> thread_cpu_ns
  ccall("w_runtime_port_thread_cpu_ns")

-> build_corpus(stratum)
  if stratum == "inline"
    return ["", "a", "", "12", "", "123", "", "1234",
            "", "12345", "", "x", "", "xy", "", "xyz"]

  if stratum == "slab"
    return ["", "123456", "", "1234567", "", "slab-backed text", "", "abcdefgh",
            "", "123456789", "", "another slab value", "", "abcdef", "", "short slab"]

  if stratum == "heap"
    h1 = "h" * 80
    h2 = "i" * 96
    h3 = "j" * 128
    h4 = "k" * 160
    return ["", h1, "", h2, "", h3, "", h4,
            "", "".concat("a"), "", "".concat("bc"), "", h2 + h1, "", h4 + h3]

  if stratum == "rope"
    left = "l" * 40
    right = "r" * 40
    a = left + right
    b = right + left
    c = a + b
    d = b + a
    return ["", a, "", b, "", c, "", d,
            "", a + c, "", b + d, "", c + a, "", d + b]

  if stratum == "symbol"
    return ["".to_sym, "a".to_sym, "".to_sym, "ab".to_sym,
            "".to_sym, "symbol".to_sym, "".to_sym, "long_symbol_name".to_sym,
            "".to_sym, "x".to_sym, "".to_sym, "xy".to_sym,
            "".to_sym, "another".to_sym, "".to_sym, "final".to_sym]

  << "unknown stratum: [stratum]"
  exit(2)

-> check_stratum(stratum)
  values = build_corpus(stratum)
  i = 0
  while i < values.size
    expected = (i & 1) == 0
    got = values[i].empty?
    if got != expected
      << "FAIL public.empty?/[stratum]/[i] got=[got] expected=[expected]"
      exit(1)
    i += 1

-> run_check
  check_stratum("inline")
  check_stratum("slab")
  check_stratum("heap")
  check_stratum("rope")
  check_stratum("symbol")
  if !"".empty?(123, "ignored") || "x".empty?(123)
    << "FAIL public.empty? surplus-argument compatibility"
    exit(1)
  << "correctness: ok (80 public representation checks plus surplus arguments)"

-> time_public(values, iters)
  checksum = 0
  i = 0
  started = thread_cpu_ns()
  while i < iters
    checksum += values[i & CORPUS_MASK].empty? ? 1 : 0
    i += 1
  [thread_cpu_ns() - started, checksum]

args = argv()
mode = args.size > 0 ? args[0] : "check"

if mode == "check"
  run_check()
  exit(0)
if mode != "bench"
  << "mode must be check or bench"
  exit(2)

stratum = args.size > 1 ? args[1] : "inline"
iters = args.size > 2 ? args[2].to_i : DEFAULT_ITERS
if iters <= 0
  << "iterations must be positive"
  exit(2)
values = build_corpus(stratum)
time_public(values, WARMUP_ITERS)
result = time_public(values, iters)
<< "RESULT|public.empty?.[stratum]|[result[0]]|[result[1]]"
