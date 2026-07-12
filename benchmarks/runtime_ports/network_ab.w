# Individual-function A/B benchmark for MAC and IPv6 methods moved from C to
# source-defined core classes. network_ref.c is linked only for this program.

use ../../core/ipv6
use ../../core/mac

IP_COUNT = 1024
IP_MASK = IP_COUNT - 1
MAC_COUNT = 256
IPV6_NAMES = ["ipv6.prefix", "ipv6.cidr?", "ipv6.with_prefix", "ipv6.byte",
              "ipv6.[]", "ipv6.bytes", "ipv6.network", "ipv6.include?",
              "ipv6.contains?", "ipv6.unspecified?", "ipv6.loopback?",
              "ipv6.multicast?", "ipv6.link_local?", "ipv6.unique_local?",
              "ipv6.private?", "ipv6.global?"]
MAC_NAMES = ["mac.byte", "mac.[]", "mac.bytes", "mac.multicast?",
             "mac.unicast?", "mac.local?", "mac.universal?", "mac.broadcast?"]

+ IPv6
  -> __c_prefix
    ccall("w_ref_ipv6_prefix", self)
  -> __c_cidr?
    ccall("w_ref_ipv6_cidr_p", self)
  -> __c_with_prefix(prefix = nil)
    ccall("w_ref_ipv6_with_prefix", self, prefix)
  -> __c_byte(index)
    ccall("w_ref_ipv6_byte", self, index)
  -> __c_index(index)
    ccall("w_ref_ipv6_byte", self, index)
  -> __c_bytes
    ccall("w_ref_ipv6_bytes", self)
  -> __c_network
    ccall("w_ref_ipv6_network", self)
  -> __c_include?(address)
    ccall("w_ref_ipv6_include", self, address)
  -> __c_contains?(address)
    ccall("w_ref_ipv6_include", self, address)
  -> __c_unspecified?
    ccall("w_ref_ipv6_unspecified_p", self)
  -> __c_loopback?
    ccall("w_ref_ipv6_loopback_p", self)
  -> __c_multicast?
    ccall("w_ref_ipv6_multicast_p", self)
  -> __c_link_local?
    ccall("w_ref_ipv6_link_local_p", self)
  -> __c_unique_local?
    ccall("w_ref_ipv6_unique_local_p", self)
  -> __c_private?
    ccall("w_ref_ipv6_unique_local_p", self)
  -> __c_global?
    ccall("w_ref_ipv6_global_p", self)

+ MAC
  -> __c_byte(index)
    ccall("w_ref_mac_byte", self, index)
  -> __c_index(index)
    ccall("w_ref_mac_byte", self, index)
  -> __c_bytes
    ccall("w_ref_mac_bytes", self)
  -> __c_multicast?
    ccall("w_ref_mac_multicast_p", self)
  -> __c_unicast?
    ccall("w_ref_mac_unicast_p", self)
  -> __c_local?
    ccall("w_ref_mac_local_p", self)
  -> __c_universal?
    ccall("w_ref_mac_universal_p", self)
  -> __c_broadcast?
    ccall("w_ref_mac_broadcast_p", self)

-> fail_check(name, case_index, got, want)
  << "FAIL [name] case=[case_index] got=[got] want=[want]"
  exit(1)

-> check(name, case_index, got, want)
  if got != want
    fail_check(name, case_index, got, want)

-> check_array(name, case_index, got, want)
  if got == nil
    fail_check(name + ".w.nil", case_index, got, want)
  if want == nil
    fail_check(name + ".c.nil", case_index, got, want)
  got_size = ccall("w_ref_array_size", got)
  want_size = ccall("w_ref_array_size", want)
  check(name + ".size", case_index, got_size, want_size)
  count = got_size
  # Exact representation parity: the former C bodies returned generic w64
  # Arrays (ebits=65), not ByteArray/u8 storage.
  check(name + ".w.ebits", case_index, ccall("w_ref_array_ebits", got), 65)
  check(name + ".c.ebits", case_index, ccall("w_ref_array_ebits", want), 65)
  i = 0
  while i < count
    check(name + ".item", case_index * count + i,
          ccall("w_ref_array_item", got, i), ccall("w_ref_array_item", want, i))
    i += 1

