# Sierpinski carpet

-> in_carpet?(x, y)
  while x > 0 && y > 0
    if x % 3 == 1 && y % 3 == 1
      return false
    x /= 3
    y /= 3
  true

-> carpet(n)
  size = 1
  i = 0
  while i < n
    size *= 3
    i += 1
  y = 0
  while y < size
    line = ""
    x = 0
    while x < size
      if in_carpet?(x, y)
        line += "#"
      else
        line += " "
      x += 1
    << line
    y += 1

carpet(2)

## expect stdout
## #########
## # ## ## #
## #########
## ###   ###
## # #   # #
## ###   ###
## #########
## # ## ## #
## #########
