# 99 Bottles of Beer

-> bottles(n)
  when n == 0 "no more bottles"
  when n == 1 "1 bottle"
  else        "[n] bottles"

n = 99

while n > 0
  << "[bottles(n)] of beer on the wall, [bottles(n)] of beer."

  << "Take one down and pass it around, " + bottles(n--) + " of beer on the wall."
  <<

## expect skip until the bug in compiler interpolation is fixed
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
