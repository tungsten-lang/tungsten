# Sierpinski triangle

-> sierpinski_ascii(order)
  rows = 1 << order
  r = 0
  while r < rows
    line = ""
    s = 0
    while s < rows - r - 1
      line += " "
      s += 1
    c = 0
    while c <= r
      if (r & c) == c
        if c < r
          line += "* "
        else
          line += "*"
      else
        line += "  "
      c += 1
    << line
    r += 1

sierpinski_ascii(3)

## expect stdout
##        *
##       * *
##      *   *
##     * * * *
##    *       *
##   * *     * *
##  *   *   *   *
## * * * * * * * *
