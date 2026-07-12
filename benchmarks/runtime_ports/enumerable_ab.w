# Function-level A/B benchmark for collection combinators moved from the
# runtime IC tables into Enumerable. The benchmark-only C methods call exact
# copies of the removed loops from enumerable_ref.c through the same receiver
# type-class dispatch as the public Tungsten methods.

use ../../core/array
use ../../core/hash

DEFAULT_ITERS = 10_000
WARMUP_ITERS = 200

+ Array
  -> __c_map(block)
    ccall("w_ref_array_map", self, block)

  -> __c_select(block)
    ccall("w_ref_array_select", self, block)

  -> __c_reject(block)
    ccall("w_ref_array_reject", self, block)

  -> __c_find(block)
    ccall("w_ref_array_find", self, block)

  -> __c_detect(block)
    ccall("w_ref_array_find", self, block)

  -> __c_reduce(initial, block)
    ccall("w_ref_array_reduce", self, initial, block)

  -> __c_each_with_index(block)
    ccall("w_ref_array_each_with_index", self, block)

  -> __c_group_by(block)
    ccall("w_ref_array_group_by", self, block)

  -> __c_partition(block)
    ccall("w_ref_array_partition", self, block)

  -> __c_tally
    ccall("w_ref_array_tally", self)

  -> __c_flat_map(block)
    ccall("w_ref_array_flat_map", self, block)

+ Hash
  -> __c_map(block)
    ccall("w_ref_hash_map", self, block)

-> fail_check(name, detail)
  << "FAIL [name]: [detail]"
  exit(1)

-> check_value(name, got, expected)
  if got != expected
    fail_check(name, "got=[got] expected=[expected]")

-> check_array(name, got, expected)
  check_value("[name] size", got.size, expected.size)
  i = 0
  while i < got.size
    check_value("[name] item [i]", got[i], expected[i])
    i++

-> build_typed_values
  values = i16[64]
  i = 0
  while i < 64
    values[i] = i - 32
    i++
  values

-> check_array_suite(label, values)
  mapper = -> (value)
    value * 3 + 1
  predicate = -> (value)
    (value & 3) == 1
  reducer = -> (accumulator, value)
    accumulator + value * value
  grouper = -> (value)
    value & 3
  expander = -> (value)
    [value, value + 1]

  check_array("[label] map", values.map(mapper), values.__c_map(mapper))
  check_array("[label] select", values.select(predicate), values.__c_select(predicate))
  check_array("[label] reject", values.reject(predicate), values.__c_reject(predicate))
  check_value("[label] find", values.find(predicate), values.__c_find(predicate))
  check_value("[label] detect", values.detect(predicate), values.__c_detect(predicate))
  check_value("[label] reduce", values.reduce(17, reducer), values.__c_reduce(17, reducer))

  c_index_total = [0]
  w_index_total = [0]
  c_indexer = -> (value, index)
    c_index_total[0] = c_index_total[0] + value * (index + 1)
  w_indexer = -> (value, index)
    w_index_total[0] = w_index_total[0] + value * (index + 1)
  c_each_result = values.__c_each_with_index(c_indexer)
  w_each_result = values.each_with_index(w_indexer)
  check_value("[label] each_with_index receiver", w_each_result, c_each_result)
  check_value("[label] each_with_index effects", w_index_total[0], c_index_total[0])

  c_groups = values.__c_group_by(grouper)
  w_groups = values.group_by(grouper)
  check_value("[label] group_by size", w_groups.size, c_groups.size)
  c_groups.each -> (key, expected)
    check_array("[label] group_by [key]", w_groups[key], expected)

  c_partition = values.__c_partition(predicate)
  w_partition = values.partition(predicate)
  check_array("[label] partition yes", w_partition[0], c_partition[0])
  check_array("[label] partition no", w_partition[1], c_partition[1])

  c_tally = values.__c_tally
  w_tally = values.tally
  values.each -> (value)
    check_value("[label] tally [value]", w_tally[value], c_tally[value])

  check_array("[label] flat_map", values.flat_map(expander), values.__c_flat_map(expander))
  scalar = -> (value)
    value + 9
  check_array("[label] flat_map scalar", values.flat_map(scalar), values.__c_flat_map(scalar))

-> run_correctness(typed_values, hash)
  check_array_suite("plain", [-3, -1, 0, 1, 1, 4, 9])
  check_array_suite("typed-i16", typed_values)
  check_array_suite("empty", [])

  # A side-effect counter proves the W find/detect bodies retain the C loop's
  # early return rather than evaluating the rest of the receiver.
  c_seen = [0]
  w_seen = [0]
  c_early = -> (value)
    c_seen[0] = c_seen[0] + 1
    value == 0
  w_early = -> (value)
    w_seen[0] = w_seen[0] + 1
    value == 0
  check_value("find early value", typed_values.find(w_early), typed_values.__c_find(c_early))
  check_value("find early calls", w_seen[0], c_seen[0])

  hash_mapper = -> (key, value)
    key * 1000 + value
  check_array("hash map pair yield", hash.map(hash_mapper), hash.__c_map(hash_mapper))
  check_array("empty hash map", ({}).map(hash_mapper), ({}).__c_map(hash_mapper))

  << "correctness: ok (plain, i16 typed, empty, pair-yield, and early-return cases)"

