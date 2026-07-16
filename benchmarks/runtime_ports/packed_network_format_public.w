# True-public relaxed-gate fixture for IPv4/IPv6/MAC to_s.
#
# Deliberately no `use core/...`: literals, class references, and exact native
# constructors must provide the same autoload surface a real program sees.
# Baseline to_s calls resolve to w_ic_value_to_s; candidate to_s calls resolve
# to the classes' dormant direct-format Tungsten wrappers. Inspect calls below
# are correctness controls and remain native in both roots.

CORPUS_SIZE = 16
CORPUS_MASK = CORPUS_SIZE - 1
DEFAULT_ITERS = 2_000_000
DEFAULT_WARMUP = 100_000

-> fail_check(kind, index, path, got, expected)
  << "FAIL [kind] case=[index] [path] got=[got] expected=[expected]"
  exit(1)

-> check(kind, index, path, got, expected)
  if got != expected
    fail_check(kind, index, path, got, expected)

-> fingerprint(value)
  ccall("w_pnf_network_fingerprint", value)

-> check_ipv4
  values = [0.0.0.0,
            255.255.255.255,
            127.0.0.1,
            192.0.2.1,
            IPv4.parse("203.0.113.9"),
            IPv4.of(1, 2, 3, 4),
            ccall("w_pnf_ipv4_case", 13, nil)]
  expected = ["0.0.0.0", "255.255.255.255", "127.0.0.1",
              "192.0.2.1", "203.0.113.9", "1.2.3.4",
              ccall("w_to_s", values[6])]
  i = 0
  while i < values.size
    value = values[i]
    before_bits = wvalue_bits(value)
    before_fingerprint = fingerprint(value)
    check("IPv4#to_s", i, "exact", value.to_s, expected[i])
    check("IPv4#inspect", i, "exact", value.inspect, expected[i])
    check("IPv4", i, "direct formatter parity", value.to_s,
          ccall("w_to_s", value))
    check("IPv4", i, "receiver bits stable", wvalue_bits(value), before_bits)
    check("IPv4", i, "receiver fields stable", fingerprint(value), before_fingerprint)
    i += 1

  # Exhaust every valid prefix and the packed no-prefix sentinel.
  prefix = 0
  while prefix <= 32
    value = IPv4.of(203, 0, 113, 9, prefix)
    expected_text = "203.0.113.9/" + prefix.to_s()
    before_bits = wvalue_bits(value)
    check("IPv4#to_s", prefix, "all prefixes", value.to_s, expected_text)
    check("IPv4#inspect", prefix, "all prefixes", value.inspect, expected_text)
    check("IPv4", prefix, "prefixed receiver stable", wvalue_bits(value), before_bits)
    prefix += 1

  value = IPv4.of(198, 51, 100, 7)
  check("IPv4#to_s", 100, "one surplus", value.to_s(17), "198.51.100.7")
  check("IPv4#to_s", 101, "three surplus", value.to_s(1, 2, 3), "198.51.100.7")
  check("IPv4#inspect", 102, "one surplus", value.inspect(17), "198.51.100.7")
  check("IPv4#inspect", 103, "three surplus", value.inspect(1, 2, 3), "198.51.100.7")

