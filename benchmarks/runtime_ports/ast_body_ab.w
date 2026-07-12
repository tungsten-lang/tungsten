# Function-level A/B benchmark for packed AST-body methods moved from
# runtime.c into core/ast_body.w. The C methods call exact copies of the old IC
# handlers from ast_body_ref.c; both sides dispatch on the same packed receiver.

use ../../core/ast_body

CORPUS_SIZE = 64
CORPUS_MASK = CORPUS_SIZE - 1
DEFAULT_ITERS = 50_000
WARMUP_ITERS = 1_000

+ Tungsten:AST:Body
  -> __c_size
    ccall("w_ref_body_size", self)

  -> __c_read(index)
    ccall("w_ref_body_read", self, index)

  -> __c_empty?
    ccall("w_ref_body_empty_p", self)

  -> __c_each(&block)
    ccall("w_ref_body_each", self, block)

  -> __c_map(&block)
    ccall("w_ref_body_map", self, block)

  -> __c_select(&block)
    ccall("w_ref_body_select", self, block)

  -> __c_reject(&block)
    ccall("w_ref_body_reject", self, block)

  -> __c_find(&block)
    ccall("w_ref_body_find", self, block)

  -> __c_any?
    ccall("w_ref_body_any_p", self, nil)

  -> __c_any_block?(&block)
    ccall("w_ref_body_any_p", self, block)

  -> __c_all?
    ccall("w_ref_body_all_p", self, nil)

  -> __c_all_block?(&block)
    ccall("w_ref_body_all_p", self, block)

  -> __c_none?
    ccall("w_ref_body_none_p", self, nil)

  -> __c_none_block?(&block)
    ccall("w_ref_body_none_p", self, block)

  -> __c_reduce(init, &block)
    ccall("w_ref_body_reduce", self, init, block)

  -> __c_compact
    ccall("w_ref_body_compact", self)

  -> __c_dup
    ccall("w_ref_body_dup", self)

-> freeze_body(values)
  ccall_nobox("w_ast_freeze_if_array", values)

-> fail_check(name, got, expected)
  << "FAIL [name]: got=[got] expected=[expected]"
  exit(1)

-> check_value(name, got, expected)
  if got != expected
    fail_check(name, got, expected)

-> check_array(name, got, expected)
  if got.size != expected.size
    fail_check(name + " size", got.size, expected.size)
  i = 0
  while i < got.size
    if got[i] != expected[i]
      fail_check(name + " item " + i.to_s, got[i], expected[i])
    i += 1

-> build_corpus
  bodies = []
  i = 0
  while i < CORPUS_SIZE
    values = []
    j = 0
    while j < 8
      values.push(((i * 17 + j * 7) & 0xFF) + 1)
      j += 1
    bodies.push(freeze_body(values))
    i += 1
  bodies

