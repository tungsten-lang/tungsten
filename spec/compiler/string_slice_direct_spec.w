-> check(name, got, want)
  if got != want
    << "FAIL string slice " + name + " got=" + got + " want=" + want
    exit(1)
  << "PASS string slice " + name

slice_src = "aébcdef"
slice_start = 3 ## i64
slice_len = 2 ## i64
check("machine indices", slice_src.slice(slice_start, slice_len), "bc")
check("negative start", slice_src.slice(-3, 2), "de")
check("too negative clamps", slice_src.slice(-99, 1), "a")
check("past end", slice_src.slice(99, 2), "")
check("overlong", slice_src.slice(3, 99), "bcdef")
check("zero length", slice_src.slice(1, 0), "")
check("negative length", slice_src.slice(1, -2), "")
check("utf8 bytes", slice_src.slice(1, 2), "é")
