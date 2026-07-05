count = 0
i = 0
while i < 1000
  j = 0
  while j < 1000
    k = 0
    while k < 1000
      count = (count + i * 31 + j * 17 + k) % 1000000007
      k += 1
    end
    j += 1
  end
  i += 1
end
puts count
