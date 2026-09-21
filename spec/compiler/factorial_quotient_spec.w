# Compiled-only cancellation regression. Expanding these factorials would
# require a trillion iterations; lowering must retain only the small tail.
-> check(name, got, want)
  if got != want
    << "FAIL [name]: got=[got] want=[want]"
    exit(1)

check("huge equal bounds", 1000000000000! / 1000000000000!, 1)
check("huge adjacent bounds", 1000000000000! / 999999999999!, 1000000000000)
check("grouped literal cancellation", (1000000000000)! / (999999999999)!, 1000000000000)
check("huge two-factor tail", (1000000000000! / 999999999998!).to_s, "999999999999000000000000")
check("huge hex bounds", 0x100000000! / 0xFFFFFFFF!, 4294967296)
check("inline boundary", 140737488355327! / 140737488355326!, 140737488355327)
check("ordinary tail", 10! / 5!, 30240)
check("promoting tail", (25! / 5!).to_s, "129260083694424883200000")
<< "PASS factorial quotient cancellation"
