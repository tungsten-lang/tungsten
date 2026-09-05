# Validated triangle-mesh topology for two- and three-dimensional real points.
#
# TriangleMesh owns only mesh connectivity and immutable-by-interface input
# snapshots.  Dense fields remain Tensor's responsibility, assembled operators
# remain Sparse's responsibility, and rendering remains Plot/Plot3D's
# responsibility. Construction validates point/face representation and finite
# Float coordinates; incidence is computed and cached on the first topology
# query. The topology report certifies combinatorial incidence;
# it does not certify a non-self-intersecting embedding or nonzero geometric
# area for faces whose three vertex indices are distinct.

use core/numeric/float
use core/numeric/rational
use core/geometry/mesh_topology

+ TriangleMesh
  # Immediate integers copy without allocation. Heap BigInt is copied through
  # decimal text because identity arithmetic and Array#dup can share limbs.
  # Operational validation happens before any arithmetic or payload access.
  -> .__copy_integer(value)
    if !Integer.value?(value)
      raise "triangle mesh coordinates must be operational real values"
    Integer.copy_value(value)

  -> .__copy_coordinate(value)
    name = value.class_name
    if name == "Float"
      operational = false
      nonfinite = true
      begin
        text = value.to_s
        operational = text != nil && text.class_name == "String"
        nonfinite = value.nan? || value.infinite? if operational
      rescue error
        raise "triangle mesh coordinates must be operational real values"
      if !operational
        raise "triangle mesh coordinates must be operational real values"
      if nonfinite
        raise "triangle mesh Float coordinates must be finite"
      return value
    if Integer.value?(value)
      return TriangleMesh.__copy_integer(value)
    if name == "Rational"
      numerator = TriangleMesh.__copy_integer(value.numerator)
      denominator = TriangleMesh.__copy_integer(value.denominator)
      return Rational.new(numerator, denominator)
    raise "triangle mesh coordinates must be Integer, Rational, or finite Float values"

  -> new(vertices, faces)
    if vertices.class_name != "Array" || vertices.size == 0
      raise "triangle mesh needs a nonempty Array of vertices"
    if faces.class_name != "Array"
      raise "triangle mesh faces must be an Array"

    first = vertices[0]
    if first.class_name != "Array" || (first.size != 2 && first.size != 3)
      raise "triangle mesh vertices must be 2D or 3D coordinate Arrays"
    @dimension = first.size
    @vertices = []
    vertices.each -> (point)
      if point.class_name != "Array" || point.size != @dimension
        raise "triangle mesh vertices must have one consistent dimension"
      copy = []
      point.each -> (coordinate)
        copy.push(TriangleMesh.__copy_coordinate(coordinate))
      @vertices.push(copy)

    @faces = []
    faces.each -> (face)
      if face.class_name != "Array" || face.size != 3
        raise "triangle mesh faces must contain exactly three vertex indices"
      copy = []
      face.each -> (index)
        if !Integer.value?(index)
          raise "triangle mesh face indices must be Integer values"
        if index < 0 || index >= @vertices.size
          raise "triangle mesh face index is out of bounds"
        copy.push(index + 0)
      if copy[0] == copy[1] || copy[1] == copy[2] || copy[2] == copy[0]
        raise "triangle mesh faces must use three distinct vertex indices"
      @faces.push(copy)

    @topology = nil

  -> __canonical_accessor_index(index, count, label)
    if !Integer.value?(index)
      raise "triangle mesh " + label + " index must be an Integer value"
    if index < 0 || index >= count
      raise "triangle mesh " + label + " index is out of bounds"
    index

  # Internal scalar read used during incidence construction, with no mutable
  # Array or numeric payload escaping. All callers supply validated indices.
  -> __face_corner(face, corner)
    @faces[face][corner]

  -> dimension
    @dimension

  -> vertex_count
    @vertices.size

  -> face_count
    @faces.size

  -> vertex(index)
    index = __canonical_accessor_index(
      index, @vertices.size, "vertex")
    out = []
    @vertices[index].each -> (coordinate)
      out.push(TriangleMesh.__copy_coordinate(coordinate))
    out

  -> face(index)
    index = __canonical_accessor_index(index, @faces.size, "face")
    @faces[index].dup

  -> vertices
    out = []
    index = 0
    while index < @vertices.size
      out.push(vertex(index))
      index += 1
    out

  -> faces
    out = []
    @faces.each -> (face) out.push(face.dup)
    out

  -> topology
    @topology = TriangleMeshTopology.new(self) if @topology == nil
    @topology

  -> edges
    topology.edges

  -> boundary_edges
    topology.boundary_edges

  -> combinatorial_manifold?
    topology.combinatorial_manifold?

  -> consistently_oriented?
    topology.consistently_oriented?

  -> closed?
    topology.closed?

  -> orientable_genus
    topology.orientable_genus

  -> orientable?
    topology.orientable?

  # A new mesh; the original winding and snapshots remain intact.
  -> reoriented
    flips = topology.orientation_face_flips
    raise "mesh has no certified orientable surface" if flips == nil
    oriented = faces
    flips.each -> (face)
      old = oriented[face][1]
      oriented[face][1] = oriented[face][2]
      oriented[face][2] = old
    TriangleMesh.new(vertices, oriented)

  -> inspect
    "TriangleMesh(vertices=" + vertex_count.to_s + ", faces=" + (
      face_count.to_s) + ", dimension=" + @dimension.to_s + ")"

  -> to_s
    inspect

+ Geometry
  -> .triangle_mesh(vertices, faces)
    TriangleMesh.new(vertices, faces)
