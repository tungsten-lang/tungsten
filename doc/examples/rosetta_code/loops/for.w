# Tungsten uses iterator-style loops.
(1..5).each ->(i)
  i.times ->(_j)
    <- "*"
  << ""

# Integer#times
5.times ->(i)
  (i + 1).times ->(_j)
    <- "*"
  << ""

## expect stdout
## *
## **
## ***
## ****
## *****
## *
## **
## ***
## ****
## *****