-> run_correctness
  empty = freeze_body([])
  mixed = freeze_body([nil, false, true, -4, 0, 3, 8])

  check_value("empty size", empty.size, empty.__c_size)
  check_value("empty predicate", empty.empty?, empty.__c_empty?)
  check_value("empty read zero", empty.read(0), empty.__c_read(0))
  check_value("empty read negative", empty.read(-1), empty.__c_read(-1))
  check_value("mixed size", mixed.size, mixed.__c_size)
  check_value("mixed predicate", mixed.empty?, mixed.__c_empty?)

  indexes = [-20, -8, -7, -2, -1, 0, 1, 6, 7, 20]
  i = 0
  while i < indexes.size
    index = indexes[i]
    check_value("read " + index.to_s, mixed.read(index), mixed.__c_read(index))
    check_value("index " + index.to_s, mixed[index], mixed.__c_read(index))
    i += 1

  c_seen = []
  w_seen = []
  mixed.__c_each -> (item)
    c_seen.push(item)
  returned = mixed.each -> (item)
    w_seen.push(item)
  check_array("each values", w_seen, c_seen)
  check_value("each returns self", returned, mixed)

  check_array("map",
              mixed.map -> (item) item == nil ? 99 : item,
              mixed.__c_map -> (item) item == nil ? 99 : item)
  check_array("select",
              mixed.select -> (item) item != nil && item != false,
              mixed.__c_select -> (item) item != nil && item != false)
  check_array("reject",
              mixed.reject -> (item) item == nil || item == false,
              mixed.__c_reject -> (item) item == nil || item == false)
  check_value("find",
              mixed.find -> (item) item == 3,
              mixed.__c_find -> (item) item == 3)

  check_value("any no block", mixed.any?, mixed.__c_any?)
  check_value("all no block", mixed.all?, mixed.__c_all?)
  check_value("none no block", mixed.none?, mixed.__c_none?)
  check_value("empty any no block", empty.any?, empty.__c_any?)
  check_value("empty all no block", empty.all?, empty.__c_all?)
  check_value("empty none no block", empty.none?, empty.__c_none?)
  check_value("any block",
              mixed.any? -> (item) item == 8,
              mixed.__c_any_block? -> (item) item == 8)
  check_value("all block",
              mixed.all? -> (item) item == nil || item == false || item == true || item <= 8,
              mixed.__c_all_block? -> (item) item == nil || item == false || item == true || item <= 8)
  check_value("none block",
              mixed.none? -> (item) item == 99,
              mixed.__c_none_block? -> (item) item == 99)

  check_value("reduce",
              mixed.compact.reduce(0) -> (acc, item) item == false || item == true ? acc : acc + item,
              mixed.__c_compact.reduce(0) -> (acc, item) item == false || item == true ? acc : acc + item)
  check_array("compact", mixed.compact, mixed.__c_compact)
  check_array("dup", mixed.dup, mixed.__c_dup)
  check_array("to_a", mixed.to_a, mixed.__c_dup)

  check_value("immutable index set", mixed.respond_to?("[]="), false)

  << "correctness: ok (empty/bounds/negative indexes and Enumerable combinators)"

-> finish_timing(start_ns, checksum)
  [clock() - start_ns, checksum]

