# Native WNetAddr field access and source-defined IPv6/MAC behavior.

-> check(name, got, want)
  if got != want
    << "FAIL [name]: got=[got] want=[want]"
    exit(1)

-> check_ipv4_octets(name, got, a, b, c, d)
  check(name + " size", got.size, 4)
  check(name + " a", got[0], a)
  check(name + " b", got[1], b)
  check(name + " c", got[2], c)
  check(name + " d", got[3], d)

ip = IPv6.parse("2001:db8:abcd:1234:5678:9abc:def0:1357")
literal_ip = 2001:db8::1
literal_net = 2001:db8::/32
check("ipv6 literal autoload byte", literal_ip.byte(0), 0x20)
check("ipv6 cidr literal autoload prefix", literal_net.prefix, 32)
check("ipv6 cidr literal autoload include", literal_net.include?(literal_ip), true)
check("ipv6 byte first", ip.byte(0), 0x20)
check("ipv6 byte second", ip[1], 0x01)
check("ipv6 byte last", ip.byte(15), 0x57)
check("ipv6 byte negative", ip.byte(-1), nil)
check("ipv6 byte high", ip.byte(16), nil)
check("ipv6 byte float coercion", ip.byte(~1.9), 0x01)
check("ipv6 bytes size", ip.bytes.size, 16)
check("ipv6 bytes content", ip.bytes[14], 0x13)
check("ipv6 plain prefix", ip.prefix, nil)
check("ipv6 plain cidr", ip.cidr?, false)

p = 0
while p <= 128
  prefixed = ip.with_prefix(p)
  check("ipv6 prefix roundtrip", prefixed.prefix, p)
  check("ipv6 cidr roundtrip", prefixed.cidr?, true)
  p += 1
check("ipv6 negative prefix clears", ip.with_prefix(-7).prefix, nil)
check("ipv6 nil prefix clears", ip.with_prefix(nil).prefix, nil)
invalid_prefix_raised = false
begin
  ip.with_prefix(129)
rescue error
  invalid_prefix_raised = true
check("ipv6 invalid prefix raises", invalid_prefix_raised, true)
huge_ipv6_prefix_raised = false
begin
  ip.with_prefix(4294967296)
rescue error
  huge_ipv6_prefix_raised = true
check("ipv6 huge prefix raises", huge_ipv6_prefix_raised, true)

ipv4 = IPv4.of(192, 0, 2, 1)
ipv4_octets = ipv4.octets
check_ipv4_octets("ipv4 octets", ipv4_octets, 192, 0, 2, 1)
check_ipv4_octets("ipv4 prefixed octets",
                  IPv4.of(255, 128, 1, 0, 17).octets,
                  255, 128, 1, 0)
check_ipv4_octets("ipv4 octets surplus arguments",
                  ipv4.octets(123, "ignored"),
                  192, 0, 2, 1)
ipv4_octets[0] = 9
check("ipv4 octets fresh allocation", ipv4.octets[0], 192)
check("ipv4 of valid prefix", IPv4.of(192, 0, 2, 1, 24).prefix, 24)
huge_ipv4_prefix_raised = false
begin
  IPv4.of(192, 0, 2, 1, 4294967296)
rescue error
  huge_ipv4_prefix_raised = true
check("ipv4 of huge prefix raises", huge_ipv4_prefix_raised, true)
wide_ipv4_octet_raised = false
begin
  IPv4.of(18446744073709551616, 0, 2, 1)
rescue error
  wide_ipv4_octet_raised = true
check("ipv4 bigint octet raises", wide_ipv4_octet_raised, true)
wide_ipv4_prefix_raised = false
begin
  IPv4.of(192, 0, 2, 1, 18446744073709551616)
rescue error
  wide_ipv4_prefix_raised = true
check("ipv4 bigint prefix raises", wide_ipv4_prefix_raised, true)
huge_ipv4_with_prefix_raised = false
begin
  ipv4.with_prefix(4294967296)
