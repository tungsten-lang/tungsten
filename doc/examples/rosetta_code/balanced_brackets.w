# Balanced brackets

-> balanced?(s)
  depth = 0
  i = 0
  while i < s.length
    if s[i] == "\["
      depth += 1
    elsif s[i] == "\]"
      depth -= 1
      if depth < 0
        return false
    i += 1
  depth == 0

tests = ["", "\[\]", "\[\]\[\]", "\[\[\]\[\]\]", "\]\[", "\]\[\]\[", "\[\]\]\[\[\]"]
tests.each -> (t)
  if balanced?(t)
    << "\"[t]\" is balanced"
  else
    << "\"[t]\" is NOT balanced"

## expect stdout
## "" is balanced
## "[]" is balanced
## "[][]" is balanced
## "[[][]]" is balanced
## "][" is NOT balanced
## "][][" is NOT balanced
## "[]][[]" is NOT balanced
