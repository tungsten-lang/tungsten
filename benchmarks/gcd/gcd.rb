def gcd(a, b)
  while b != 0
    t = b
    b = a % b
    a = t
  end
  a
end

result = 0
i = 1
while i <= 22000000
  result += gcd(i, 31415927)
  i += 1
end
puts result
