# Focused combinatorial triangle-mesh regressions.
# Run in both engines:
#   bin/tungsten run spec/core/geometry_mesh_spec.w
#   bin/tungsten compile spec/core/geometry_mesh_spec.w \
#     --out /tmp/geometry-mesh-spec
#   /tmp/geometry-mesh-spec

use core/geometry/mesh

-> mesh_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

tetra_vertices = [
  [0, 0, 0],
  [1, 0, 0],
  [0, 1, 0],
  [0, 0, 1]
]
tetra_faces = [
  [0, 2, 1],
  [0, 1, 3],
  [1, 2, 3],
  [2, 0, 3]
]
tetra = Geometry.triangle_mesh(tetra_vertices, tetra_faces)
mesh_check("tetra.dimension", tetra.dimension == 3)
mesh_check("tetra.counts",
           tetra.vertex_count == 4 && tetra.face_count == 4 &&
           tetra.topology.edge_count == 6)
mesh_check("tetra.euler", tetra.topology.euler_characteristic == 2)
mesh_check("tetra.closed_manifold", tetra.closed? && tetra.combinatorial_manifold?)
mesh_check("tetra.orientation", tetra.consistently_oriented?)
mesh_check("tetra.genus", tetra.orientable_genus == 0)
mesh_check("tetra.boundary", tetra.boundary_edges.size == 0 &&
           tetra.topology.boundary_component_count == 0)

# Accessors return copies: caller mutation cannot alter certified incidence.
external_vertices = tetra.vertices
external_faces = tetra.faces
external_edges = tetra.edges
external_vertices[0][0] = 99
external_faces[0][0] = 3
external_edges[0][0] = 99
mesh_check("snapshot.vertices", tetra.vertex(0)[0] == 0)
mesh_check("snapshot.faces", tetra.face(0)[0] == 0)
mesh_check("snapshot.edges", tetra.edges[0][0] == 0)

mutable_integer = 281474976710656
owned_integer_mesh = TriangleMesh.new(
  [[mutable_integer, 0], [0, 0], [0, 1]], [[0, 1, 2]])
mutable_integer.neg!
mesh_check("snapshot.bigint_source", owned_integer_mesh.vertex(0)[0] > 0)
exposed_integer = owned_integer_mesh.vertex(0)[0]
exposed_integer.neg!
mesh_check("snapshot.bigint_accessor", owned_integer_mesh.vertex(0)[0] > 0)

mutable_rational = Rational.new(281474976710656, 3)
owned_rational_mesh = TriangleMesh.new(
  [[mutable_rational, 0], [0, 0], [0, 1]], [[0, 1, 2]])
mutable_rational.numerator.neg!
mesh_check("snapshot.rational_source", owned_rational_mesh.vertex(0)[0] > 0)
exposed_rational = owned_rational_mesh.vertex(0)[0]
exposed_rational.numerator.neg!
mesh_check("snapshot.rational_accessor", owned_rational_mesh.vertex(0)[0] > 0)

disk = TriangleMesh.new(
  [[0, 0], [1, 0], [1, 1], [0, 1]],
  [[0, 1, 2], [0, 2, 3]])
mesh_check("disk.manifold", disk.combinatorial_manifold?)
mesh_check("disk.open", !disk.closed?)
mesh_check("disk.boundary_edges", disk.boundary_edges.size == 4)
mesh_check("disk.boundary_component", disk.topology.boundary_component_count == 1)
mesh_check("disk.euler", disk.topology.euler_characteristic == 1)
mesh_check("disk.genus", disk.orientable_genus == 0)

annulus = TriangleMesh.new(
  [[0, 0], [3, 0], [3, 3], [0, 3],
   [1, 1], [2, 1], [2, 2], [1, 2]],
  [[0, 1, 5], [0, 5, 4], [1, 2, 6], [1, 6, 5],
   [2, 3, 7], [2, 7, 6], [3, 0, 4], [3, 4, 7]])
mesh_check("annulus.boundaries", annulus.topology.boundary_component_count == 2)
mesh_check("annulus.euler_genus",
           annulus.topology.euler_characteristic == 0 &&
           annulus.orientable_genus == 0)

# A 3x3 periodic grid is an abstract triangulated torus. Coordinates are only
# labels here: TriangleMeshTopology certifies incidence, not the embedding.
torus_vertices = [
  [0, 0], [0, 1], [0, 2],
  [1, 0], [1, 1], [1, 2],
  [2, 0], [2, 1], [2, 2]
]
torus_faces = [
  [0, 3, 4], [0, 4, 1], [1, 4, 5], [1, 5, 2],
  [2, 5, 3], [2, 3, 0], [3, 6, 7], [3, 7, 4],
  [4, 7, 8], [4, 8, 5], [5, 8, 6], [5, 6, 3],
  [6, 0, 1], [6, 1, 7], [7, 1, 2], [7, 2, 8],
  [8, 2, 0], [8, 0, 6]
]
torus = TriangleMesh.new(torus_vertices, torus_faces)
mesh_check("torus.closed", torus.closed? && torus.consistently_oriented?)
mesh_check("torus.euler_genus",
           torus.topology.euler_characteristic == 0 &&
           torus.orientable_genus == 1)

