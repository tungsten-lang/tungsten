# Mutual recursion (Hofstadter Female and Male sequences)

-> f(n)
  if n == 0
    1
  else
    n - m(f(n - 1))

-> m(n)
  if n == 0
    0
  else
    n - f(m(n - 1))

fs = (0..20).map -> (i) "F([i])=[f(i)]"
<< fs.join(" ")
ms = (0..20).map -> (i) "M([i])=[m(i)]"
<< ms.join(" ")

## expect stdout
## F(0)=1 F(1)=1 F(2)=2 F(3)=2 F(4)=3 F(5)=3 F(6)=4 F(7)=5 F(8)=5 F(9)=6 F(10)=6 F(11)=7 F(12)=8 F(13)=8 F(14)=9 F(15)=9 F(16)=10 F(17)=11 F(18)=11 F(19)=12 F(20)=13
## M(0)=0 M(1)=0 M(2)=1 M(3)=2 M(4)=2 M(5)=3 M(6)=4 M(7)=4 M(8)=5 M(9)=6 M(10)=6 M(11)=7 M(12)=7 M(13)=8 M(14)=9 M(15)=9 M(16)=10 M(17)=11 M(18)=11 M(19)=12 M(20)=12
