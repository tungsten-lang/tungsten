# Validated triangle-mesh topology for two- and three-dimensional real points.
#
# TriangleMesh owns only mesh connectivity and immutable-by-interface input
# snapshots.  Dense fields remain Tensor's responsibility, assembled operators
# remain Sparse's responsibility, and rendering remains Plot/Plot3D's
# responsibility.  Construction validates point/face representation and finite
# Float coordinates.  The topology report certifies combinatorial incidence;
# it does not certify a non-self-intersecting embedding or nonzero geometric
# area for faces whose three vertex indices are distinct.

use core/numeric/float
use core/numeric/rational

+ TriangleMesh
  # Copy exact integer storage through decimal text.  Heap BigInt supports
  # explicit in-place sign mutation, so arithmetic identity operations and
  # Array#dup are not ownership boundaries.  The round trip both validates a
  # live numeric payload (rejecting callable class scaffolds such as
  # Integer.new/BigInt.new) and creates independent limb storage.
  -> .__copy_integer(value)
    text = nil
    begin
      text = value.to_s
    rescue error
      raise "triangle mesh coordinates must be operational real values"
    if text == nil || text.class_name != "String"
      raise "triangle mesh coordinates must be operational real values"
    copy = text.to_i
    if copy != value
      raise "triangle mesh coordinates must be operational real values"
    copy

  -> .__copy_coordinate(value)
    name = value.class_name
    if name == "Float"
      operational = false
      nonfinite = true
      begin
        text = value.to_s
        operational = text != nil && text.class_name == "String"
        nonfinite = value.nan? || value.infinite?
      rescue error
        raise "triangle mesh coordinates must be operational real values"
      if !operational
        raise "triangle mesh coordinates must be operational real values"
      if nonfinite
        raise "triangle mesh Float coordinates must be finite"
      return value
    if name == "Integer" || name == "BigInt"
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
    @valid_vertex_indices = {}
    @vertices.size.times -> (index) @valid_vertex_indices[index] = index
    faces.each -> (face)
      if face.class_name != "Array" || face.size != 3
        raise "triangle mesh faces must contain exactly three vertex indices"
      copy = []
      face.each -> (index)
        name = index.class_name
        if name != "Integer" && name != "BigInt"
          raise "triangle mesh face indices must be Integer values"
        canonical = @valid_vertex_indices[index]
        if canonical == nil
          raise "triangle mesh face index is out of bounds"
        copy.push(canonical)
      if copy[0] == copy[1] || copy[1] == copy[2] || copy[2] == copy[0]
        raise "triangle mesh faces must use three distinct vertex indices"
      @faces.push(copy)

    @valid_face_indices = {}
    @faces.size.times -> (index) @valid_face_indices[index] = index

    @topology = TriangleMeshTopology.new(self)

  -> __canonical_accessor_index(index, valid_indices, label)
    name = index.class_name
    if name != "Integer" && name != "BigInt"
      raise "triangle mesh " + label + " index must be an Integer value"
    canonical = nil
    begin
      canonical = valid_indices[index]
    rescue error
      canonical = nil
    if canonical == nil
      raise "triangle mesh " + label + " index is out of bounds"
    canonical

  -> dimension
    @dimension

  -> vertex_count
    @vertices.size

  -> face_count
    @faces.size

  -> vertex(index)
    index = __canonical_accessor_index(
      index, @valid_vertex_indices, "vertex")
    out = []
    @vertices[index].each -> (coordinate)
      out.push(TriangleMesh.__copy_coordinate(coordinate))
    out

  -> face(index)
    index = __canonical_accessor_index(index, @valid_face_indices, "face")
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
    @topology

  -> edges
    @topology.edges

  -> boundary_edges
    @topology.boundary_edges

  -> combinatorial_manifold?
    @topology.combinatorial_manifold?

  -> consistently_oriented?
    @topology.consistently_oriented?

  -> closed?
    @topology.closed?

  -> orientable_genus
    @topology.orientable_genus

  -> inspect
    "TriangleMesh(vertices=" + vertex_count.to_s + ", faces=" + (
      face_count.to_s) + ", dimension=" + @dimension.to_s + ")"

  -> to_s
    inspect


