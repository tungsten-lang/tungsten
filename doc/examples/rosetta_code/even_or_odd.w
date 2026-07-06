# Even or odd

-> even?(n)
  n % 2 == 0

-> odd?(n)
  n % 2 != 0

(0..10).each -> (n)
  if even?(n)
    << "[n] is even"
  else
    << "[n] is odd"

## expect stdout
## 0 is even
## 1 is odd
## 2 is even
## 3 is odd
## 4 is even
## 5 is odd
## 6 is even
## 7 is odd
## 8 is even
## 9 is odd
## 10 is even