-> build_ipv6
  values = []
  i = 0
  while i < IP_COUNT
    p = i % 130
    prefix = p == 129 ? nil : p
    values.push(ccall("w_ref_ipv6_seed", i, prefix))
    i += 1
  values

-> build_macs
  values = []
  i = 0
  while i < MAC_COUNT
    values.push(ccall("w_ref_mac_seed", i, i * 17 + 3))
    i += 1
  values

-> run_correctness(ips, macs)
  checked = 0
  indexes = [-1, 0, 1, 7, 14, 15, 16,
             ~-1.0, ~-0.5, ~0.0, ~1.9, ~15.99, ~16.0,
             281_474_976_710_656, -281_474_976_710_656]
  i = 0
  while i < ips.size
    ip = ips[i]
    check("ipv6.prefix", i, ip.prefix, ip.__c_prefix)
    check("ipv6.cidr?", i, ip.cidr?, ip.__c_cidr?)
    check("ipv6.network", i, ip.network, ip.__c_network)
    check("ipv6.unspecified?", i, ip.unspecified?, ip.__c_unspecified?)
    check("ipv6.loopback?", i, ip.loopback?, ip.__c_loopback?)
    check("ipv6.multicast?", i, ip.multicast?, ip.__c_multicast?)
    check("ipv6.link_local?", i, ip.link_local?, ip.__c_link_local?)
    check("ipv6.unique_local?", i, ip.unique_local?, ip.__c_unique_local?)
    check("ipv6.private?", i, ip.private?, ip.__c_private?)
    check("ipv6.global?", i, ip.global?, ip.__c_global?)
    check_array("ipv6.bytes", i, ip.bytes, ip.__c_bytes)

    other = ips[(i * 17 + 11) & IP_MASK]
    check("ipv6.include?", i, ip.include?(other), ip.__c_include?(other))
    check("ipv6.contains?", i, ip.contains?(other), ip.__c_contains?(other))
    check("ipv6.include wrong type", i, ip.include?(macs[i & 255]), ip.__c_include?(macs[i & 255]))

    j = 0
    while j < indexes.size
      index = indexes[j]
      check("ipv6.byte", i * indexes.size + j, ip.byte(index), ip.__c_byte(index))
      check("ipv6.[]", i * indexes.size + j, ip[index], ip.__c_index(index))
      j += 1

    # Every prefix, including /128 and the no-prefix sentinel, appears in the
    # corpus. Reapply it to exercise the source storage boundary too.
    prefix = ip.__c_prefix
    check("ipv6.with_prefix", i, ip.with_prefix(prefix), ip.__c_with_prefix(prefix))
    checked += 47
    i += 1

  invalid = [129, 255, 1000, ~129.9]
  i = 0
  while i < invalid.size
    c_raised = false
    w_raised = false
    begin
      ips[0].__c_with_prefix(invalid[i])
    rescue error
      c_raised = true
    begin
      ips[0].with_prefix(invalid[i])
    rescue error
      w_raised = true
    check("ipv6.with_prefix invalid", i, w_raised, c_raised)
    check("ipv6.with_prefix invalid raises", i, w_raised, true)
    checked += 2
    i += 1

  i = 0
  while i < macs.size
    mac = macs[i]
    check("mac.byte", i, mac.byte(0), mac.__c_byte(0))
    check("mac.[]", i, mac[5], mac.__c_index(5))
    check("mac.byte low", i, mac.byte(-1), mac.__c_byte(-1))
    check("mac.byte high", i, mac.byte(6), mac.__c_byte(6))
    check_array("mac.bytes", i, mac.bytes, mac.__c_bytes)
    check("mac.multicast?", i, mac.multicast?, mac.__c_multicast?)
    check("mac.unicast?", i, mac.unicast?, mac.__c_unicast?)
    check("mac.local?", i, mac.local?, mac.__c_local?)
    check("mac.universal?", i, mac.universal?, mac.__c_universal?)
    check("mac.broadcast?", i, mac.broadcast?, mac.__c_broadcast?)
    checked += 16
    i += 1

  broadcast = ccall("w_ref_mac_broadcast")
  check("mac.broadcast all ff", 0, broadcast.broadcast?, broadcast.__c_broadcast?)
  check("mac.broadcast all ff true", 0, broadcast.broadcast?, true)
  checked += 2
  << "correctness: ok ([checked] grouped checks; exhaustive prefixes and MAC first octets)"

