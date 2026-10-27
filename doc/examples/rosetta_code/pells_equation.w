# Pell's equation

-> solve_pell(n)
  a0 = 1
  while (a0 + 1) * (a0 + 1) <= n
    a0 += 1
  m = 0
  d = 1
  a = a0
  num1 = 1
  num2 = a
  den1 = 0
  den2 = 1
  while num2 * num2 - n * den2 * den2 != 1
    m = d * a - m
    d = (n - m * m) / d
    a = (a0 + m) / d
    next_num = a * num2 + num1
    next_den = a * den2 + den1
    num1 = num2
    num2 = next_num
    den1 = den2
    den2 = next_den
  [num2, den2]

ns = [61, 109, 181, 277]
ns.each -> (n)
  sol = solve_pell(n)
  << "x^2 - [n]*y^2 = 1: x=[sol[0]], y=[sol[1]]"

## expect stdout
## x^2 - 61*y^2 = 1: x=1766319049, y=226153980
## x^2 - 109*y^2 = 1: x=158070671986249, y=15140424455100
## x^2 - 181*y^2 = 1: x=2469645423824185801, y=183567298683461940
## x^2 - 277*y^2 = 1: x=159150073798980475849, y=9562401173878027020
