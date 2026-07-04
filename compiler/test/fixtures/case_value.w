# Pattern matching case with subject
-> describe(x)
  case x
    "red" =>
      return "warm"
    "blue" =>
      return "cool"
    "green" =>
      return "nature"
    =>
      return "unknown"

<< describe("red")
<< describe("blue")
<< describe("green")
<< describe("purple")

# Integer patterns
-> label(n)
  case n
    1 =>
      return "one"
    2 =>
      return "two"
    3 =>
      return "three"
    =>
      return "other"

<< label(1)
<< label(2)
<< label(3)
<< label(99)
