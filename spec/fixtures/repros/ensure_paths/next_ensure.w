# next-through-ensure inside an iterator block: `next` returns from the
# block function; an ensure opened inside the block body must run first.
log = ""
[1, 2, 3].each -> (x)
  begin
    log = log + "a"
    if x == 2
      next
    log = log + "b"
  ensure
    log = log + "e"
<< "log:" + log
