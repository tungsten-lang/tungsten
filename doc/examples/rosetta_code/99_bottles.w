# 99 Bottles of Beer

-> bottles(n)
  if n == 0
    "no more bottles"
  elsif n == 1
    "1 bottle"
  else
    "[n] bottles"

-> sing(start)
  n = start
  while n > 0
    << "[bottles(n)] of beer on the wall, [bottles(n)] of beer."
    n -= 1
    << "Take one down and pass it around, [bottles(n)] of beer on the wall."
    if n > 0
      << ""

sing(99)

## expect stdout
## 99 bottles of beer on the wall, 99 bottles of beer.
## Take one down and pass it around, 98 bottles of beer on the wall.
##
## 98 bottles of beer on the wall, 98 bottles of beer.
## Take one down and pass it around, 97 bottles of beer on the wall.
##
## ...
##
## 2 bottles of beer on the wall, 2 bottles of beer.
## Take one down and pass it around, 1 bottle of beer on the wall.
##
## 1 bottle of beer on the wall, 1 bottle of beer.
## Take one down and pass it around, no more bottles of beer on the wall.
