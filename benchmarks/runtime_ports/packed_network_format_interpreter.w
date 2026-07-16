# Tree-walker parity for source-only packed-network to_s wrappers.
# No explicit core imports: literal/native-result autoload must register all
# three primitive classes before dispatch.

-> fail(name, got, expected)
  << "FAIL [name]: got=[got] expected=[expected]"
  exit(1)

-> check(name, got, expected)
  if got != expected
    fail(name, got, expected)

ip4 = 198.51.100.7/24
ip4_bits = wvalue_bits(ip4)
check("IPv4 to_s", ip4.to_s, "198.51.100.7/24")
check("IPv4 to_s surplus", ip4.to_s(1, 2, 3), "198.51.100.7/24")
check("IPv4 receiver stable", wvalue_bits(ip4), ip4_bits)

ip6 = 2001:db8::1/64
ip6_bits = wvalue_bits(ip6)
ip6_prefix = ip6.prefix
ip6_first = ip6.byte(0)
ip6_last = ip6.byte(15)
check("IPv6 to_s", ip6.to_s, "2001:db8:0:0:0:0:0:1/64")
check("IPv6 to_s surplus", ip6.to_s(1, 2, 3), "2001:db8:0:0:0:0:0:1/64")
check("IPv6 receiver bits stable", wvalue_bits(ip6), ip6_bits)
check("IPv6 prefix stable", ip6.prefix, ip6_prefix)
check("IPv6 first byte stable", ip6.byte(0), ip6_first)
check("IPv6 last byte stable", ip6.byte(15), ip6_last)

mac = ccall("w_mac_parse", "02-11-22-33-44-55")
mac_bits = wvalue_bits(mac)
mac_first = mac.byte(0)
mac_last = mac.byte(5)
check("MAC to_s", mac.to_s, "02:11:22:33:44:55")
check("MAC to_s surplus", mac.to_s(1, 2, 3), "02:11:22:33:44:55")
check("MAC receiver bits stable", wvalue_bits(mac), mac_bits)
check("MAC first byte stable", mac.byte(0), mac_first)
check("MAC last byte stable", mac.byte(5), mac_last)

# The tree walker passes the attached block to the source callee instead of
# native lowering's implicit-result-each rewrite. These formatter wrappers do
# not accept a block, so it is ignored exactly as by the old C IC ABI.
hits = 0
result = ip4.to_s -> (ignored)
  hits += 1
check("IPv4 to_s block result", result, "198.51.100.7/24")
check("IPv4 to_s block ignored", hits, 0)
result = ip6.to_s -> (ignored)
  hits += 1
check("IPv6 to_s block result", result, "2001:db8:0:0:0:0:0:1/64")
check("IPv6 to_s block ignored", hits, 0)
result = mac.to_s -> (ignored)
  hits += 1
check("MAC to_s block result", result, "02:11:22:33:44:55")
check("MAC to_s block ignored", hits, 0)
<< "PASS interpreter packed-network to_s: no-import autoload, exact output, receiver stability, surplus args, ignored blocks"