rescue error
  huge_ipv4_with_prefix_raised = true
check("ipv4 with huge prefix raises", huge_ipv4_with_prefix_raised, true)
wide_ipv6_prefix_raised = false
begin
  ip.with_prefix(18446744073709551616)
rescue error
  wide_ipv6_prefix_raised = true
check("ipv6 bigint prefix raises", wide_ipv6_prefix_raised, true)

net37 = ip.with_prefix(37)
check("ipv6 network /37", net37.network,
      IPv6.parse("2001:db8:a800:0:0:0:0:0/37"))
check("ipv6 include /37 inside", net37.include?(IPv6.parse("2001:db8:afff:ffff:ffff:ffff:ffff:ffff")), true)
check("ipv6 include /37 outside", net37.include?(IPv6.parse("2001:db8:b000:0:0:0:0:0")), false)
check("ipv6 include wrong type", net37.include?(IPv4.parse("1.2.3.4")), false)
check("ipv6 contains alias", net37.contains?(ip), true)
check("ipv6 plain network", ip.network, ip)

check("ipv6 unspecified", IPv6.parse("::").unspecified?, true)
check("ipv6 unspecified boundary", IPv6.parse("::1").unspecified?, false)
check("ipv6 loopback", IPv6.parse("::1").loopback?, true)
check("ipv6 loopback boundary", IPv6.parse("::2").loopback?, false)
check("ipv6 multicast", IPv6.parse("ff00::").multicast?, true)
check("ipv6 multicast lower boundary", IPv6.parse("feff::").multicast?, false)
check("ipv6 link-local low", IPv6.parse("fe80::").link_local?, true)
check("ipv6 link-local high", IPv6.parse("febf:ffff::").link_local?, true)
check("ipv6 link-local outside", IPv6.parse("fec0::").link_local?, false)
check("ipv6 unique-local fc", IPv6.parse("fc00::").unique_local?, true)
check("ipv6 unique-local fd", IPv6.parse("fdff::").private?, true)
check("ipv6 unique-local outside", IPv6.parse("fe00::").unique_local?, false)
check("ipv6 global", IPv6.parse("2001:4860:4860::8888").global?, true)
check("ipv6 global excludes unspecified", IPv6.parse("::").global?, false)
check("ipv6 global excludes loopback", IPv6.parse("::1").global?, false)
check("ipv6 global excludes multicast", IPv6.parse("ff02::1").global?, false)
check("ipv6 global excludes link-local", IPv6.parse("fe80::1").global?, false)
check("ipv6 global excludes unique-local", IPv6.parse("fd00::1").global?, false)

mac = MAC.parse("02-11-22-33-44-55")
check("mac byte first", mac.byte(0), 0x02)
check("mac index last", mac[5], 0x55)
check("mac byte negative", mac.byte(-1), nil)
check("mac byte high", mac.byte(6), nil)
check("mac byte float coercion", mac.byte(~1.9), 0x11)
mac_bytes = mac.bytes
check("mac bytes size", mac_bytes.size, 6)
check("mac bytes 0", mac_bytes[0], 2)
check("mac bytes 1", mac_bytes[1], 17)
check("mac bytes 2", mac_bytes[2], 34)
check("mac bytes 3", mac_bytes[3], 51)
check("mac bytes 4", mac_bytes[4], 68)
check("mac bytes 5", mac_bytes[5], 85)
check("mac local", mac.local?, true)
check("mac universal", mac.universal?, false)
check("mac multicast", mac.multicast?, false)
check("mac unicast", mac.unicast?, true)
check("mac broadcast", mac.broadcast?, false)
check("mac broadcast all ff", MAC.parse("ff:ff:ff:ff:ff:ff").broadcast?, true)
check("mac multicast bit", MAC.parse("01:00:5e:00:00:01").multicast?, true)
check("mac universal bit", MAC.parse("00:11:22:33:44:55").universal?, true)

<< "network_native_spec: all checks passed"
