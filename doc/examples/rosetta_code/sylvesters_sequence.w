# Sylvester's sequence

-> sylvester(count)
  seq = [2]
  i = 1
  while i < count
    prev = seq[i - 1]
    seq.push(prev * (prev - 1) + 1)
    i += 1
  seq

seq = sylvester(7)
seq.each -> (x)
  << x

## expect stdout
## 2
## 3
## 7
## 43
## 1807
## 3263443
## 10650056950807
