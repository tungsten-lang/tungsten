# SEDOLs

-> sedol_char_val(c)
  code = c.ord
  if code >= 48 && code <= 57
    code - 48
  else
    code - 65 + 10

-> sedol_with_check(s)
  weights = [1, 3, 1, 7, 3, 9]
  chars = s.chars
  sum = 0
  i = 0
  while i < 6
    sum += sedol_char_val(chars[i]) * weights[i]
    i += 1
  check = (10 - (sum % 10)) % 10
  "[s][check]"

inputs = ["710889", "B0YBKJ", "406566", "B0YBLH", "228276", "B0YBKL"]
inputs.each -> (inp)
  << sedol_with_check(inp)

## expect stdout
## 7108899
## B0YBKJ7
## 4065663
## B0YBLH2
## 2282765
## B0YBKL9
