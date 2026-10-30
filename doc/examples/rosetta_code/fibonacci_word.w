# Fibonacci word

-> fib_words(count)
  w1 = "1"
  w2 = "0"
  << "1: len=[w1.size] [w1]"
  << "2: len=[w2.size] [w2]"
  i = 3
  while i <= count
    w3 = w2 + w1
    << "[i]: len=[w3.size] [w3]"
    w1 = w2
    w2 = w3
    i += 1

fib_words(7)

## expect stdout
## 1: len=1 1
## 2: len=1 0
## 3: len=2 01
## 4: len=3 010
## 5: len=5 01001
## 6: len=8 01001010
## 7: len=13 0100101001001
