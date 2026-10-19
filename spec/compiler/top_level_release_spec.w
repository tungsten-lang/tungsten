# spec: compiled -- exercises the ownership pass on top-level script loops
# A top-level variable is a module global mirrored into a slot of main, and
# main reads only the slot (compiler/lib/ownership.w write_only_globals).  Its
# global copy is a dead write, so a top-level loop's values are released like a
# function's: temporaries after their last read, a variable's old value after
# the next assignment, and an integer held by two variables only when the
# second lets go.  Every shape is checked against a value computed in a
# function, then the memory of a long top-level loop is bounded.

-> check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> ref_mix(x, n)
  acc = 0
  i = 0
  while i < n
    acc = (acc + (x * x + i) % 1000003) % 1000003
    i += 1
  acc

x = (3 ## int) ** 2000 + 12345

acc = 0
i = 0
while i < 50
  y = x * x + i
  acc = (acc + y % 1000003) % 1000003
  i += 1
check("temporaries and a reassigned variable", acc == ref_mix(x, 50))

a = 0
b = 0
i = 0
while i < 20
  a = x * x + i
  b = a
  a = a + 1
  i += 1
check("a copy keeps its value when the original moves on", b == x * x + 19 && a == x * x + 20)

kept = []
i = 0
while i < 20
  v = x * 3 + i
  kept.push(v)
  i += 1
check("values stored in a container stay valid", kept[0] == x * 3 && kept[19] == x * 3 + 19)

# Memory: 3,000 rounds at 100,000 bits kept every square and remainder before
# (about 650 MB); now a few live at a time.
m = ((1 ## int) << 100_000) - 1
s = (3 ## int) ** 1000
i = 0
while i < 3000
  s = (s * s + i) % m
  i += 1
rss_kib = OS.capture("ps -o rss= -p $PPID").strip().to_i()
check("3,000 top-level rounds at 100,000 bits stay under 30 MB (rss_kib=[rss_kib])", rss_kib > 0 && rss_kib < 30_720)
check("and the result is still below the modulus", s >= 0 && s < m)
<< "top_level_release_spec: all checks passed"
