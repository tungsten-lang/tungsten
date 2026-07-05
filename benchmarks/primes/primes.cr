def is_prime(n : Int32) : Bool
  return false if n < 2
  return true if n < 4
  return false if n % 2 == 0 || n % 3 == 0
  i = 5
  while i * i <= n
    return false if n % i == 0 || n % (i + 2) == 0
    i += 6
  end
  true
end

count = 0
2.upto(120000000) do |n|
  count += 1 if is_prime(n)
end
puts count