-> check_ipv6
  literal = 2001:db8::1
  values = [IPv6.parse("::"),
            IPv6.parse("::1"),
            literal,
            IPv6.parse("FFFF:FFFF:FFFF:FFFF:FFFF:FFFF:FFFF:FFFF"),
            IPv6.parse("::ffff:192.0.2.128"),
            ccall("w_ipv6_storage_from_words", 0x20010DB8, 0, 0, 1, 255),
            ccall("w_pnf_ipv6_case", 14, nil)]
  expected = ["0:0:0:0:0:0:0:0",
              "0:0:0:0:0:0:0:1",
              "2001:db8:0:0:0:0:0:1",
              "ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff",
              "0:0:0:0:0:ffff:c000:280",
              "2001:db8:0:0:0:0:0:1",
              ccall("w_to_s", values[6])]
  i = 0
  while i < values.size
    value = values[i]
    before_bits = wvalue_bits(value)
    before_fingerprint = fingerprint(value)
    check("IPv6#to_s", i, "exact", value.to_s, expected[i])
    check("IPv6#inspect", i, "exact", value.inspect, expected[i])
    check("IPv6", i, "direct formatter parity", value.inspect,
          ccall("w_to_s", value))
    check("IPv6", i, "receiver bits stable", wvalue_bits(value), before_bits)
    check("IPv6", i, "receiver fields stable", fingerprint(value), before_fingerprint)
    i += 1

  # Exhaust /0 through /128 plus the separate no-prefix values above.
  base = IPv6.parse("2001:db8:abcd:1234:5678:9abc:def0:1357")
  base_text = "2001:db8:abcd:1234:5678:9abc:def0:1357"
  prefix = 0
  while prefix <= 128
    value = base.with_prefix(prefix)
    expected_text = base_text + "/" + prefix.to_s()
    before_bits = wvalue_bits(value)
    before_fingerprint = fingerprint(value)
    check("IPv6#to_s", prefix, "all prefixes", value.to_s, expected_text)
    check("IPv6#inspect", prefix, "all prefixes", value.inspect, expected_text)
    check("IPv6", prefix, "prefixed receiver bits stable", wvalue_bits(value), before_bits)
    check("IPv6", prefix, "prefixed receiver fields stable", fingerprint(value), before_fingerprint)
    prefix += 1

  value = IPv6.parse("2001:db8::7/64")
  expected_text = "2001:db8:0:0:0:0:0:7/64"
  check("IPv6#to_s", 200, "one surplus", value.to_s(17), expected_text)
  check("IPv6#to_s", 201, "three surplus", value.to_s(1, 2, 3), expected_text)
  check("IPv6#inspect", 202, "one surplus", value.inspect(17), expected_text)
  check("IPv6#inspect", 203, "three surplus", value.inspect(1, 2, 3), expected_text)

-> check_mac
  values = [MAC.parse("00:11:22:33:44:55"),
            MAC.parse("02-AB-CD-EF-01-02"),
            MAC.parse("0011.2233.4455"),
            MAC.parse("ff:ff:ff:ff:ff:ff"),
            ccall("w_mac_parse", "01:00:5e:00:00:01"),
            ccall("w_pnf_mac_case", 14)]
  expected = ["00:11:22:33:44:55",
              "02:ab:cd:ef:01:02",
              "00:11:22:33:44:55",
              "ff:ff:ff:ff:ff:ff",
              "01:00:5e:00:00:01",
              ccall("w_to_s", values[5])]
  i = 0
  while i < values.size
    value = values[i]
    before_bits = wvalue_bits(value)
    before_fingerprint = fingerprint(value)
    check("MAC#to_s", i, "exact", value.to_s, expected[i])
    check("MAC#inspect", i, "exact", value.inspect, expected[i])
    check("MAC", i, "direct formatter parity", value.to_s,
          ccall("w_to_s", value))
    check("MAC", i, "receiver bits stable", wvalue_bits(value), before_bits)
    check("MAC", i, "receiver fields stable", fingerprint(value), before_fingerprint)
    i += 1

  value = MAC.parse("de:ad:be:ef:00:01")
  check("MAC#to_s", 100, "one surplus", value.to_s(17), "de:ad:be:ef:00:01")
  check("MAC#to_s", 101, "three surplus", value.to_s(1, 2, 3), "de:ad:be:ef:00:01")
  check("MAC#inspect", 102, "one surplus", value.inspect(17), "de:ad:be:ef:00:01")
  check("MAC#inspect", 103, "three surplus", value.inspect(1, 2, 3), "de:ad:be:ef:00:01")

-> run_check
  check_ipv4()
  check_ipv6()
  check_mac()
  << "PASS packed network formatters: exact outputs, 33 IPv4 prefixes, 129 IPv6 prefixes, packed/heap storage, receiver stability, surplus args"

-> build_values(kind)
  values = []
  i = 0
  if kind in ("ipv4.to_s.plain" "ipv4.to_s.cidr")
    cidr = kind == "ipv4.to_s.cidr"
    while i < CORPUS_SIZE
      prefix = cidr ? ((i * 7) % 33) : nil
      values.push(ccall("w_pnf_ipv4_case", i, prefix))
      i += 1
    return values
  if kind in ("ipv6.to_s.plain" "ipv6.to_s.cidr")
    cidr = kind == "ipv6.to_s.cidr"
    while i < CORPUS_SIZE
      prefix = cidr ? ((i * 11) % 129) : nil
      values.push(ccall("w_pnf_ipv6_case", i, prefix))
      i += 1
    return values
  if kind == "mac.to_s"
    while i < CORPUS_SIZE
      values.push(ccall("w_pnf_mac_case", i))
      i += 1
    return values
  << "unknown packed-network formatter stratum: [kind]"
  exit(2)

