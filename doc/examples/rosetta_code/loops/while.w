# https://rosettacode.org/wiki/Loops/While#Ruby
i = 1024

while i > 0
  << i
  i /= 2

# more idiomatically
<< i = 1024
<< i /= 2 while i > 0

# using until
i = 1024
until i <= 0
  << i
  i /= 2

## expect stdout
## 1024
## 512
## 256
## 128
## 64
## 32
## 16
## 8
## 4
## 2
## 1
## 1024
## 512
## 256
## 128
## 64
## 32
## 16
## 8
## 4
## 2
## 1
## 0
## 1024
## 512
## 256
## 128
## 64
## 32
## 16
## 8
## 4
## 2
## 1
