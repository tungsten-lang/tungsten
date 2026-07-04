-> sierpinski(n)
  rows = 1 << n

  0...rows -> (r)
    # Leading spaces
    line = StringBuffer(2 ** r)

    s = 0
    while s < rows - r - 1
      line << " "
      s++

    # Pixels: bit pattern r & c == 0 means filled
    0..r -> (c)
      if (r & c) == c
        line << "▲ "
      else
        line << "  "
    << line

sierpinski(5)

## expect skip still working on this one
