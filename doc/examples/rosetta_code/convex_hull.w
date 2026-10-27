# Convex hull

-> cross(o, a, b)
  (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

-> sort_points(pts)
  n = pts.size
  i = 1
  while i < n
    key = pts[i]
    j = i - 1
    while j >= 0 && (pts[j][0] > key[0] || (pts[j][0] == key[0] && pts[j][1] > key[1]))
      pts[j + 1] = pts[j]
      j -= 1
    pts[j + 1] = key
    i += 1
  pts

-> convex_hull(pts)
  pts = sort_points(pts)
  lower = []
  i = 0
  while i < pts.size
    p = pts[i]
    while lower.size >= 2 && cross(lower[lower.size - 2], lower[lower.size - 1], p) <= 0
      lower.pop
    lower.push(p)
    i += 1
  upper = []
  i = pts.size - 1
  while i >= 0
    p = pts[i]
    while upper.size >= 2 && cross(upper[upper.size - 2], upper[upper.size - 1], p) <= 0
      upper.pop
    upper.push(p)
    i -= 1
  lower.pop
  upper.pop
  i = 0
  while i < upper.size
    lower.push(upper[i])
    i += 1
  lower

points = [
  [16, 3], [12, 17], [0, 6], [-4, -6], [16, 6],
  [16, -7], [16, -3], [17, -4], [5, 19], [19, -8],
  [3, 16], [12, 13], [3, -4], [17, 5], [-3, 15],
  [-3, -9], [0, 11], [-9, -3], [-4, -2], [12, 10]
]

hull = convex_hull(points)
hull.each -> (pt)
  << "([pt[0]], [pt[1]])"

## expect stdout
## (-9, -3)
## (-3, -9)
## (19, -8)
## (17, 5)
## (12, 17)
## (5, 19)
## (-3, 15)