-> finish_timing(start, checksum)
  [clock() - start, checksum]

# The selector for each function runs before its timer starts. Cheap byte and
# predicate leaves are otherwise dominated by a branch ladder whose cost grows
# with the method's position in the table. Every iteration also contributes a
# result-derived checksum so release optimization cannot discard pure W loops.
-> time_ipv6_prefix(ips, use_w, iters)
  checksum = 0
  i = 0
  if use_w
    start = clock()
    while i < iters
      prefix = ips[i & IP_MASK].prefix
      checksum += prefix == nil ? 255 : prefix
      i += 1
    return finish_timing(start, checksum)
  start = clock()
  while i < iters
    prefix = ips[i & IP_MASK].__c_prefix
    checksum += prefix == nil ? 255 : prefix
    i += 1
  finish_timing(start, checksum)

-> time_ipv6_cidr(ips, use_w, iters)
  checksum = 0
  i = 0
  if use_w
    start = clock()
    while i < iters
      checksum += ips[i & IP_MASK].cidr? ? 1 : 0
      i += 1
    return finish_timing(start, checksum)
  start = clock()
  while i < iters
    checksum += ips[i & IP_MASK].__c_cidr? ? 1 : 0
    i += 1
  finish_timing(start, checksum)

-> time_ipv6_with_prefix(ips, use_w, iters)
  checksum = 0
  i = 0
  if use_w
    start = clock()
    while i < iters
      p = i % 130
      out = ips[i & IP_MASK].with_prefix(p == 129 ? nil : p)
      out_prefix = out.prefix
      checksum += out.byte(0) * 257 + (out_prefix == nil ? 255 : out_prefix)
      i += 1
    return finish_timing(start, checksum)
  start = clock()
  while i < iters
    p = i % 130
    out = ips[i & IP_MASK].__c_with_prefix(p == 129 ? nil : p)
    out_prefix = out.prefix
    checksum += out.byte(0) * 257 + (out_prefix == nil ? 255 : out_prefix)
    i += 1
  finish_timing(start, checksum)

-> time_ipv6_byte(ips, use_w, iters)
  checksum = 0
  i = 0
  if use_w
    start = clock()
    while i < iters
      checksum += ips[i & IP_MASK].byte(i & 15)
      i += 1
    return finish_timing(start, checksum)
  start = clock()
  while i < iters
    checksum += ips[i & IP_MASK].__c_byte(i & 15)
    i += 1
  finish_timing(start, checksum)

-> time_ipv6_index(ips, use_w, iters)
  checksum = 0
  i = 0
  if use_w
    start = clock()
    while i < iters
      checksum += ips[i & IP_MASK][i & 15]
      i += 1
    return finish_timing(start, checksum)
  start = clock()
  while i < iters
    checksum += ips[i & IP_MASK].__c_index(i & 15)
    i += 1
  finish_timing(start, checksum)

-> time_ipv6_bytes(ips, use_w, iters)
  checksum = 0
  i = 0
  if use_w
    start = clock()
    while i < iters
      out = ips[i & IP_MASK].bytes
      checksum += out.size * 257 + out[0]
      i += 1
    return finish_timing(start, checksum)
  start = clock()
  while i < iters
    out = ips[i & IP_MASK].__c_bytes
    checksum += out.size * 257 + out[0]
    i += 1
  finish_timing(start, checksum)

