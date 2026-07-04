# Token comparison: Tungsten vs Python
# Tungsten saves ~29% tokens on equivalent programs.

-> fib(n)
  if n <= 1
    n
  else
    fib(n - 1) + fib(n - 2)

<< "fib(10) = [fib(10)]"

## expect stdout
## fib(10) = 55
