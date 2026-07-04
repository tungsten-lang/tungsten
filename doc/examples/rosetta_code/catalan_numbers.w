# Catalan numbers

-> factorial(n)
  if n <= 1
    1
  else
    n * factorial(n - 1)

-> catalan(n)
  factorial(2 * n) / (factorial(n + 1) * factorial(n))

0.upto(15) { |n|
  puts "C([n]) = [catalan(n)]"
}

## expect skip currently unsupported in this runtime
