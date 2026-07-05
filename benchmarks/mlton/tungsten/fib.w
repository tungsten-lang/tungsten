# Port of upstream/tests/fib.sml from the MLton benchmark suite.
# Use `->`, not `fn`, so Tungsten does not memoize the recursive calls.

-> fib(n)
  return 0 if n == 0
  return 1 if n == 1
  fib(n - 1) + fib(n - 2)

result = fib(41)
if result != 165580141
  << "bug"
  exit(1)

<< result
