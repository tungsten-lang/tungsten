# Function-level A/B benchmark for IPv4 methods moved from runtime.c into
# core/ipv4.w. The C side comes from ipv4_ref.c through TUNGSTEN_C_INCLUDES;
# compilation and corpus construction happen outside every timed interval.

use ../../core/ipv4

CORPUS_SIZE = 4096
CORPUS_MASK = CORPUS_SIZE - 1
DEFAULT_ITERS = 10_000_000
WARMUP_ITERS = 50_000

# Benchmark-only C-backed methods. The primary comparison calls these through
# the same packed IPv4 type-class dispatch as the public Tungsten methods, so
# the ratio isolates the method body rather than charging dispatch only to W.
+ IPv4
  -> __c_to_i
    ccall("w_ref_ipv4_to_i", self)

  -> __c_prefix
    ccall("w_ref_ipv4_prefix", self)

  -> __c_cidr?
    ccall("w_ref_ipv4_cidr_p", self)

  -> __c_with_prefix(prefix = nil)
    ccall("w_ref_ipv4_with_prefix", self, prefix)

  -> __c_octet(index)
    ccall("w_ref_ipv4_octet", self, index)

  -> __c_a
    ccall("w_ref_ipv4_octet", self, 0)

  -> __c_b
    ccall("w_ref_ipv4_octet", self, 1)

  -> __c_c
    ccall("w_ref_ipv4_octet", self, 2)

  -> __c_d
    ccall("w_ref_ipv4_octet", self, 3)

  -> __c_index(index)
    ccall("w_ref_ipv4_octet", self, index)

  -> __c_network
    ccall("w_ref_ipv4_network", self)

  -> __c_broadcast
    ccall("w_ref_ipv4_broadcast", self)

  -> __c_netmask
    ccall("w_ref_ipv4_netmask", self)

  -> __c_include?(address)
    ccall("w_ref_ipv4_in_cidr", address, self)

  -> __c_contains?(address)
    ccall("w_ref_ipv4_in_cidr", address, self)

  -> __c_private?
    ccall("w_ref_ipv4_private_p", self)

  -> __c_loopback?
    ccall("w_ref_ipv4_loopback_p", self)

  -> __c_link_local?
    ccall("w_ref_ipv4_link_local_p", self)

  -> __c_multicast?
    ccall("w_ref_ipv4_multicast_p", self)

  -> __c_unspecified?
    ccall("w_ref_ipv4_unspecified_p", self)

  -> __c_broadcast?
    ccall("w_ref_ipv4_broadcast_p", self)

  -> __c_reserved?
    ccall("w_ref_ipv4_reserved_p", self)

  -> __c_global?
    ccall("w_ref_ipv4_global_p", self)

-> fail_check(name, case_index, got, expected)
  << "FAIL [name] case=[case_index] got=[got] expected=[expected]"
  exit(1)

-> check_value(name, case_index, got, expected)
  if got != expected
    fail_check(name, case_index, got, expected)

-> make_ip(address, prefix)
  IPv4.of((address >> 24) & 0xFF,
          (address >> 16) & 0xFF,
          (address >> 8) & 0xFF,
          address & 0xFF,
          prefix)

# A deterministic corpus that keeps every special-address branch live while
# still including ordinary public addresses. Prefixes cycle through every
# bit/byte boundary plus nil (the packed no-prefix sentinel).
-> build_corpus
  prefixes = [nil]
  prefix = 0
  while prefix <= 32
    prefixes.push(prefix)
    prefix += 1
  values = []
  state = 0x6D2B79F5
  i = 0
  while i < CORPUS_SIZE
    state = (state * 1_664_525 + 1_013_904_223) & 0xFFFFFFFF
    low = state & 0x00FFFFFF
    kind = i & 0xF
    address = 0x08000000 | low
    if kind == 1
      address = 0x0A000000 | low
    elsif kind == 2
      address = 0xAC100000 | (low & 0x000FFFFF)
    elsif kind == 3
      address = 0xC0A80000 | (low & 0x0000FFFF)
    elsif kind == 4
      address = 0x7F000000 | low
    elsif kind == 5
      address = 0xA9FE0000 | (low & 0x0000FFFF)
    elsif kind == 6
      address = 0xE0000000 | (low & 0x0FFFFFFF)
    elsif kind == 7
      address = 0xF0000000 | (low & 0x0FFFFFFF)
    elsif kind == 8
      address = 0
    elsif kind == 9
      address = 0xFFFFFFFF
    elsif kind == 10
      address = 0x01000000 | low
    elsif kind == 11
      address = 0x64000000 | low
    elsif kind == 12
      address = 0x09FFFFFF
    elsif kind == 13
      address = 0x80000000 | low
    elsif kind == 14
      address = 0xA9FDFFFF
    elsif kind == 15
      address = 0xDFFFFFFF
    values.push(make_ip(address, prefixes[i % prefixes.size()]))
    i += 1
  values

