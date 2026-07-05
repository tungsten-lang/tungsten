def ackermann(m : Int32, n : Int32) : Int32
  if m == 0
    n + 1
  elsif n == 0
    ackermann(m - 1, 1)
  else
    ackermann(m - 1, ackermann(m, n - 1))
  end
end

puts ackermann(3, 12)
