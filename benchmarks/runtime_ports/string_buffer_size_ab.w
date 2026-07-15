# Function-level A/B benchmark for moving StringBuffer#size from its C IC
# handler to a native Tungsten field accessor.  The public `size` call is the
# current C baseline. An explicit `i64` return-signature variant was also
# tried, but generated identical WIRE and LLVM, so only one copy is timed.

use ../../core/string_buffer

CORPUS_SIZE = 8
CORPUS_MASK = CORPUS_SIZE - 1
DEFAULT_ITERS = 50_000_000
WARMUP_ITERS = 100_000

+ StringBuffer
  - data
    u8     flags
    u8[7]  _pad
    * u8[] data
    i64    length
    i64    capacity

  -> __w_size
    $length

-> build_corpus
  texts = ["", "a", "hello", "sixteen bytes....",
           "a somewhat longer string buffer payload",
           "\u03bb\u03bb\u03bb\u03bb", "0123456789", "end"]
  buffers = []
  i = 0
  while i < texts.size()
    buffer = StringBuffer(64)
    # Setup is outside the timed region. Use the allocation primitive directly
    # because StringBuffer#append is still a bodyless compiler/runtime builtin.
    ccall("w_strbuf_append", buffer, texts[i])
    buffers.push(buffer)
    i += 1
  buffers

-> check_value(name, case_index, got, expected)
  if got != expected
    << "FAIL [name] case=[case_index] got=[got] expected=[expected]"
    exit(1)

-> run_correctness(buffers)
  i = 0
  while i < buffers.size()
    buffer = buffers[i]
    check_value("size", i, buffer.__w_size, buffer.size)
    i += 1
  << "correctness: ok ([buffers.size()] exact C/W comparisons)"

-> finish_timing(start_ns, checksum)
  [clock() - start_ns, checksum]

-> time_size_c(buffers, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += buffers[i & CORPUS_MASK].size
    i += 1
  finish_timing(start_ns, checksum)

-> time_size_w(buffers, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += buffers[i & CORPUS_MASK].__w_size
    i += 1
  finish_timing(start_ns, checksum)

-> report_result(name, c_result, w_result, iters)
  if c_result[1] != w_result[1]
    << "FAIL benchmark checksum [name]: C=[c_result[1]] W=[w_result[1]]"
    exit(1)
  c_ns = c_result[0] * 1_000_000_000 / iters
  w_ns = w_result[0] * 1_000_000_000 / iters
  ratio = w_result[0] / c_result[0]
  << "RESULT|[name]|[c_ns]|[w_ns]|[ratio]|[c_result[1]]"

-> run_pair(buffers, iters, parity, emit = true)
  if parity == 0
    c_result = time_size_c(buffers, iters)
    w_result = time_size_w(buffers, iters)
  else
    w_result = time_size_w(buffers, iters)
    c_result = time_size_c(buffers, iters)
  if emit
    report_result("size", c_result, w_result, iters)

-> run_bench(buffers, iters, parity)
  run_pair(buffers, WARMUP_ITERS, parity, false)
  run_pair(buffers, iters, parity)

args = argv()
mode = args.size() > 0 ? args[0] : "bench"
buffers = build_corpus()

if mode == "check"
  run_correctness(buffers)
  exit(0)

iters = DEFAULT_ITERS
if args.size() > 1
  iters = args[1].to_i
if iters <= 0
  << "iterations must be positive"
  exit(2)

parity = 0
if args.size() > 2
  if args[2] != "0" && args[2] != "1"
    << "sample parity must be 0 (C/W) or 1 (W/C)"
    exit(2)
  parity = args[2].to_i

run_bench(buffers, iters, parity)
