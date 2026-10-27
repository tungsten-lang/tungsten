# Fermat numbers

-> fermat(n)
  exp = 1 << n
  (1 << exp) + 1

(0..4).each -> (n)
  << "F([n]) = [fermat(n)]"

## expect stdout
## F(0) = 3
## F(1) = 5
## F(2) = 17
## F(3) = 257
## F(4) = 65537
