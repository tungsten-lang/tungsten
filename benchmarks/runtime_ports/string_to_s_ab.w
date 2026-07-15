# Representation-stratified String/Symbol#to_s port benchmark.
#
# __c_to_s keeps the removed C body's semantics behind the same cached source
# dispatch shape as __w_to_s. Public `to_s` independently measures the actual
# runtime route: C IC in the baseline tree, shared 0xF9 Tungsten method in the
# candidate tree.

use ../../core/string_native

DEFAULT_ITERS = 40_000_000
WARMUP_ITERS = 200_000

+ String
  -> __c_to_s
    ccall("w_ref_string_symbol_to_s", self)

  -> __w_to_s
    wvalue_from_bits($value & -2)

  -> __to_s_storage_mode
    ($value >> 1) & 7

-> check(name, got, want)
  if got != want
    << "FAIL [name]: got=[got] want=[want]"
    exit(1)

-> make_rope(ch)
  (ch * 40) + (ch * 41)

-> build_corpora
  inline = ["", "a", "ab", "abc", "abcd", "abcde", "z", "12345"]

  slab = ["123456", "slab-07", "slab-eight", "slab-backed-11",
          "a medium slab-backed string", "utf8-π", "12345678901234567890",
          "123456789012345678901234567890123456789012345678901234"]

  heap = ["".concat("h"), "a" * 55, "b" * 64, "c" * 80,
          "d" * 96, "e" * 127, "f" * 256, "g" * 1024]

  rope = [make_rope("a"), make_rope("b"), make_rope("c"), make_rope("d"),
          make_rope("e"), make_rope("f"), make_rope("g"), make_rope("h")]

  symbol_inline = ["".to_sym, "a".to_sym, "ab".to_sym, "abc".to_sym,
                   "abcd".to_sym, "abcde".to_sym, "z".to_sym, "12345".to_sym]

  symbol_slab = ["123456".to_sym, "symbol7".to_sym, "symbol-eight".to_sym,
                 "symbol-eleven".to_sym, "a-medium-symbol".to_sym,
                 "utf8-π".to_sym, "12345678901234567890".to_sym,
                 "a-symbol-long-enough-for-two-slab-slots-1234567890".to_sym]

  [inline, slab, heap, rope, symbol_inline, symbol_slab]

-> corpus_name(index)
  case index
  when 0
    "inline"
  when 1
    "slab"
  when 2
    "heap"
  when 3
    "rope"
  when 4
    "symbol_inline"
  when 5
    "symbol_slab"

-> run_correctness(corpora)
  ci = 0
  while ci < corpora.size
    values = corpora[ci]
    i = 0
    while i < values.size
      value = values[i]
      c_value = value.__c_to_s
      w_value = value.__w_to_s
      public_value = value.to_s
      label = corpus_name(ci) + "[" + i.to_s + "]"
      check(label + " C/W content", w_value, c_value)
      check(label + " public content", public_value, c_value)
      check(label + " C/W bits", wvalue_bits(w_value), wvalue_bits(c_value))
      check(label + " public bits", wvalue_bits(public_value), wvalue_bits(c_value))
      check(label + " result type", type(public_value), "String")

      # Non-rope strings retain exact identity; symbols differ by exactly the
      # low marker bit. Rope dispatch intentionally compares the cached flat
      # result because flattening happens before either method body runs.
      if ci < 3
        check(label + " String identity", wvalue_bits(public_value), wvalue_bits(value))
      elsif ci >= 4
        check(label + " Symbol bit clear", wvalue_bits(public_value), wvalue_bits(value) & -2)
      i += 1
    ci += 1

  check("inline storage", corpora[0][1].__to_s_storage_mode, 1)
  check("inline max storage", corpora[0][7].__to_s_storage_mode, 5)
  check("slab storage", corpora[1][0].__to_s_storage_mode, 6)
  check("heap short storage", corpora[2][0].__to_s_storage_mode, 7)
  check("heap long storage", corpora[2][7].__to_s_storage_mode, 7)
  check("rope flattened storage", corpora[3][0].__to_s_storage_mode, 7)
  check("inline symbol storage", corpora[4][1].__to_s_storage_mode, 1)
  check("slab symbol storage", corpora[5][0].__to_s_storage_mode, 6)
  << "correctness: ok (48 values; exact content, type, and WValue bits)"

-> now_ns
  ccall("w_to_s_thread_cpu_ns")

-> finish_timing(start_ns, checksum)
  elapsed = now_ns() - start_ns
  [elapsed, checksum]

-> time_c(values, iters)
  checksum = 0
  i = 0
  start_ns = now_ns()
  while i < iters
    result = values[i & 7].__c_to_s
    checksum += (wvalue_bits(result) >> 4) & 0xFFFF
    i += 1
  finish_timing(start_ns, checksum)

-> time_w(values, iters)
  checksum = 0
  i = 0
  start_ns = now_ns()
  while i < iters
    result = values[i & 7].__w_to_s
    checksum += (wvalue_bits(result) >> 4) & 0xFFFF
    i += 1
  finish_timing(start_ns, checksum)

-> time_public(values, iters)
  checksum = 0
  i = 0
  start_ns = now_ns()
  while i < iters
    result = values[i & 7].to_s
    checksum += (wvalue_bits(result) >> 4) & 0xFFFF
    i += 1
  finish_timing(start_ns, checksum)

-> emit_result(name, c_result, w_result, public_result, iters)
  check(name + " benchmark C/W checksum", w_result[1], c_result[1])
  check(name + " benchmark public checksum", public_result[1], c_result[1])
  c_ns = c_result[0].to_f / iters
  w_ns = w_result[0].to_f / iters
  public_ns = public_result[0].to_f / iters
  << "RESULT|[name]|[c_ns]|[w_ns]|[public_ns]|[w_ns / c_ns]|[public_ns / c_ns]|[c_result[1]]"

-> run_pair(name, values, iters, parity, emit = true)
  if parity == 0
    c_result = time_c(values, iters)
    w_result = time_w(values, iters)
    public_result = time_public(values, iters)
  else
    public_result = time_public(values, iters)
    w_result = time_w(values, iters)
    c_result = time_c(values, iters)
  if emit
    emit_result(name, c_result, w_result, public_result, iters)

args = argv()
mode = args.size > 0 ? args[0] : "bench"
corpora = build_corpora()

if mode == "check"
  run_correctness(corpora)
  exit(0)

iters = args.size > 1 ? args[1].to_i : DEFAULT_ITERS
parity = args.size > 2 ? args[2].to_i : 0
if iters <= 0 || (parity != 0 && parity != 1)
  << "usage: string_to_s_ab bench [positive-iters] [0|1]"
  exit(2)

ci = 0
while ci < corpora.size
  run_pair(corpus_name(ci), corpora[ci], WARMUP_ITERS, parity, false)
  run_pair(corpus_name(ci), corpora[ci], iters, parity)
  ci += 1