-> time_ipv6_network(ips, use_w, iters)
  checksum = 0
  i = 0
  if use_w
    start = clock()
    while i < iters
      out = ips[i & IP_MASK].network
      out_prefix = out.prefix
      checksum += out.byte(0) * 257 + (out_prefix == nil ? 255 : out_prefix)
      i += 1
    return finish_timing(start, checksum)
  start = clock()
  while i < iters
    out = ips[i & IP_MASK].__c_network
    out_prefix = out.prefix
    checksum += out.byte(0) * 257 + (out_prefix == nil ? 255 : out_prefix)
    i += 1
  finish_timing(start, checksum)

-> time_ipv6_include(ips, use_w, iters)
  checksum = 0
  i = 0
  if use_w
    start = clock()
    while i < iters
      value = ips[i & IP_MASK]
      other = ips[(i * 17 + 11) & IP_MASK]
      checksum += value.include?(other) ? 1 : 0
      i += 1
    return finish_timing(start, checksum)
  start = clock()
  while i < iters
    value = ips[i & IP_MASK]
    other = ips[(i * 17 + 11) & IP_MASK]
    checksum += value.__c_include?(other) ? 1 : 0
    i += 1
  finish_timing(start, checksum)

-> time_ipv6_contains(ips, use_w, iters)
  checksum = 0
  i = 0
  if use_w
    start = clock()
    while i < iters
      value = ips[i & IP_MASK]
      other = ips[(i * 17 + 11) & IP_MASK]
      checksum += value.contains?(other) ? 1 : 0
      i += 1
    return finish_timing(start, checksum)
  start = clock()
  while i < iters
    value = ips[i & IP_MASK]
    other = ips[(i * 17 + 11) & IP_MASK]
    checksum += value.__c_contains?(other) ? 1 : 0
    i += 1
  finish_timing(start, checksum)

-> time_ipv6_unspecified(ips, use_w, iters)
  checksum = 0
  i = 0
  if use_w
    start = clock()
    while i < iters
      checksum += ips[i & IP_MASK].unspecified? ? 1 : 0
      i += 1
    return finish_timing(start, checksum)
  start = clock()
  while i < iters
    checksum += ips[i & IP_MASK].__c_unspecified? ? 1 : 0
    i += 1
  finish_timing(start, checksum)

-> time_ipv6_loopback(ips, use_w, iters)
  checksum = 0
  i = 0
  if use_w
    start = clock()
    while i < iters
      checksum += ips[i & IP_MASK].loopback? ? 1 : 0
      i += 1
    return finish_timing(start, checksum)
  start = clock()
  while i < iters
    checksum += ips[i & IP_MASK].__c_loopback? ? 1 : 0
    i += 1
  finish_timing(start, checksum)

-> time_ipv6_multicast(ips, use_w, iters)
  checksum = 0
  i = 0
  if use_w
    start = clock()
    while i < iters
      checksum += ips[i & IP_MASK].multicast? ? 1 : 0
      i += 1
    return finish_timing(start, checksum)
  start = clock()
  while i < iters
    checksum += ips[i & IP_MASK].__c_multicast? ? 1 : 0
    i += 1
  finish_timing(start, checksum)

-> time_ipv6_link_local(ips, use_w, iters)
  checksum = 0
  i = 0
  if use_w
    start = clock()
    while i < iters
      checksum += ips[i & IP_MASK].link_local? ? 1 : 0
      i += 1
    return finish_timing(start, checksum)
  start = clock()
  while i < iters
    checksum += ips[i & IP_MASK].__c_link_local? ? 1 : 0
    i += 1
  finish_timing(start, checksum)

-> time_ipv6_unique_local(ips, use_w, iters)
  checksum = 0
  i = 0
  if use_w
    start = clock()
    while i < iters
      checksum += ips[i & IP_MASK].unique_local? ? 1 : 0
      i += 1
    return finish_timing(start, checksum)
  start = clock()
  while i < iters
    checksum += ips[i & IP_MASK].__c_unique_local? ? 1 : 0
    i += 1
  finish_timing(start, checksum)

