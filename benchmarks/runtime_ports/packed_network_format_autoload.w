# No-import autoload probe for every compiler-recognized network construction
# route relevant to the source formatter wrappers.

-> fail(name, got, expected)
  << "FAIL [name]: got=[got] expected=[expected]"
  exit(1)

-> check(name, got, expected)
  if got != expected
    fail(name, got, expected)

# Packed literals carry no class reference.
ip4 = 198.51.100.7
net4 = 198.51.100.0/24
check("IPv4 literal to_s", ip4.to_s, "198.51.100.7")
check("IPv4 CIDR literal to_s", net4.to_s, "198.51.100.0/24")

# Heap IPv6 literals likewise depend on literal-kind autoload.
ip6 = 2001:db8::1
net6 = 2001:db8::/32
check("IPv6 literal to_s", ip6.to_s, "2001:db8:0:0:0:0:0:1")
check("IPv6 CIDR literal to_s", net6.to_s, "2001:db8:0:0:0:0:0:0/32")

# Exact native-result map entries cover values entering through ccall without
# a literal or class receiver.
parsed4 = ccall("w_ipv4_parse", "203.0.113.9/27")
parsed6 = ccall("w_ipv6_parse", "fe80::1/64")
parsed_mac = ccall("w_mac_parse", "02-11-22-33-44-55")
check("IPv4 ccall result to_s", parsed4.to_s, "203.0.113.9/27")
check("IPv6 ccall result to_s", parsed6.to_s, "fe80:0:0:0:0:0:0:1/64")
check("MAC ccall result to_s", parsed_mac.to_s, "02:11:22:33:44:55")

<< "PASS packed-network to_s no-import literal/call-result autoload"
