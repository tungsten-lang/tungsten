# ABACABA sequence

-> abacaba(n)
  s = ""
  i = 0
  while i < n
    ch = (65 + i).chr
    s = s + ch + s
    i += 1
  s

(1..4).each -> (k)
  << abacaba(k)

## expect stdout
## A
## ABA
## ABACABA
## ABACABADABACABA
