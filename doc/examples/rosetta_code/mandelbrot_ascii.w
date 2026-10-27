# Mandelbrot set (ASCII)

-> mandelbrot_ascii()
  # Fixed-point integer arithmetic (scale = 1000) for exact cross-engine output
  scale = 1000
  y = -1000
  while y <= 1000
    line = ""
    x = -2000
    while x <= 500
      zr = 0
      zi = 0
      iter = 0
      inside = true
      while iter < 30
        zr2 = (zr * zr) / scale
        zi2 = (zi * zi) / scale
        if zr2 + zi2 > 4000
          inside = false
          break
        zi = (2 * zr * zi) / scale + y
        zr = zr2 - zi2 + x
        iter += 1
      if inside
        line += "#"
      else
        line += "."
      x += 125
    << line
    y += 250

mandelbrot_ascii()

## expect stdout
## ................#....
## ..............###....
## ............#######..
## .......##..#########.
## ###################..
## .......##..#########.
## ............#######..
## ..............###....
## ................#....