-> run_correctness(values)
  # Build boxed Float values with `~`; the `f` suffix denotes a raw f32
  # scalar and does not exercise the old WValue ccall conversion boundary.
  # Large integer indexes exercise the BigInt conversion in the old C body.
  octet_indexes = [-1, 0, 1, 2, 3, 4,
                   ~-1.0, ~-0.5, ~0.0, ~1.0, ~1.75,
                   ~2.0, ~3.0, ~3.99, ~4.0, ~4.75,
                   281_474_976_710_656, -281_474_976_710_656]
  valid_prefixes = [nil, -100, -1, ~-1.75, 63, ~63.99]
  prefix = 0
  while prefix <= 32
    valid_prefixes.push(prefix)
    prefix += 1
  checked = 0
  i = 0
  while i < values.size()
    ip = values[i]
    check_value("to_i", i, ip.to_i, ip.__c_to_i)
    check_value("prefix", i, ip.prefix, ip.__c_prefix)
    check_value("cidr?", i, ip.cidr?, ip.__c_cidr?)
    j = 0
    while j < valid_prefixes.size()
      prefix_value = valid_prefixes[j]
      check_value("with_prefix", i * valid_prefixes.size() + j,
                  ip.with_prefix(prefix_value), ip.__c_with_prefix(prefix_value))
      j += 1
    j = 0
    while j < octet_indexes.size()
      index = octet_indexes[j]
      check_value("octet", i * octet_indexes.size() + j,
                  ip.octet(index), ip.__c_octet(index))
      check_value("[]", i * octet_indexes.size() + j,
                  ip[index], ip.__c_index(index))
      j += 1
    check_value("a", i, ip.a, ip.__c_a)
    check_value("b", i, ip.b, ip.__c_b)
    check_value("c", i, ip.c, ip.__c_c)
    check_value("d", i, ip.d, ip.__c_d)
    check_value("network", i, ip.network, ip.__c_network)
    check_value("broadcast", i, ip.broadcast, ip.__c_broadcast)
    check_value("netmask", i, ip.netmask, ip.__c_netmask)
    include_values = [ip,
                      values[(i + 1) & CORPUS_MASK],
                      values[(i + 17) & CORPUS_MASK],
                      nil, 0, "not an ip"]
    j = 0
    while j < include_values.size()
      candidate = include_values[j]
      check_value("include?", i * include_values.size() + j,
                  ip.include?(candidate), ip.__c_include?(candidate))
      check_value("contains?", i * include_values.size() + j,
                  ip.contains?(candidate), ip.__c_contains?(candidate))
      j += 1
    check_value("private?", i, ip.private?, ip.__c_private?)
    check_value("loopback?", i, ip.loopback?, ip.__c_loopback?)
    check_value("link_local?", i, ip.link_local?, ip.__c_link_local?)
    check_value("multicast?", i, ip.multicast?, ip.__c_multicast?)
    check_value("unspecified?", i, ip.unspecified?, ip.__c_unspecified?)
    check_value("broadcast?", i, ip.broadcast?, ip.__c_broadcast?)
    check_value("reserved?", i, ip.reserved?, ip.__c_reserved?)
    check_value("global?", i, ip.global?, ip.__c_global?)
    checked += 51 + valid_prefixes.size() + 3 + include_values.size() * 2
    i += 1

  # Invalid prefixes must raise on both sides. Do this once per invalid value;
  # exception setup is deliberately outside the performance measurements.
  invalid_prefixes = [33, 62, 64, 1000, ~33.9, ~64.1]
  i = 0
  while i < invalid_prefixes.size()
    prefix_value = invalid_prefixes[i]
    c_raised = false
    w_raised = false
    begin
      values[0].__c_with_prefix(prefix_value)
    rescue error
      c_raised = true
    begin
      values[0].with_prefix(prefix_value)
    rescue error
      w_raised = true
    check_value("with_prefix invalid raise", i, w_raised, c_raised)
    if !w_raised
      fail_check("with_prefix invalid raise", i, false, true)
    checked += 1
    i += 1

  << "correctness: ok ([checked] exact C/W comparisons)"

