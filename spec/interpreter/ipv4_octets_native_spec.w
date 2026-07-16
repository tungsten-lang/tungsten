# Tree-walker parity for source-only IPv4#octets after removing its C IC.

-> check(name, got, want)
  if got != want
    << "FAIL [name]: got=[got] want=[want]"
    exit(1)

-> check_octets(name, got, a, b, c, d)
  check(name + " size", got.size, 4)
  check(name + " a", got[0], a)
  check(name + " b", got[1], b)
  check(name + " c", got[2], c)
  check(name + " d", got[3], d)

ip = IPv4.of(192, 0, 2, 1, 24)
first = ip.octets
second = ip.octets(123, "ignored")

check_octets("octets", first, 192, 0, 2, 1)
check_octets("surplus arguments", second, 192, 0, 2, 1)
check("ordinary Array capacity", first.cap, 8)
check("fresh allocation", wvalue_bits(first) == wvalue_bits(second), false)

first[0] = 9
first.push(77)
check("mutated result size", first.size, 5)
check("mutated result first", first[0], 9)
check("mutated result tail", first[4], 77)
check_octets("independent result", second, 192, 0, 2, 1)
check_octets("receiver unchanged", ip.octets, 192, 0, 2, 1)
check_octets("prefix ignored", IPv4.of(255, 128, 1, 0, 17).octets,
             255, 128, 1, 0)

<< "PASS interpreter IPv4#octets source parity"
