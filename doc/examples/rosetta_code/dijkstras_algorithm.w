# Dijkstra's algorithm

-> dijkstra(n, adj, src)
  inf = 1000000000
  dist = []
  prev = []
  visited = []
  i = 0
  while i < n
    dist.push(inf)
    prev.push(-1)
    visited.push(false)
    i += 1
  dist[src] = 0
  step = 0
  while step < n
    u = -1
    best = inf
    v = 0
    while v < n
      if !visited[v] && dist[v] < best
        best = dist[v]
        u = v
      v += 1
    if u == -1
      break
    visited[u] = true
    edges = adj[u]
    e = 0
    while e < edges.size
      to = edges[e][0]
      w = edges[e][1]
      if dist[u] + w < dist[to]
        dist[to] = dist[u] + w
        prev[to] = u
      e += 1
    step += 1
  [dist, prev]

names = ["a", "b", "c", "d", "e", "f"]
adj = [
  [[1, 7], [2, 9], [5, 14]],
  [[2, 10], [3, 15]],
  [[3, 11], [5, 2]],
  [[4, 6]],
  [[5, 9]],
  []
]

res = dijkstra(6, adj, 0)
dist = res[0]
prev = res[1]

path = []
curr = 4
while curr != -1
  path.push(names[curr])
  curr = prev[curr]

<< "Distance a -> e: [dist[4]]"
joined = path.reverse.join(" -> ")
<< "Path: [joined]"

## expect stdout
## Distance a -> e: 26
## Path: a -> c -> d -> e