# Deterministic combinatorial diagnostics derived from a TriangleMesh.
#
# A vertex is combinatorially manifold exactly when its simplicial link is one
# connected cycle (interior) or one connected path (boundary).  This catches
# bow-tie vertices that edge-incidence checks alone miss.  Orientable genus is
# returned only when those link conditions, edge incidence, duplicate-face
# checks, and the supplied face winding all certify an orientable surface.
+ TriangleMeshTopology
  -> new(mesh)
    if mesh.class_name != "TriangleMesh"
      raise "triangle mesh topology must be built from a TriangleMesh"
    @vertex_count = mesh.vertex_count
    @face_count = mesh.face_count
    @faces = mesh.faces
    @vertex_faces = []
    @vertex_neighbors = []
    @vertex_count.times ->
      @vertex_faces.push([])
      @vertex_neighbors.push([])
    @edge_records = {}
    face_records = {}

    face_index = 0
    while face_index < @faces.size
      face = @faces[face_index]
      face.each -> (vertex) @vertex_faces[vertex].push(face_index)
      directed_edges = [
        [face[0], face[1]],
        [face[1], face[2]],
        [face[2], face[0]]
      ]
      directed_edges.each -> (directed)
        left = directed[0]
        right = directed[1]
        @vertex_neighbors[left].push(right)
        @vertex_neighbors[right].push(left)
        low = left < right ? left : right
        high = left < right ? right : left
        edge_key = low.to_s + ":" + high.to_s
        direction = left == low ? 1 : -1
        edge_record = @edge_records[edge_key]
        if edge_record == nil
          @edge_records[edge_key] = [
            low, high, [face_index], [direction]]
        else
          edge_record[2].push(face_index)
          edge_record[3].push(direction)
          @edge_records[edge_key] = edge_record

      canonical = face.sort
      face_key = canonical.join(":")
      group = face_records[face_key]
      if group == nil
        face_records[face_key] = [face_index]
      else
        group.push(face_index)
        face_records[face_key] = group
      face_index += 1

    @edges = []
    @boundary_edges = []
    @nonmanifold_edges = []
    @orientation_conflicts = []
    @edge_records.each -> (key, record)
      edge = [record[0], record[1]]
      @edges.push(edge)
      incidence_count = record[2].size
      if incidence_count == 1
        @boundary_edges.push(edge)
      elsif incidence_count > 2
        @nonmanifold_edges.push(edge)
      elsif record[3][0] == record[3][1]
        @orientation_conflicts.push(edge)
    @edges = __sorted_edges(@edges)
    @boundary_edges = __sorted_edges(@boundary_edges)
    @nonmanifold_edges = __sorted_edges(@nonmanifold_edges)
    @orientation_conflicts = __sorted_edges(@orientation_conflicts)
    @edge_count = @edges.size

    @duplicate_face_groups = []
    face_records.each -> (key, group)
      @duplicate_face_groups.push(group.dup) if group.size > 1
    @duplicate_face_groups = @duplicate_face_groups.sort -> (left, right)
      left[0] <=> right[0]

    @isolated_vertices = []
    vertex = 0
    while vertex < @vertex_count
      @isolated_vertices.push(vertex) if @vertex_faces[vertex].size == 0
      vertex += 1

    @nonmanifold_vertices = []
    vertex = 0
    while vertex < @vertex_count
      if @vertex_faces[vertex].size > 0 && !__manifold_vertex?(vertex)
        @nonmanifold_vertices.push(vertex)
      vertex += 1

    @connected_component_count = __count_vertex_components(false)
    @surface_component_count = __count_vertex_components(true)
    @euler_characteristic = @vertex_count - @edge_count + @face_count
    @boundary_component_count = nil
    if combinatorial_manifold?
      @boundary_component_count = __count_boundary_components

  # Tungsten currently has no enforceable private-helper declaration.  The
  # double-underscore methods below are read-only implementation details; all
  # construction-time mutations stay inline above and no mutating report
  # method is exposed.
  -> __sorted_edges(source)
    source.sort -> (left, right)
      if left[0] == right[0]
        left[1] <=> right[1]
      else
        left[0] <=> right[0]

  -> __manifold_vertex?(vertex)
    link_neighbors = {}
    link_degrees = {}
    @vertex_faces[vertex].each -> (face_index)
      face = @faces[face_index]
      others = []
      face.each -> (candidate)
        others.push(candidate) if candidate != vertex
      left_key = others[0].to_s
      right_key = others[1].to_s
      link_neighbors[left_key] = [] if link_neighbors[left_key] == nil
      link_neighbors[right_key] = [] if link_neighbors[right_key] == nil
      link_degrees[left_key] = 0 if link_degrees[left_key] == nil
      link_degrees[right_key] = 0 if link_degrees[right_key] == nil
      link_neighbors[left_key].push(others[1])
      link_neighbors[right_key].push(others[0])
      link_degrees[left_key] += 1
      link_degrees[right_key] += 1

    nodes = []
    link_neighbors.each -> (key, neighbors) nodes.push(key)
    return false if nodes.size == 0
    seen = {}
    stack = [nodes[0]]
    while stack.size > 0
      current_key = stack.pop
      if !seen.has_key?(current_key)
        seen[current_key] = true
        link_neighbors[current_key].each -> (neighbor)
          neighbor_key = neighbor.to_s
          stack.push(neighbor_key) if !seen.has_key?(neighbor_key)
    return false if seen.size != nodes.size

    degree_one = 0
    valid_degrees = true
    link_degrees.each -> (key, degree)
      degree_one += 1 if degree == 1
      valid_degrees = false if degree != 1 && degree != 2
    valid_degrees && (degree_one == 0 || degree_one == 2)

  -> __count_vertex_components(surface_only)
    visited = []
    @vertex_count.times -> visited.push(false)
    count = 0
    start = 0
    while start < @vertex_count
      eligible = !surface_only || @vertex_faces[start].size > 0
      if eligible && !visited[start]
        count += 1
        visited[start] = true
        stack = [start]
        while stack.size > 0
          current = stack.pop
          @vertex_neighbors[current].each -> (neighbor)
            if !visited[neighbor]
              visited[neighbor] = true
              stack.push(neighbor)
      start += 1
    count

  -> __count_boundary_components
    return 0 if @boundary_edges.size == 0
    adjacency = []
    @vertex_count.times -> adjacency.push([])
    @boundary_edges.each -> (edge)
      adjacency[edge[0]].push(edge[1])
      adjacency[edge[1]].push(edge[0])
    vertex = 0
    while vertex < @vertex_count
      if adjacency[vertex].size != 0 && adjacency[vertex].size != 2
        return nil
      vertex += 1
    visited = []
    @vertex_count.times -> visited.push(false)
    count = 0
    start = 0
    while start < @vertex_count
      if adjacency[start].size > 0 && !visited[start]
        count += 1
        visited[start] = true
        stack = [start]
        while stack.size > 0
          current = stack.pop
          adjacency[current].each -> (neighbor)
            if !visited[neighbor]
              visited[neighbor] = true
              stack.push(neighbor)
      start += 1
    count

  -> __copy_edges(source)
    out = []
    source.each -> (edge) out.push(edge.dup)
    out

  -> __copy_groups(source)
    out = []
    source.each -> (group) out.push(group.dup)
    out

  -> __copy_values(source)
    source.dup

  -> vertex_count
    @vertex_count

  -> face_count
    @face_count

  -> edge_count
    @edge_count

  -> edges
    __copy_edges(@edges)

  -> boundary_edges
    __copy_edges(@boundary_edges)

  -> nonmanifold_edges
    __copy_edges(@nonmanifold_edges)

  -> orientation_conflicts
    __copy_edges(@orientation_conflicts)

  -> duplicate_face_groups
    __copy_groups(@duplicate_face_groups)

  -> isolated_vertices
    __copy_values(@isolated_vertices)

  -> nonmanifold_vertices
    __copy_values(@nonmanifold_vertices)

  -> connected_component_count
    @connected_component_count

  -> surface_component_count
    @surface_component_count

  -> euler_characteristic
    @euler_characteristic

  -> boundary_component_count
    @boundary_component_count

  -> edge_manifold?
    @nonmanifold_edges.size == 0

  -> vertex_manifold?
    @nonmanifold_vertices.size == 0

  -> combinatorial_manifold?
    @face_count > 0 && @isolated_vertices.size == 0 && (
      @duplicate_face_groups.size == 0) && edge_manifold? && vertex_manifold?

  -> consistently_oriented?
    combinatorial_manifold? && @orientation_conflicts.size == 0

  -> closed?
    combinatorial_manifold? && @boundary_edges.size == 0

  # Total orientable genus across all surface components.  For a compact
  # orientable triangulated surface, chi = 2*C - 2*g - B.  Nil means the
  # incidence/winding preconditions do not certify that formula.
  -> orientable_genus
    return nil if !consistently_oriented?
    return nil if @boundary_component_count == nil
    numerator = 2*@surface_component_count - @boundary_component_count - (
      @euler_characteristic)
    return nil if numerator < 0 || numerator.odd?
    numerator / 2

  -> summary
    {
      vertex_count: @vertex_count,
      face_count: @face_count,
      edge_count: @edge_count,
      connected_component_count: @connected_component_count,
      surface_component_count: @surface_component_count,
      euler_characteristic: @euler_characteristic,
      boundary_component_count: @boundary_component_count,
      combinatorial_manifold: combinatorial_manifold?,
      consistently_oriented: consistently_oriented?,
      closed: closed?,
      orientable_genus: orientable_genus
    }

  -> inspect
    "TriangleMeshTopology(V=" + @vertex_count.to_s + ", E=" + (
      @edge_count.to_s) + ", F=" + @face_count.to_s + ", chi=" + (
      @euler_characteristic.to_s) + ")"

  -> to_s
    inspect


+ Geometry
  -> .triangle_mesh(vertices, faces)
    TriangleMesh.new(vertices, faces)
