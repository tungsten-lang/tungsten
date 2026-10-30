# Currying

+ Adder
  -> new(@a) ro

  -> call(b)
    @a + b

-> curry_add(a)
  Adder.new(a)

add5 = curry_add(5)
add10 = curry_add(10)

<< add5.call(3)
<< add5.call(12)
<< add10.call(7)

## expect stdout
## 8
## 17
## 17
