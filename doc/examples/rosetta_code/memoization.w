# Memoization

fn fib(n)
  if n <= 1
    n
  else
    fib(n - 1) + fib(n - 2)

<< fib(10)
<< fib(20)
<< fib(30)

## expect stdout
## 55
## 6765
## 832040
