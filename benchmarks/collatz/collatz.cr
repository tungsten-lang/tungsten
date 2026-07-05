def collatz_steps(n : Int64) : Int32
  steps = 0
  while n != 1
    if n % 2 == 0
      n = n // 2
    else
      n = 3_i64 &* n &+ 1
    end
    steps += 1
  end
  steps
end

total = 0
i = 1_i64
while i <= 5000000
  total += collatz_steps(i)
  i += 1
end
puts total
