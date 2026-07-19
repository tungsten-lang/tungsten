# break/next-through-ensure in a while loop: a break or next that leaves a
# begin/ensure region opened inside the loop body must run the ensure body
# before transferring (spec 4.6.5 — ensure runs on every exit path).
i = 0
log = ""
while i < 5
  begin
    log = log + "b"
    if i == 2
      break
    i += 1
    log = log + "c"
  ensure
    log = log + "e"
<< "log:" + log + "|i:" + i.to_s()

j = 0
nlog = ""
while j < 3
  j += 1
  begin
    nlog = nlog + "t"
    if j == 2
      next
    nlog = nlog + "u"
  ensure
    nlog = nlog + "v"
<< "nlog:" + nlog
