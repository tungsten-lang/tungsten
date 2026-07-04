add = ->(a, b)
  a + b
<< add(3, 4)

factor = 10
scale = ->(n)
  n * factor
<< scale(5)

twice = ->(x)
  x * 2
<< twice.call(21)
