# Exceptions

-> safe_divide(a, b)
  begin
    if b == 0
      raise "division by zero"
    << "[a] / [b] = [a / b]"
  rescue e
    << "Caught error: [e]"

safe_divide(10, 2)
safe_divide(10, 0)

## expect stdout
## 10 / 2 = 5
## Caught error: division by zero
