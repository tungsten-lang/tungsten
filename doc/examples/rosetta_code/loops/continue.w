# Loops/Continue

-> demo_continue()
  parts = []
  i = 1
  while i <= 10
    parts.push(i.to_s)
    if i % 5 == 0
      << parts.join(", ")
      parts = []
    i += 1

demo_continue()

## expect stdout
## 1, 2, 3, 4, 5
## 6, 7, 8, 9, 10
