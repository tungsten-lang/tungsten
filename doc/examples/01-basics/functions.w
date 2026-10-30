# Functions in Tungsten

# Simple function
-> greet(name)
  << "Hello, [name]!"

greet("world")

# Function with return value
-> square(n)
  n * n

<< square(5)

# Pure function (auto-memoized)
fn fib(n)
  if n <= 1
    n
  else
    fib(n - 1) + fib(n - 2)

<< fib(10)

# Arity shorthand
-> add/2 @1 + @2

<< add(3, 4)

## expect stdout
## Hello, world!
## 25
## 55
## 7
