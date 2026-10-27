# Topological sort

-> topo_sort(nodes, deps)
  visited = {}
  visiting = {}
  order = []

  -> visit(n, deps, visited, visiting, order)
    if visited[n] == true
      return
    if visiting[n] == true
      raise "cycle detected at [n]"
    visiting[n] = true
    dlist = deps[n]
    if dlist != nil
      i = 0
      while i < dlist.size
        dep = dlist[i]
        if dep != n
          visit(dep, deps, visited, visiting, order)
        i += 1
    visiting[n] = false
    visited[n] = true
    order.push(n)

  i = 0
  while i < nodes.size
    visit(nodes[i], deps, visited, visiting, order)
    i += 1
  order

nodes = ["lib_a", "lib_b", "lib_c", "lib_d", "app"]
deps = {
  "lib_a" => [],
  "lib_b" => ["lib_a"],
  "lib_c" => ["lib_a", "lib_b"],
  "lib_d" => ["lib_a"],
  "app"   => ["lib_c", "lib_d"]
}

<< topo_sort(nodes, deps).join(" -> ")

## expect stdout
## lib_a -> lib_b -> lib_c -> lib_d -> app
