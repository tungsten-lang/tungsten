# Function composition

-> double(x)
  x * 2

-> inc(x)
  x + 1

double_after_inc = double ∘ inc
inc_after_double = inc ∘ double

<< double_after_inc(5)
<< inc_after_double(5)

## expect stdout
## 12
## 11
