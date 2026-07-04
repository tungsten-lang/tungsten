# Fibonacci sequence

-> fib(n)
  if n <= 1
    return n
  fib(n - 1) + fib(n - 2)

(0..20).each -> (i)
  << fib(i)

## expect stdout
## 0
## 1
## 1
## 2
## 3
## 5
## 8
## 13
## 21
## 34
## 55
## 89
## 144
## 233
## 377
## 610
## 987
## 1597
## 2584
## 4181
## 6765