-> time_ipv6_private(ips, use_w, iters)
  checksum = 0
  i = 0
  if use_w
    start = clock()
    while i < iters
      checksum += ips[i & IP_MASK].private? ? 1 : 0
      i += 1
    return finish_timing(start, checksum)
  start = clock()
  while i < iters
    checksum += ips[i & IP_MASK].__c_private? ? 1 : 0
    i += 1
  finish_timing(start, checksum)

-> time_ipv6_global(ips, use_w, iters)
  checksum = 0
  i = 0
  if use_w
    start = clock()
    while i < iters
      checksum += ips[i & IP_MASK].global? ? 1 : 0
      i += 1
    return finish_timing(start, checksum)
  start = clock()
  while i < iters
    checksum += ips[i & IP_MASK].__c_global? ? 1 : 0
    i += 1
  finish_timing(start, checksum)

-> time_ipv6(ips, code, use_w, iters)
  if code == 0
    return time_ipv6_prefix(ips, use_w, iters)
  if code == 1
    return time_ipv6_cidr(ips, use_w, iters)
  if code == 2
    return time_ipv6_with_prefix(ips, use_w, iters)
  if code == 3
    return time_ipv6_byte(ips, use_w, iters)
  if code == 4
    return time_ipv6_index(ips, use_w, iters)
  if code == 5
    return time_ipv6_bytes(ips, use_w, iters)
  if code == 6
    return time_ipv6_network(ips, use_w, iters)
  if code == 7
    return time_ipv6_include(ips, use_w, iters)
  if code == 8
    return time_ipv6_contains(ips, use_w, iters)
  if code == 9
    return time_ipv6_unspecified(ips, use_w, iters)
  if code == 10
    return time_ipv6_loopback(ips, use_w, iters)
  if code == 11
    return time_ipv6_multicast(ips, use_w, iters)
  if code == 12
    return time_ipv6_link_local(ips, use_w, iters)
  if code == 13
    return time_ipv6_unique_local(ips, use_w, iters)
  if code == 14
    return time_ipv6_private(ips, use_w, iters)
  time_ipv6_global(ips, use_w, iters)

-> time_mac_byte(macs, use_w, iters)
  checksum = 0
  i = 0
  if use_w
    start = clock()
    while i < iters
      checksum += macs[i & 255].byte(i % 6)
      i += 1
    return finish_timing(start, checksum)
  start = clock()
  while i < iters
    checksum += macs[i & 255].__c_byte(i % 6)
    i += 1
  finish_timing(start, checksum)

-> time_mac_index(macs, use_w, iters)
  checksum = 0
  i = 0
  if use_w
    start = clock()
    while i < iters
      checksum += macs[i & 255][i % 6]
      i += 1
    return finish_timing(start, checksum)
  start = clock()
  while i < iters
    checksum += macs[i & 255].__c_index(i % 6)
    i += 1
  finish_timing(start, checksum)

-> time_mac_bytes(macs, use_w, iters)
  checksum = 0
  i = 0
  if use_w
    start = clock()
    while i < iters
      out = macs[i & 255].bytes
      checksum += out.size * 257 + out[0]
      i += 1
    return finish_timing(start, checksum)
  start = clock()
  while i < iters
    out = macs[i & 255].__c_bytes
    checksum += out.size * 257 + out[0]
    i += 1
  finish_timing(start, checksum)

-> time_mac_multicast(macs, use_w, iters)
  checksum = 0
  i = 0
  if use_w
    start = clock()
    while i < iters
      checksum += macs[i & 255].multicast? ? 1 : 0
      i += 1
    return finish_timing(start, checksum)
  start = clock()
  while i < iters
    checksum += macs[i & 255].__c_multicast? ? 1 : 0
    i += 1
  finish_timing(start, checksum)

