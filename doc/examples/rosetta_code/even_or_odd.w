# Even or odd

-> even?(n)
  n % 2 == 0

-> odd?(n)
  n % 2 != 0

0.upto(10) { |n|
  if even?(n)
    puts "[n] is even"
  else
    puts "[n] is odd"
}

## expect skip currently unsupported in this runtime
