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

result = apply(10, 20) -> (a, b)
  a * b
<< result

## expect stdout
## Hello!
## 7
## 200
