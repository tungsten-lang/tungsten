# Color cycle benchmark — 10M colors, unboxed loop, raw ccall
n = 10000000
i = 0 ## i64
acc = 0 ## i64

while i < n
  r = (i & 255) ## i64
  g = ((i >> 8) & 255) ## i64
  b = ((i >> 16) & 255) ## i64
  c = ccall("w_color_raw", r, g, b, 255)
  i += 1

<< "tungsten: [n] colors cycled"