-> time_size_c(bodies, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += bodies[i & CORPUS_MASK].__c_size
    i += 1
  finish_timing(start_ns, checksum)

-> time_size_w(bodies, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += bodies[i & CORPUS_MASK].size
    i += 1
  finish_timing(start_ns, checksum)

-> time_read_c(bodies, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += bodies[i & CORPUS_MASK].__c_read(i & 7)
    i += 1
  finish_timing(start_ns, checksum)

-> time_read_w(bodies, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += bodies[i & CORPUS_MASK].read(i & 7)
    i += 1
  finish_timing(start_ns, checksum)

-> time_empty_c(bodies, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += bodies[i & CORPUS_MASK].__c_empty? ? 1 : 0
    i += 1
  finish_timing(start_ns, checksum)

-> time_empty_w(bodies, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += bodies[i & CORPUS_MASK].empty? ? 1 : 0
    i += 1
  finish_timing(start_ns, checksum)

-> time_each_c(bodies, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    bodies[i & CORPUS_MASK].__c_each -> (item)
      checksum += item
    i += 1
  finish_timing(start_ns, checksum)

-> time_each_w(bodies, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    bodies[i & CORPUS_MASK].each -> (item)
      checksum += item
    i += 1
  finish_timing(start_ns, checksum)

-> time_map_c(bodies, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    out = bodies[i & CORPUS_MASK].__c_map -> (item) item + 1
    checksum += out[0] + out.size
    i += 1
  finish_timing(start_ns, checksum)

-> time_map_w(bodies, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    out = bodies[i & CORPUS_MASK].map -> (item) item + 1
    checksum += out[0] + out.size
    i += 1
  finish_timing(start_ns, checksum)

-> time_select_c(bodies, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    out = bodies[i & CORPUS_MASK].__c_select -> (item) (item & 1) == 0
    checksum += out.size
    i += 1
  finish_timing(start_ns, checksum)

-> time_select_w(bodies, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    out = bodies[i & CORPUS_MASK].select -> (item) (item & 1) == 0
    checksum += out.size
    i += 1
  finish_timing(start_ns, checksum)

-> time_reject_c(bodies, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    out = bodies[i & CORPUS_MASK].__c_reject -> (item) (item & 1) == 0
    checksum += out.size
    i += 1
  finish_timing(start_ns, checksum)

-> time_reject_w(bodies, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    out = bodies[i & CORPUS_MASK].reject -> (item) (item & 1) == 0
    checksum += out.size
    i += 1
  finish_timing(start_ns, checksum)

-> time_find_c(bodies, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += bodies[i & CORPUS_MASK].__c_find -> (item) item > 0
    i += 1
  finish_timing(start_ns, checksum)

-> time_find_w(bodies, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += bodies[i & CORPUS_MASK].find -> (item) item > 0
    i += 1
  finish_timing(start_ns, checksum)

-> time_any_c(bodies, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += bodies[i & CORPUS_MASK].__c_any? ? 1 : 0
    i += 1
  finish_timing(start_ns, checksum)

-> time_any_w(bodies, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += bodies[i & CORPUS_MASK].any? ? 1 : 0
    i += 1
  finish_timing(start_ns, checksum)

-> time_all_c(bodies, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += bodies[i & CORPUS_MASK].__c_all? ? 1 : 0
    i += 1
  finish_timing(start_ns, checksum)

-> time_all_w(bodies, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += bodies[i & CORPUS_MASK].all? ? 1 : 0
    i += 1
  finish_timing(start_ns, checksum)

-> time_none_c(bodies, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += bodies[i & CORPUS_MASK].__c_none? ? 1 : 0
    i += 1
  finish_timing(start_ns, checksum)

-> time_none_w(bodies, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += bodies[i & CORPUS_MASK].none? ? 1 : 0
    i += 1
  finish_timing(start_ns, checksum)

-> time_reduce_c(bodies, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += bodies[i & CORPUS_MASK].__c_reduce(0) -> (acc, item) acc + item
    i += 1
  finish_timing(start_ns, checksum)

-> time_reduce_w(bodies, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += bodies[i & CORPUS_MASK].reduce(0) -> (acc, item) acc + item
    i += 1
  finish_timing(start_ns, checksum)

-> time_compact_c(bodies, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += bodies[i & CORPUS_MASK].__c_compact.size
    i += 1
  finish_timing(start_ns, checksum)

-> time_compact_w(bodies, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += bodies[i & CORPUS_MASK].compact.size
    i += 1
  finish_timing(start_ns, checksum)

-> time_dup_c(bodies, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    out = bodies[i & CORPUS_MASK].__c_dup
    checksum += out.size + out[0]
    i += 1
  finish_timing(start_ns, checksum)

-> time_dup_w(bodies, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    out = bodies[i & CORPUS_MASK].dup
    checksum += out.size + out[0]
    i += 1
  finish_timing(start_ns, checksum)

-> report_result(name, c_result, w_result, iters)
  if c_result[1] != w_result[1]
    fail_check("benchmark checksum " + name, w_result[1], c_result[1])
  c_ns = c_result[0] * 1_000_000_000 / iters
  w_ns = w_result[0] * 1_000_000_000 / iters
  ratio = w_result[0] / c_result[0]
  << "RESULT|[name]|[c_ns]|[w_ns]|[ratio]|[c_result[1]]"

-> run_pair(bodies, iters, parity, name, emit = true)
  if name == "size"
    if parity == 0
      c_result = time_size_c(bodies, iters)
      w_result = time_size_w(bodies, iters)
    else
      w_result = time_size_w(bodies, iters)
      c_result = time_size_c(bodies, iters)
  elsif name == "read"
    if parity == 0
      c_result = time_read_c(bodies, iters)
      w_result = time_read_w(bodies, iters)
    else
      w_result = time_read_w(bodies, iters)
      c_result = time_read_c(bodies, iters)
  elsif name == "empty?"
    if parity == 0
      c_result = time_empty_c(bodies, iters)
      w_result = time_empty_w(bodies, iters)
    else
      w_result = time_empty_w(bodies, iters)
      c_result = time_empty_c(bodies, iters)
  elsif name == "each"
    if parity == 0
      c_result = time_each_c(bodies, iters)
      w_result = time_each_w(bodies, iters)
    else
      w_result = time_each_w(bodies, iters)
      c_result = time_each_c(bodies, iters)
  elsif name == "map"
    if parity == 0
      c_result = time_map_c(bodies, iters)
      w_result = time_map_w(bodies, iters)
    else
      w_result = time_map_w(bodies, iters)
      c_result = time_map_c(bodies, iters)
  elsif name == "select"
    if parity == 0
      c_result = time_select_c(bodies, iters)
      w_result = time_select_w(bodies, iters)
    else
      w_result = time_select_w(bodies, iters)
      c_result = time_select_c(bodies, iters)
  elsif name == "reject"
    if parity == 0
      c_result = time_reject_c(bodies, iters)
      w_result = time_reject_w(bodies, iters)
    else
      w_result = time_reject_w(bodies, iters)
      c_result = time_reject_c(bodies, iters)
  elsif name == "find"
    if parity == 0
      c_result = time_find_c(bodies, iters)
      w_result = time_find_w(bodies, iters)
    else
      w_result = time_find_w(bodies, iters)
      c_result = time_find_c(bodies, iters)
  elsif name == "any?"
    if parity == 0
      c_result = time_any_c(bodies, iters)
      w_result = time_any_w(bodies, iters)
    else
      w_result = time_any_w(bodies, iters)
      c_result = time_any_c(bodies, iters)
  elsif name == "all?"
    if parity == 0
      c_result = time_all_c(bodies, iters)
      w_result = time_all_w(bodies, iters)
    else
      w_result = time_all_w(bodies, iters)
      c_result = time_all_c(bodies, iters)
  elsif name == "none?"
    if parity == 0
      c_result = time_none_c(bodies, iters)
      w_result = time_none_w(bodies, iters)
    else
      w_result = time_none_w(bodies, iters)
      c_result = time_none_c(bodies, iters)
  elsif name == "reduce"
    if parity == 0
      c_result = time_reduce_c(bodies, iters)
      w_result = time_reduce_w(bodies, iters)
    else
      w_result = time_reduce_w(bodies, iters)
      c_result = time_reduce_c(bodies, iters)
  elsif name == "compact"
    if parity == 0
      c_result = time_compact_c(bodies, iters)
      w_result = time_compact_w(bodies, iters)
    else
      w_result = time_compact_w(bodies, iters)
      c_result = time_compact_c(bodies, iters)
  else
    if parity == 0
      c_result = time_dup_c(bodies, iters)
      w_result = time_dup_w(bodies, iters)
    else
      w_result = time_dup_w(bodies, iters)
      c_result = time_dup_c(bodies, iters)
  if emit
    report_result(name, c_result, w_result, iters)

-> run_bench(bodies, iters, parity)
  names = ["size", "read", "empty?", "each", "map", "select", "reject",
           "find", "any?", "all?", "none?", "reduce", "compact", "dup"]
  i = 0
  while i < names.size
    run_pair(bodies, WARMUP_ITERS, parity, names[i], false)
    run_pair(bodies, iters, parity, names[i])
    i += 1

args = argv()
mode = args.size > 0 ? args[0] : "check"
if mode == "check"
  run_correctness()
  exit(0)

iters = args.size > 1 ? args[1].to_i : DEFAULT_ITERS
parity = args.size > 2 ? args[2].to_i : 0
if iters <= 0 || !(parity in (0 1))
  << "usage: ast_body_ab bench POSITIVE_ITERS [0|1]"
  exit(2)
run_bench(build_corpus(), iters, parity)
