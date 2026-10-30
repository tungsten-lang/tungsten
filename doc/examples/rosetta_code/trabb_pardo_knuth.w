# Trabb Pardo-Knuth algorithm

-> f_scaled(t)
  # f(t) = sqrt(|t|) + 5 * t^3 for integer inputs whose |t| is a perfect square
  abs_t = t
  if abs_t < 0
    abs_t = -abs_t
  root = 0
  while (root + 1) * (root + 1) <= abs_t
    root += 1
  root + 5 * t * t * t

seq = [0, 1, -1, 4, -4, 9]
rev = seq.reverse
rev.each -> (x)
  y = f_scaled(x)
  if y > 400
    << "f([x]): TOO LARGE"
  else
    << "f([x]) = [y]"

## expect stdout
## f(9): TOO LARGE
## f(-4) = -318
## f(4) = 322
## f(-1) = -4
## f(1) = 6
## f(0) = 0
