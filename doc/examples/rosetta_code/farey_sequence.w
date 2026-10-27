# Farey sequence

-> farey(n)
  a = 0
  b = 1
  c = 1
  d = n
  terms = ["[a]/[b]"]
  while c <= n
    k = (n + b) / d
    next_a = c
    next_b = d
    next_c = k * c - a
    next_d = k * d - b
    a = next_a
    b = next_b
    c = next_c
    d = next_d
    terms.push("[a]/[b]")
  terms.join(" ")

(1..6).each -> (n)
  << "F([n]): [farey(n)]"

## expect stdout
## F(1): 0/1 1/1
## F(2): 0/1 1/2 1/1
## F(3): 0/1 1/3 1/2 2/3 1/1
## F(4): 0/1 1/4 1/3 1/2 2/3 3/4 1/1
## F(5): 0/1 1/5 1/4 1/3 2/5 1/2 3/5 2/3 3/4 4/5 1/1
## F(6): 0/1 1/6 1/5 1/4 1/3 2/5 1/2 3/5 2/3 3/4 4/5 5/6 1/1
