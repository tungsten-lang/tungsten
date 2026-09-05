# Native construction + topology benchmark, with invariant checks.
# GEOMETRY_GRID_N is the cells per side; faces = 2*n*n.
# GEOMETRY_BENCH_MODE: input, mesh, or topology (default).
use core/geometry/mesh

size_text = env("GEOMETRY_GRID_N")
n = size_text == nil ? 100 : size_text.to_i
raise "grid size must be positive" if n <= 0
mode = env("GEOMETRY_BENCH_MODE")
vertices = []
y = 0
while y <= n
  x = 0
  while x <= n
    vertices.push([x, y])
    x += 1
  y += 1
faces = []
y = 0
while y < n
  x = 0
  while x < n
    a = y*(n + 1) + x
    b = a + 1
    c = a + n + 1
    d = c + 1
    faces.push([a, b, d])
    faces.push([a, d, c])
    x += 1
  y += 1
start = ccall("__w_clock_ms")
if mode != "input"
  mesh = TriangleMesh.new(vertices, faces)
  if mode != "mesh"
    topology = mesh.topology
    if topology.edge_count != 3*n*n + 2*n || topology.euler_characteristic != 1 || mesh.orientable_genus != 0
      raise "FAIL grid topology invariants"
elapsed = ccall("__w_clock_ms") - start
<< "faces=" + faces.size.to_s + " build_ms=" + elapsed.to_s