-> finish_timing(start_ns, checksum)
  [clock() - start_ns, checksum]

-> time_operation(operation, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += operation.call()
    i++
  finish_timing(start_ns, checksum)

-> time_each_with_index(values, use_w, iters)
  c_total = [0]
  w_total = [0]
  c_block = -> (value, index)
    c_total[0] = c_total[0] + value * (index + 1)
  w_block = -> (value, index)
    w_total[0] = w_total[0] + value * (index + 1)
  checksum = 0
  i = 0
  if use_w
    start_ns = clock()
    while i < iters
      w_total[0] = 0
      values.each_with_index(w_block)
      checksum += w_total[0]
      i++
    return finish_timing(start_ns, checksum)
  start_ns = clock()
  while i < iters
    c_total[0] = 0
    values.__c_each_with_index(c_block)
    checksum += c_total[0]
    i++
  finish_timing(start_ns, checksum)

-> report_result(name, c_result, w_result, iters)
  if c_result[1] != w_result[1]
    fail_check("benchmark checksum [name]", "C=[c_result[1]] W=[w_result[1]]")
  c_ns = c_result[0] * 1_000_000_000 / iters
  w_ns = w_result[0] * 1_000_000_000 / iters
  ratio = w_result[0] / c_result[0]
  << "RESULT|[name]|[c_ns]|[w_ns]|[ratio]|[c_result[1]]"

-> run_each_with_index_pair(values, iters, parity, emit)
  if parity == 0
    c_result = time_each_with_index(values, false, iters)
    w_result = time_each_with_index(values, true, iters)
  else
    w_result = time_each_with_index(values, true, iters)
    c_result = time_each_with_index(values, false, iters)
  if emit
    report_result("each_with_index", c_result, w_result, iters)

-> run_pair(name, values, hash, iters, parity, emit = true)
  if name == "array.map"
    block = -> (value) value * 3 + 1
    operations = [-> () values.__c_map(block).size,
                  -> () values.map(block).size]
  elsif name == "hash.map"
    block = -> (key, value) key * 1000 + value
    operations = [-> () hash.__c_map(block).size,
                  -> () hash.map(block).size]
  elsif name == "select"
    block = -> (value) (value & 3) == 1
    operations = [-> () values.__c_select(block).size,
                  -> () values.select(block).size]
  elsif name == "reject"
    block = -> (value) (value & 3) == 1
    operations = [-> () values.__c_reject(block).size,
                  -> () values.reject(block).size]
  elsif name == "find"
    block = -> (value) value == 0
    operations = [-> () values.__c_find(block),
                  -> () values.find(block)]
  elsif name == "detect"
    block = -> (value) value == 0
    operations = [-> () values.__c_detect(block),
                  -> () values.detect(block)]
  elsif name == "reduce"
    block = -> (accumulator, value) accumulator + value * value
    operations = [-> () values.__c_reduce(17, block),
                  -> () values.reduce(17, block)]
  elsif name == "group_by"
    block = -> (value) value & 3
    operations = [-> () values.__c_group_by(block).size,
                  -> () values.group_by(block).size]
  elsif name == "partition"
    block = -> (value) (value & 3) == 1
    operations = [-> () values.__c_partition(block)[0].size,
                  -> () values.partition(block)[0].size]
  elsif name == "tally"
    operations = [-> () values.__c_tally.size,
                  -> () values.tally.size]
  else
    block = -> (value) [value, value + 1]
    operations = [-> () values.__c_flat_map(block).size,
                  -> () values.flat_map(block).size]

  if parity == 0
    c_result = time_operation(operations[0], iters)
    w_result = time_operation(operations[1], iters)
  else
    w_result = time_operation(operations[1], iters)
    c_result = time_operation(operations[0], iters)
  if emit
    report_result(name, c_result, w_result, iters)

-> run_bench(values, hash, iters, parity)
  names = ["array.map", "hash.map", "select", "reject", "find", "detect",
           "reduce", "group_by", "partition", "tally", "flat_map"]
  i = 0
  while i < names.size()
    run_pair(names[i], values, hash, WARMUP_ITERS, parity, false)
    i++
  run_each_with_index_pair(values, WARMUP_ITERS, parity, false)
  i = 0
  while i < names.size()
    run_pair(names[i], values, hash, iters, parity)
    i++
  run_each_with_index_pair(values, iters, parity, true)

typed_values = build_typed_values()
hash = {}
i = 0
while i < 64
  hash[i] = (i * 17 + 3) & 255
  i++

args = argv()
if args.size() > 0 && args[0] == "check"
  run_correctness(typed_values, hash)
elsif args.size() > 0 && args[0] == "bench"
  iters = DEFAULT_ITERS
  parity = 0
  if args.size() > 1
    iters = args[1].to_i
  if args.size() > 2
    parity = args[2].to_i & 1
  run_bench(typed_values, hash, iters, parity)
else
  << "usage: enumerable-ab check | bench [iters] [parity]"
  exit(2)
