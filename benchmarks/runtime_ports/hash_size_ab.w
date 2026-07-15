# Function-level A/B benchmark for moving Hash#size from its C IC handler to
# a native Tungsten view-field load. Unique names keep the two implementations
# independently callable while the production intrinsic remains installed.

use ../../core/hash

CORPUS_SIZE = 16
CORPUS_MASK = CORPUS_SIZE - 1
DEFAULT_ITERS = 50_000_000
WARMUP_ITERS = 100_000

+ Hash
  -> __c_size
    ccall("w_ref_hash_size", self)

  -> __w_size
    $count

-> build_corpus
  hashes = []
  i = 0
  while i < CORPUS_SIZE
    hash = {}
    j = 0
    while j < i
      hash[j] = i * 100 + j
      j += 1
    hashes.push(hash)
    i += 1
  hashes

-> run_correctness(hashes)
  i = 0
  while i < hashes.size
    c_result = hashes[i].__c_size
    w_result = hashes[i].__w_size
    if c_result != i || w_result != c_result
      << "FAIL size case=[i] C=[c_result] W=[w_result] expected=[i]"
      exit(1)
    i += 1
  << "correctness: ok ([hashes.size] exact C/W comparisons; counts 0..[CORPUS_SIZE - 1])"

-> finish_timing(start_ns, checksum)
  [clock() - start_ns, checksum]

-> time_size_c(hashes, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += hashes[i & CORPUS_MASK].__c_size
    i += 1
  finish_timing(start_ns, checksum)

-> time_size_w(hashes, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += hashes[i & CORPUS_MASK].__w_size
    i += 1
  finish_timing(start_ns, checksum)

-> report_result(c_result, w_result, iters)
  if c_result[1] != w_result[1]
    << "FAIL benchmark checksum size: C=[c_result[1]] W=[w_result[1]]"
    exit(1)
  c_ns = c_result[0] * 1_000_000_000 / iters
  w_ns = w_result[0] * 1_000_000_000 / iters
  ratio = w_result[0] / c_result[0]
  << "RESULT|size|[c_ns]|[w_ns]|[ratio]|[c_result[1]]"

-> run_pair(hashes, iters, parity, emit = true)
  if parity == 0
    c_result = time_size_c(hashes, iters)
    w_result = time_size_w(hashes, iters)
  else
    w_result = time_size_w(hashes, iters)
    c_result = time_size_c(hashes, iters)
  if emit
    report_result(c_result, w_result, iters)

-> run_bench(hashes, iters, parity)
  run_pair(hashes, WARMUP_ITERS, parity, false)
  run_pair(hashes, iters, parity)

args = argv()
mode = args.size() > 0 ? args[0] : "bench"
hashes = build_corpus()

if mode == "check"
  run_correctness(hashes)
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

run_bench(hashes, iters, parity)
