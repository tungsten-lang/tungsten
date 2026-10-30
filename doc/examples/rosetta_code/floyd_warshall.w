# Floyd-Warshall algorithm

inf = 1000000
n = 4
dist = [
  [0, inf, -2, inf],
  [4, 0, 3, inf],
  [inf, inf, 0, 2],
  [inf, -1, inf, 0]
]

k = 0
while k < n
  i = 0
  while i < n
    j = 0
    while j < n
      if dist[i][k] < inf && dist[k][j] < inf
        if dist[i][k] + dist[k][j] < dist[i][j]
          dist[i][j] = dist[i][k] + dist[k][j]
      j += 1
    i += 1
  k += 1

dist.each -> (row)
  << row.join(" ")

## expect stdout
## 0 -1 -2 0
## 4 0 2 4
## 5 1 0 2
## 3 -1 1 0