-> expected_signatures(values)
  expected = []
  i = 0
  while i < CORPUS_SIZE
    expected.push(ccall("w_pnf_string_signature", ccall("w_to_s", values[i])))
    i += 1
  expected

-> time_ipv4_to_s(values, expected, iters, run_id)
  checksum = 0
  i = 0
  start_ns = ccall("w_pnf_thread_cpu_ns")
  while i < iters
    index = i & CORPUS_MASK
    checksum += ccall("w_pnf_string_signature", values[index].to_s) == expected[index] ? 1 : 0
    i += 1
  [ccall("w_pnf_thread_cpu_ns") - start_ns, checksum]

-> time_ipv6_to_s(values, expected, iters, run_id)
  checksum = 0
  i = 0
  start_ns = ccall("w_pnf_thread_cpu_ns")
  while i < iters
    index = i & CORPUS_MASK
    checksum += ccall("w_pnf_string_signature", values[index].to_s) == expected[index] ? 1 : 0
    i += 1
  [ccall("w_pnf_thread_cpu_ns") - start_ns, checksum]

-> time_mac_to_s(values, expected, iters, run_id)
  checksum = 0
  i = 0
  start_ns = ccall("w_pnf_thread_cpu_ns")
  while i < iters
    index = i & CORPUS_MASK
    checksum += ccall("w_pnf_string_signature", values[index].to_s) == expected[index] ? 1 : 0
    i += 1
  [ccall("w_pnf_thread_cpu_ns") - start_ns, checksum]

-> run_once(kind, values, expected, iters, run_id)
  if kind in ("ipv4.to_s.plain" "ipv4.to_s.cidr")
    return time_ipv4_to_s(values, expected, iters, run_id)
  if kind in ("ipv6.to_s.plain" "ipv6.to_s.cidr")
    return time_ipv6_to_s(values, expected, iters, run_id)
  time_mac_to_s(values, expected, iters, run_id)

# Native lowering treats a trailing block on these no-block methods as an
# implicit `.each` over the returned String. Each helper bounds a hypothetical
# iterable String with `break`; the runner compares baseline/candidate status
# and semantic output for the three migrated public methods.
-> block_ipv4_to_s
  value = IPv4.of(192, 0, 2, 1)
  hits = 0
  value.to_s -> (ignored)
    hits += 1
    break
  << "BLOCK_RETURN|ipv4.to_s|[hits]"

-> block_ipv6_to_s
  value = IPv6.parse("2001:db8::1")
  hits = 0
  value.to_s -> (ignored)
    hits += 1
    break
  << "BLOCK_RETURN|ipv6.to_s|[hits]"

-> block_mac_to_s
  value = MAC.parse("00:11:22:33:44:55")
  hits = 0
  value.to_s -> (ignored)
    hits += 1
    break
  << "BLOCK_RETURN|mac.to_s|[hits]"

-> run_block(kind)
  if kind == "ipv4.to_s"
    return block_ipv4_to_s()
  if kind == "ipv6.to_s"
    return block_ipv6_to_s()
  if kind == "mac.to_s"
    return block_mac_to_s()
  << "unknown block probe: [kind]"
  exit(2)

args = argv()
mode = args.size() > 0 ? args[0] : "check"
if mode == "check"
  run_check()
  exit(0)
if mode == "block" && args.size() == 2
  run_block(args[1])
  exit(0)
if mode != "bench" || args.size() < 3
  << "usage: packed-network-format (check | block METHOD | bench STRATUM ITERS [WARMUP])"
  exit(2)

kind = args[1]
iters = args[2].to_i
warmup = args.size() > 3 ? args[3].to_i : DEFAULT_WARMUP
values = build_values(kind)
expected = expected_signatures(values)
run_once(kind, values, expected, warmup, 0)
result = run_once(kind, values, expected, iters, 1)
<< "RESULT|[kind]|[result[0]]|[result[1]]"