permuted_tetra = TriangleMesh.new(tetra_vertices, [
  [0, 3, 2], [2, 3, 1], [1, 3, 0], [2, 1, 0]
])
mesh_check("determinism.face_order_and_cycles",
           permuted_tetra.edges == tetra.edges &&
           permuted_tetra.topology.summary == tetra.topology.summary)

flipped = TriangleMesh.new(tetra_vertices, [
  [0, 1, 2],
  [0, 1, 3],
  [1, 2, 3],
  [2, 0, 3]
])
mesh_check("orientation.conflict", !flipped.consistently_oriented? &&
           flipped.topology.orientation_conflicts.size == 3)
mesh_check("orientation.genus_withheld", flipped.orientable_genus == nil)

# Three triangles sharing one edge violate the at-most-two-face condition.
nonmanifold_edge = TriangleMesh.new(
  [[0, 0, 0], [1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1]],
  [[0, 1, 2], [1, 0, 3], [0, 1, 4]])
mesh_check("edge.nonmanifold", !nonmanifold_edge.combinatorial_manifold? &&
           nonmanifold_edge.topology.nonmanifold_edges == [[0, 1]])

# Two fans meeting only at vertex zero have manifold edges but a disconnected
# vertex link.  The link audit must catch this bow tie.
bow_tie = TriangleMesh.new(
  [[0, 0], [1, 0], [0, 1], [-1, 0], [0, -1]],
  [[0, 1, 2], [0, 3, 4]])
mesh_check("vertex.bow_tie", bow_tie.topology.edge_manifold? &&
           !bow_tie.topology.vertex_manifold? &&
           bow_tie.topology.nonmanifold_vertices == [0])

duplicate = TriangleMesh.new(
  [[0, 0], [1, 0], [0, 1]],
  [[0, 1, 2], [2, 1, 0]])
mesh_check("face.duplicate", !duplicate.combinatorial_manifold? &&
           duplicate.topology.duplicate_face_groups == [[0, 1]])

with_isolate = TriangleMesh.new(
  [[0, 0], [1, 0], [0, 1], [4, 4]], [[0, 1, 2]])
mesh_check("vertex.isolated", !with_isolate.combinatorial_manifold? &&
           with_isolate.topology.isolated_vertices == [3] &&
           with_isolate.topology.connected_component_count == 2 &&
           with_isolate.topology.surface_component_count == 1)

bad_face_shape = false
begin
  TriangleMesh.new([[0, 0], [1, 0], [0, 1]], [[0, 1]])
rescue error
  bad_face_shape = error.to_s.include?("exactly three")
mesh_check("validation.face_shape", bad_face_shape)

repeated_index = false
begin
  TriangleMesh.new([[0, 0], [1, 0], [0, 1]], [[0, 1, 1]])
rescue error
  repeated_index = error.to_s.include?("distinct")
mesh_check("validation.distinct_indices", repeated_index)

nonfinite_rejected = true
[Math.sqrt(~-1.0), Math.exp(~10000.0)].each -> (coordinate)
  rejected = false
  begin
    TriangleMesh.new([[coordinate, ~0.0], [~1.0, ~0.0], [~0.0, ~1.0]],
                     [[0, 1, 2]])
  rescue error
    rejected = error.to_s.include?("finite")
  nonfinite_rejected = false if !rejected
mesh_check("validation.nonfinite", nonfinite_rejected)

scaffold_coordinate_rejected = true
[Integer.new, Int.new, BigInt.new, Float.new, Decimal.new].each -> (coordinate)
  begin
    TriangleMesh.new([[coordinate, 0], [1, 0], [0, 1]], [[0, 1, 2]])
    scaffold_coordinate_rejected = false
  rescue error
    scaffold_coordinate_rejected = false if !error.to_s.include?("coordinates")
mesh_check("validation.coordinate_scaffolds", scaffold_coordinate_rejected)

scaffold_index_rejected = true
[Integer.new, Int.new, BigInt.new].each -> (index)
  rejected = false
  begin
    TriangleMesh.new([[0, 0], [1, 0], [0, 1]], [[index, 1, 2]])
  rescue error
    rejected = true
  scaffold_index_rejected = false if !rejected
mesh_check("validation.index_scaffolds", scaffold_index_rejected)

noninteger_index_rejected = true
[Rational.new(1, 1), Decimal.new, ~1.0].each -> (index)
  begin
    TriangleMesh.new([[0, 0], [1, 0], [0, 1]], [[0, index, 2]])
    noninteger_index_rejected = false
  rescue error
    noninteger_index_rejected = false if !error.to_s.include?("Integer values")
mesh_check("validation.noninteger_indices", noninteger_index_rejected)

invalid_vertex_accessor_rejected = true
[-1, tetra.vertex_count, Rational.new(0, 1)].each -> (index)
  begin
    tetra.vertex(index)
    invalid_vertex_accessor_rejected = false
  rescue error
    invalid_vertex_accessor_rejected = false if !error.to_s.include?(
      "vertex index")
mesh_check("validation.vertex_accessor_indices",
           invalid_vertex_accessor_rejected)

invalid_face_accessor_rejected = true
[-1, tetra.face_count, ~0.0].each -> (index)
  begin
    tetra.face(index)
    invalid_face_accessor_rejected = false
  rescue error
    invalid_face_accessor_rejected = false if !error.to_s.include?(
      "face index")
mesh_check("validation.face_accessor_indices", invalid_face_accessor_rejected)

<< "geometry_mesh_spec: all checks passed"
