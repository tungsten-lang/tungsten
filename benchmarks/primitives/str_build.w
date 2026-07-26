# primitive: str_build — 20000000 ops
sb = StringBuffer(64)
n = 20000000 ## i64
t0 = clock
i = 0 ## i64
while i < n
  sb << "abcdefghij"
  i = i + 1
t1 = clock
<< "ops: 200000000"
<< sb.to_s().size()
<< "elapsed: [t1 - t0]s"
