# Shoelace formula for polygonal area

-> polygon_area_twice(pts)
  n = pts.size
  sum = 0
  i = 0
  while i < n
    j = (i + 1) % n
    sum += pts[i][0] * pts[j][1] - pts[j][0] * pts[i][1]
    i += 1
  if sum < 0
    -sum
  else
    sum

pts = [[3, 4], [5, 11], [12, 8], [9, 5], [5, 6]]
twice = polygon_area_twice(pts)
<< "Area = [twice / 2]"

## expect stdout
## Area = 30
