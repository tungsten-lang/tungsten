# Call a function

# No arguments
-> greet
  << "Hello!"

greet

# Fixed arguments
-> add(a, b)
  a + b

<< add(3, 4)

# With a block
-> apply(x, y)
  yield(x, y)

result = apply(10, 20) -> a * b
<< result

## expect skip compiled-only for now — the Ruby interpreter (which runs this harness) can't execute it; try `bin/tungsten call_a_function.w`
## expect stdout
## Hello!
## 7
## 200
