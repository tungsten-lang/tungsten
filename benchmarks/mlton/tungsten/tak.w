# Port of upstream/tests/tak.sml from the MLton benchmark suite.

-> tak(x, y, z)
  return z if !(y < x)

  tak(
    tak(x - 1, y, z),
    tak(y - 1, z, x),
    tak(z - 1, x, y)
  )

result = tak(33, 22, 11)
if result != 22
  << "bug"
  exit(1)

<< result
