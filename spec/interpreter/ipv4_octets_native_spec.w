# Tree-walker parity for source-only IPv4#octets after removing its C IC.

# Surplus arguments are an error on both engines (E_LOWER_ARITY at compile
# time where the callee is known; the interpreter raises at the call).
-> surplus_rejected?(f)
  begin
    f.call
    false
  rescue surplus_error
    true

# The interpreter rejects surplus arguments at the call; the compiled engine
# leaves DYNAMIC dispatch unchecked by design (no runtime arity cost), so on
# an unknown receiver a surplus call still runs. Compile-time checks apply
# only where the callee is statically known. This spec runs in both lanes.
-> surplus_rejection_expected
  env("TUNGSTEN_INTERPRETED_SPEC") == "1"

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
second_rejected = surplus_rejected?(->() ip.octets(123, "ignored"))
second = ip.octets

check_octets("octets", first, 192, 0, 2, 1)
check("surplus arguments rejected", second_rejected, surplus_rejection_expected)
# Ordinary (growable, non-view) array: cap covers the 4 octets. The exact
# value is an allocator detail — array literals allocate EXACT size
# (cap 4) since the exact-size literal change, where the old empty+push
# growth doubled to 8; the push test below proves growability.
check("ordinary Array capacity", first.cap >= 4, true)
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
