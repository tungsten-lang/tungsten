use core/regex
subj = "the order id is 4521-9837 today"
r = Regex.new("(\\d+)-(\\d+)")
r.match(subj)
n = 200000
t0 = ccall("__w_clock_ms")
hits = 0
i = 0
while i < n
  m = r.match(subj)
  if m != nil
    hits = hits + 1
  i = i + 1
t1 = ccall("__w_clock_ms")
ms = t1 - t0
<< "mine (Tungsten): " + ms.to_s() + " ms / " + n.to_s() + " matches = " + (ms * 1000000 / n).to_s() + " ns/match"
