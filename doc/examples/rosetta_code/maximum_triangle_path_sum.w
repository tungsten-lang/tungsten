# Maximum triangle path sum

triangle = [
  [55],
  [94, 48],
  [95, 30, 96],
  [77, 71, 26, 67],
  [97, 13, 76, 38, 45],
  [7, 36, 79, 16, 37, 68],
  [48, 7, 9, 18, 70, 26, 6],
  [18, 72, 79, 46, 59, 79, 29, 90]
]

r = triangle.size - 2
while r >= 0
  c = 0
  while c <= r
    left = triangle[r + 1][c]
    right = triangle[r + 1][c + 1]
    if left > right
      triangle[r][c] += left
    else
      triangle[r][c] += right
    c += 1
  r -= 1

<< triangle[0][0]

## expect stdout
## 558
