# Sum of a series: 1/k^2 for k = 1 to 1000

sum = 0.0
k = 1
while k <= 1000
  sum += 1.0 / (k * k)
  k += 1

<< sum

## parity skip decimal formatting differs in compiled output
## expect stdout
## 1.6439345666815598031390580238222151484
