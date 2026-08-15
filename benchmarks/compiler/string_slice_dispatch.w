-> bench_slice(n, empty)
  source = "abcdefghijklmnop"
  i = 0 ## i64
  checksum = 0 ## i64
  t0 = clock()
  while i < n
    if empty
      piece = source.slice(99, 2)
    else
      piece = source.slice(i & 3, 5)
    checksum += piece.size()
    i += 1
  t1 = clock()
  << "string_slice\t" + (empty ? "empty" : "inline5") + "\t" + n.to_s() + "\t" + ((t1 - t0) * ~1000000000.0 / n.to_f()).to_s() + "\t" + checksum.to_s()

args = argv()
mode = args.size() > 0 ? args[0] : "inline5"
n = args.size() > 1 ? args[1].to_i() : 5000000
bench_slice(n, mode == "empty")
