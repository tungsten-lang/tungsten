# Accumulator factory
# Create a function that generates accumulators:
# a function that takes a number and returns the running total

-> accumulator(initial)
  sum = initial
  -> (n)
    sum += n
    sum

acc = accumulator(5)
<< acc(3)    # 8
<< acc(10)   # 18
<< acc(2)    # 20

## expect stdout
## 8
## 18
## 20
