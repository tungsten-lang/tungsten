# Higher-order functions

-> twice(f, x)
  f(f(x))

triple = -> (n)
  n * 3

<< twice(triple, 2)
<< twice(triple, 5)

## expect stdout
## 18
## 45
