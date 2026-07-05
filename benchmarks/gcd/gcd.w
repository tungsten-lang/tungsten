fn gcd(a, b)
  while b != 0
    t = b
    b = a % b
    a = t
  return a

fn main
  result = 0 ## u64
  with i in 1..22000000
    result += gcd(i, 31415927)

  result

<< main