-> finish_timing(start_ns, checksum)
  [clock() - start_ns, checksum]

-> time_to_i_c(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].__c_to_i & 0xFF
    i += 1
  finish_timing(start_ns, checksum)

-> time_to_i_w(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].to_i & 0xFF
    i += 1
  finish_timing(start_ns, checksum)

-> time_prefix_c(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    value = values[i & CORPUS_MASK].__c_prefix
    checksum += value == nil ? 63 : value
    i += 1
  finish_timing(start_ns, checksum)

-> time_prefix_w(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    value = values[i & CORPUS_MASK].prefix
    checksum += value == nil ? 63 : value
    i += 1
  finish_timing(start_ns, checksum)

-> time_cidr_c(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].__c_cidr? ? 1 : 0
    i += 1
  finish_timing(start_ns, checksum)

-> time_cidr_w(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].cidr? ? 1 : 0
    i += 1
  finish_timing(start_ns, checksum)

-> time_with_prefix_c(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    result = values[i & CORPUS_MASK].__c_with_prefix(i & 31)
    checksum += result.d
    i += 1
  finish_timing(start_ns, checksum)

-> time_with_prefix_w(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    result = values[i & CORPUS_MASK].with_prefix(i & 31)
    checksum += result.d
    i += 1
  finish_timing(start_ns, checksum)

-> time_octet_c(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].__c_octet(i & 3)
    i += 1
  finish_timing(start_ns, checksum)

-> time_octet_w(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].octet(i & 3)
    i += 1
  finish_timing(start_ns, checksum)

-> time_a_c(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].__c_a
    i += 1
  finish_timing(start_ns, checksum)

-> time_a_w(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].a
    i += 1
  finish_timing(start_ns, checksum)

-> time_b_c(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].__c_b
    i += 1
  finish_timing(start_ns, checksum)

-> time_b_w(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].b
    i += 1
  finish_timing(start_ns, checksum)

-> time_c_field_c(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].__c_c
    i += 1
  finish_timing(start_ns, checksum)

-> time_c_field_w(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].c
    i += 1
  finish_timing(start_ns, checksum)

-> time_d_c(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].__c_d
    i += 1
  finish_timing(start_ns, checksum)

-> time_d_w(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].d
    i += 1
  finish_timing(start_ns, checksum)

-> time_index_c(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    ip = values[i & CORPUS_MASK]
    checksum += ip.__c_index(i & 3)
    i += 1
  finish_timing(start_ns, checksum)

-> time_index_w(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    ip = values[i & CORPUS_MASK]
    checksum += ip[i & 3]
    i += 1
  finish_timing(start_ns, checksum)

-> time_network_c(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].__c_network.d
    i += 1
  finish_timing(start_ns, checksum)

-> time_network_w(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].network.d
    i += 1
  finish_timing(start_ns, checksum)

-> time_broadcast_value_c(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].__c_broadcast.d
    i += 1
  finish_timing(start_ns, checksum)

-> time_broadcast_value_w(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].broadcast.d
    i += 1
  finish_timing(start_ns, checksum)

-> time_netmask_c(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].__c_netmask.to_i & 0xFFFF
    i += 1
  finish_timing(start_ns, checksum)

-> time_netmask_w(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].netmask.to_i & 0xFFFF
    i += 1
  finish_timing(start_ns, checksum)

-> time_include_c(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    cidr = values[i & CORPUS_MASK]
    candidate = values[(i + 17) & CORPUS_MASK]
    checksum += cidr.__c_include?(candidate) ? 1 : 0
    i += 1
  finish_timing(start_ns, checksum)

-> time_include_w(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    cidr = values[i & CORPUS_MASK]
    candidate = values[(i + 17) & CORPUS_MASK]
    checksum += cidr.include?(candidate) ? 1 : 0
    i += 1
  finish_timing(start_ns, checksum)

-> time_contains_c(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    cidr = values[i & CORPUS_MASK]
    candidate = values[(i + 17) & CORPUS_MASK]
    checksum += cidr.__c_contains?(candidate) ? 1 : 0
    i += 1
  finish_timing(start_ns, checksum)

-> time_contains_w(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    cidr = values[i & CORPUS_MASK]
    candidate = values[(i + 17) & CORPUS_MASK]
    checksum += cidr.contains?(candidate) ? 1 : 0
    i += 1
  finish_timing(start_ns, checksum)

-> time_private_c(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].__c_private? ? 1 : 0
    i += 1
  finish_timing(start_ns, checksum)

-> time_private_w(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].private? ? 1 : 0
    i += 1
  finish_timing(start_ns, checksum)

-> time_loopback_c(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].__c_loopback? ? 1 : 0
    i += 1
  finish_timing(start_ns, checksum)

-> time_loopback_w(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].loopback? ? 1 : 0
    i += 1
  finish_timing(start_ns, checksum)

-> time_link_local_c(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].__c_link_local? ? 1 : 0
    i += 1
  finish_timing(start_ns, checksum)

-> time_link_local_w(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].link_local? ? 1 : 0
    i += 1
  finish_timing(start_ns, checksum)

-> time_multicast_c(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].__c_multicast? ? 1 : 0
    i += 1
  finish_timing(start_ns, checksum)

-> time_multicast_w(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].multicast? ? 1 : 0
    i += 1
  finish_timing(start_ns, checksum)

-> time_unspecified_c(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].__c_unspecified? ? 1 : 0
    i += 1
  finish_timing(start_ns, checksum)

-> time_unspecified_w(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].unspecified? ? 1 : 0
    i += 1
  finish_timing(start_ns, checksum)

-> time_broadcast_c(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].__c_broadcast? ? 1 : 0
    i += 1
  finish_timing(start_ns, checksum)

-> time_broadcast_w(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].broadcast? ? 1 : 0
    i += 1
  finish_timing(start_ns, checksum)

-> time_reserved_c(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].__c_reserved? ? 1 : 0
    i += 1
  finish_timing(start_ns, checksum)

-> time_reserved_w(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].reserved? ? 1 : 0
    i += 1
  finish_timing(start_ns, checksum)

-> time_global_c(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].__c_global? ? 1 : 0
    i += 1
  finish_timing(start_ns, checksum)

-> time_global_w(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].global? ? 1 : 0
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

-> run_bench(values, iters, parity)
  # Warm the exact loop/method call sites before measuring.
  time_to_i_c(values, WARMUP_ITERS)
  time_to_i_w(values, WARMUP_ITERS)
  time_prefix_c(values, WARMUP_ITERS)
  time_prefix_w(values, WARMUP_ITERS)
  time_cidr_c(values, WARMUP_ITERS)
  time_cidr_w(values, WARMUP_ITERS)
  time_with_prefix_c(values, WARMUP_ITERS)
  time_with_prefix_w(values, WARMUP_ITERS)
  time_octet_c(values, WARMUP_ITERS)
  time_octet_w(values, WARMUP_ITERS)
  time_a_c(values, WARMUP_ITERS)
  time_a_w(values, WARMUP_ITERS)
  time_b_c(values, WARMUP_ITERS)
  time_b_w(values, WARMUP_ITERS)
  time_c_field_c(values, WARMUP_ITERS)
  time_c_field_w(values, WARMUP_ITERS)
  time_d_c(values, WARMUP_ITERS)
  time_d_w(values, WARMUP_ITERS)
  time_index_c(values, WARMUP_ITERS)
  time_index_w(values, WARMUP_ITERS)
  time_network_c(values, WARMUP_ITERS)
  time_network_w(values, WARMUP_ITERS)
  time_broadcast_value_c(values, WARMUP_ITERS)
  time_broadcast_value_w(values, WARMUP_ITERS)
  time_netmask_c(values, WARMUP_ITERS)
  time_netmask_w(values, WARMUP_ITERS)
  time_include_c(values, WARMUP_ITERS)
  time_include_w(values, WARMUP_ITERS)
  time_contains_c(values, WARMUP_ITERS)
  time_contains_w(values, WARMUP_ITERS)
  time_private_c(values, WARMUP_ITERS)
  time_private_w(values, WARMUP_ITERS)
  time_loopback_c(values, WARMUP_ITERS)
  time_loopback_w(values, WARMUP_ITERS)
  time_link_local_c(values, WARMUP_ITERS)
  time_link_local_w(values, WARMUP_ITERS)
  time_multicast_c(values, WARMUP_ITERS)
  time_multicast_w(values, WARMUP_ITERS)
  time_unspecified_c(values, WARMUP_ITERS)
  time_unspecified_w(values, WARMUP_ITERS)
  time_broadcast_c(values, WARMUP_ITERS)
  time_broadcast_w(values, WARMUP_ITERS)
  time_reserved_c(values, WARMUP_ITERS)
  time_reserved_w(values, WARMUP_ITERS)
  time_global_c(values, WARMUP_ITERS)
  time_global_w(values, WARMUP_ITERS)

  # Every process sample passes parity 0 or 1. Reverse each adjacent pair on
  # odd samples so thermal/order effects do not consistently favor C or W.
  if parity == 0
    c_result = time_to_i_c(values, iters)
    w_result = time_to_i_w(values, iters)
  else
    w_result = time_to_i_w(values, iters)
    c_result = time_to_i_c(values, iters)
  report_result("to_i", c_result, w_result, iters)

  if parity == 0
    c_result = time_prefix_c(values, iters)
    w_result = time_prefix_w(values, iters)
  else
    w_result = time_prefix_w(values, iters)
    c_result = time_prefix_c(values, iters)
  report_result("prefix", c_result, w_result, iters)

  if parity == 0
    c_result = time_cidr_c(values, iters)
    w_result = time_cidr_w(values, iters)
  else
    w_result = time_cidr_w(values, iters)
    c_result = time_cidr_c(values, iters)
  report_result("cidr?", c_result, w_result, iters)

  if parity == 0
    c_result = time_with_prefix_c(values, iters)
    w_result = time_with_prefix_w(values, iters)
  else
    w_result = time_with_prefix_w(values, iters)
    c_result = time_with_prefix_c(values, iters)
  report_result("with_prefix", c_result, w_result, iters)

  if parity == 0
    c_result = time_octet_c(values, iters)
    w_result = time_octet_w(values, iters)
  else
    w_result = time_octet_w(values, iters)
    c_result = time_octet_c(values, iters)
  report_result("octet", c_result, w_result, iters)

  if parity == 0
    c_result = time_a_c(values, iters)
    w_result = time_a_w(values, iters)
  else
    w_result = time_a_w(values, iters)
    c_result = time_a_c(values, iters)
  report_result("a", c_result, w_result, iters)

  if parity == 0
    c_result = time_b_c(values, iters)
    w_result = time_b_w(values, iters)
  else
    w_result = time_b_w(values, iters)
    c_result = time_b_c(values, iters)
  report_result("b", c_result, w_result, iters)

  if parity == 0
    c_result = time_c_field_c(values, iters)
    w_result = time_c_field_w(values, iters)
  else
    w_result = time_c_field_w(values, iters)
    c_result = time_c_field_c(values, iters)
  report_result("c", c_result, w_result, iters)

  if parity == 0
    c_result = time_d_c(values, iters)
    w_result = time_d_w(values, iters)
  else
    w_result = time_d_w(values, iters)
    c_result = time_d_c(values, iters)
  report_result("d", c_result, w_result, iters)

  if parity == 0
    c_result = time_index_c(values, iters)
    w_result = time_index_w(values, iters)
  else
    w_result = time_index_w(values, iters)
    c_result = time_index_c(values, iters)
  report_result("[]", c_result, w_result, iters)

  if parity == 0
    c_result = time_network_c(values, iters)
    w_result = time_network_w(values, iters)
  else
    w_result = time_network_w(values, iters)
    c_result = time_network_c(values, iters)
  report_result("network", c_result, w_result, iters)

  if parity == 0
    c_result = time_broadcast_value_c(values, iters)
    w_result = time_broadcast_value_w(values, iters)
  else
    w_result = time_broadcast_value_w(values, iters)
    c_result = time_broadcast_value_c(values, iters)
  report_result("broadcast", c_result, w_result, iters)

  if parity == 0
    c_result = time_netmask_c(values, iters)
    w_result = time_netmask_w(values, iters)
  else
    w_result = time_netmask_w(values, iters)
    c_result = time_netmask_c(values, iters)
  report_result("netmask", c_result, w_result, iters)

  if parity == 0
    c_result = time_include_c(values, iters)
    w_result = time_include_w(values, iters)
  else
    w_result = time_include_w(values, iters)
    c_result = time_include_c(values, iters)
  report_result("include?", c_result, w_result, iters)

  if parity == 0
    c_result = time_contains_c(values, iters)
    w_result = time_contains_w(values, iters)
  else
    w_result = time_contains_w(values, iters)
    c_result = time_contains_c(values, iters)
  report_result("contains?", c_result, w_result, iters)

  if parity == 0
    c_result = time_private_c(values, iters)
    w_result = time_private_w(values, iters)
  else
    w_result = time_private_w(values, iters)
    c_result = time_private_c(values, iters)
  report_result("private?", c_result, w_result, iters)

  if parity == 0
    c_result = time_loopback_c(values, iters)
    w_result = time_loopback_w(values, iters)
  else
    w_result = time_loopback_w(values, iters)
    c_result = time_loopback_c(values, iters)
  report_result("loopback?", c_result, w_result, iters)

  if parity == 0
    c_result = time_link_local_c(values, iters)
    w_result = time_link_local_w(values, iters)
  else
    w_result = time_link_local_w(values, iters)
    c_result = time_link_local_c(values, iters)
  report_result("link_local?", c_result, w_result, iters)

  if parity == 0
    c_result = time_multicast_c(values, iters)
    w_result = time_multicast_w(values, iters)
  else
    w_result = time_multicast_w(values, iters)
    c_result = time_multicast_c(values, iters)
  report_result("multicast?", c_result, w_result, iters)

  if parity == 0
    c_result = time_unspecified_c(values, iters)
    w_result = time_unspecified_w(values, iters)
  else
    w_result = time_unspecified_w(values, iters)
    c_result = time_unspecified_c(values, iters)
  report_result("unspecified?", c_result, w_result, iters)

  if parity == 0
    c_result = time_broadcast_c(values, iters)
    w_result = time_broadcast_w(values, iters)
  else
    w_result = time_broadcast_w(values, iters)
    c_result = time_broadcast_c(values, iters)
  report_result("broadcast?", c_result, w_result, iters)

  if parity == 0
    c_result = time_reserved_c(values, iters)
    w_result = time_reserved_w(values, iters)
  else
    w_result = time_reserved_w(values, iters)
    c_result = time_reserved_c(values, iters)
  report_result("reserved?", c_result, w_result, iters)

  if parity == 0
    c_result = time_global_c(values, iters)
    w_result = time_global_w(values, iters)
  else
    w_result = time_global_w(values, iters)
    c_result = time_global_c(values, iters)
  report_result("global?", c_result, w_result, iters)

args = argv()
mode = args.size() > 0 ? args[0] : "bench"
values = build_corpus()

if mode == "check"
  run_correctness(values)
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

run_bench(values, iters, parity)
