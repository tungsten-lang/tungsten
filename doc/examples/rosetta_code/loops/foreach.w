# https://rosettacode.org/wiki/Loops/Foreach#Ruby

list = [1, 2, 3]

list.each ->(i)
  << i

## expect stdout
## 1
## 2
## 3