-> time_mac_unicast(macs, use_w, iters)
  checksum = 0
  i = 0
  if use_w
    start = clock()
    while i < iters
      checksum += macs[i & 255].unicast? ? 1 : 0
      i += 1
    return finish_timing(start, checksum)
  start = clock()
  while i < iters
    checksum += macs[i & 255].__c_unicast? ? 1 : 0
    i += 1
  finish_timing(start, checksum)

-> time_mac_local(macs, use_w, iters)
  checksum = 0
  i = 0
  if use_w
    start = clock()
    while i < iters
      checksum += macs[i & 255].local? ? 1 : 0
      i += 1
    return finish_timing(start, checksum)
  start = clock()
  while i < iters
    checksum += macs[i & 255].__c_local? ? 1 : 0
    i += 1
  finish_timing(start, checksum)

-> time_mac_universal(macs, use_w, iters)
  checksum = 0
  i = 0
  if use_w
    start = clock()
    while i < iters
      checksum += macs[i & 255].universal? ? 1 : 0
      i += 1
    return finish_timing(start, checksum)
  start = clock()
  while i < iters
    checksum += macs[i & 255].__c_universal? ? 1 : 0
    i += 1
  finish_timing(start, checksum)

-> time_mac_broadcast(macs, use_w, iters)
  checksum = 0
  i = 0
  if use_w
    start = clock()
    while i < iters
      checksum += macs[i & 255].broadcast? ? 1 : 0
      i += 1
    return finish_timing(start, checksum)
  start = clock()
  while i < iters
    checksum += macs[i & 255].__c_broadcast? ? 1 : 0
    i += 1
  finish_timing(start, checksum)

-> time_mac(macs, code, use_w, iters)
  if code == 0
    return time_mac_byte(macs, use_w, iters)
  if code == 1
    return time_mac_index(macs, use_w, iters)
  if code == 2
    return time_mac_bytes(macs, use_w, iters)
  if code == 3
    return time_mac_multicast(macs, use_w, iters)
  if code == 4
    return time_mac_unicast(macs, use_w, iters)
  if code == 5
    return time_mac_local(macs, use_w, iters)
  if code == 6
    return time_mac_universal(macs, use_w, iters)
  time_mac_broadcast(macs, use_w, iters)

-> emit_ipv6_result(ips, code, iters, parity)
  name = IPV6_NAMES[code]
  if parity == 0
    c = time_ipv6(ips, code, false, iters)
    w = time_ipv6(ips, code, true, iters)
  else
    w = time_ipv6(ips, code, true, iters)
    c = time_ipv6(ips, code, false, iters)
  check(name + ".checksum", code, w[1], c[1])
  c_ns = c[0] * 1_000_000_000 / iters
  w_ns = w[0] * 1_000_000_000 / iters
  << "RESULT|[name]|[c_ns]|[w_ns]|[w_ns / c_ns]"

-> emit_mac_result(macs, code, iters, parity)
  name = MAC_NAMES[code]
  if parity == 0
    c = time_mac(macs, code, false, iters)
    w = time_mac(macs, code, true, iters)
  else
    w = time_mac(macs, code, true, iters)
    c = time_mac(macs, code, false, iters)
  check(name + ".checksum", code, w[1], c[1])
  c_ns = c[0] * 1_000_000_000 / iters
  w_ns = w[0] * 1_000_000_000 / iters
  << "RESULT|[name]|[c_ns]|[w_ns]|[w_ns / c_ns]"

args = argv()
mode = args.size > 0 ? args[0] : "check"
ips = build_ipv6()
macs = build_macs()

if mode == "check"
  run_correctness(ips, macs)
else
  iters = args.size > 1 ? args[1].to_i : 100_000
  parity = args.size > 2 ? args[2].to_i : 0
  code = 0
  while code < IPV6_NAMES.size
    emit_ipv6_result(ips, code, iters, parity)
    code += 1
  code = 0
  while code < MAC_NAMES.size
    emit_mac_result(macs, code, iters, parity)
    code += 1
