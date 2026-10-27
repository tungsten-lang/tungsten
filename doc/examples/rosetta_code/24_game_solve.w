# 24 game/Solve

# Solve 24 using exact rational pairs [num, den]
-> eval_op(a, b, op)
  if op == 0
    [a[0] * b[1] + b[0] * a[1], a[1] * b[1]]
  elsif op == 1
    [a[0] * b[1] - b[0] * a[1], a[1] * b[1]]
  elsif op == 2
    [a[0] * b[0], a[1] * b[1]]
  else
    if b[0] == 0
      [0, 0]
    else
      [a[0] * b[1], a[1] * b[0]]

-> op_sym(op)
  if op == 0
    "+"
  elsif op == 1
    "-"
  elsif op == 2
    "*"
  else
    "/"

-> solve24(vals, exprs)
  n = vals.size
  if n == 1
    if vals[0][1] != 0 && vals[0][0] == 24 * vals[0][1]
      return exprs[0]
    return ""
  i = 0
  while i < n
    j = 0
    while j < n
      if i != j
        rest_vals = []
        rest_exprs = []
        k = 0
        while k < n
          if k != i && k != j
            rest_vals.push(vals[k])
            rest_exprs.push(exprs[k])
          k += 1
        op = 0
        while op < 4
          r = eval_op(vals[i], vals[j], op)
          if r[1] != 0
            next_vals = []
            next_exprs = []
            m = 0
            while m < rest_vals.size
              next_vals.push(rest_vals[m])
              next_exprs.push(rest_exprs[m])
              m += 1
            next_vals.push(r)
            sym = op_sym(op)
            next_exprs.push("([exprs[i]] [sym] [exprs[j]])")
            ans = solve24(next_vals, next_exprs)
            if ans != ""
              return ans
          op += 1
      j += 1
    i += 1
  ""

hand = [3, 3, 8, 8]
vals = []
exprs = []
hand.each -> (x)
  vals.push([x, 1])
  exprs.push(x.to_s)

<< solve24(vals, exprs)

## expect stdout
## (8 / (3 - (8 / 3)))
