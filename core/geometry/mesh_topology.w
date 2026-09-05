# TriangleMeshTopology — deterministic combinatorial surface diagnostics.
#
# Incidence uses flat u32 arrays: one corner per directed halfedge and CSR
# ranges for edges and vertices. Numeric edge keys are sorted lexicographically.
# Topology is independent of coordinates and is built lazily by TriangleMesh.
# It cannot certify geometric area, embedding, or outward orientation.
use core/integer

+ TriangleMeshTopology
  -> new(mesh)
    if mesh.class_name != "TriangleMesh"
      raise "triangle mesh topology must be built from a TriangleMesh"
    @vertex_count = mesh.vertex_count
    @face_count = mesh.face_count
    if @vertex_count > 4294967295 || @face_count > 1431655765
      raise "triangle mesh incidence exceeds u32 capacity"
    halfedge_count = 3*@face_count
    @corners = u32[halfedge_count]
    @vertex_offsets = u32[@vertex_count + 1]
    edge_index = {}
    keys = []
    h = 0
    while h < halfedge_count
      vertex = mesh.__face_corner(h / 3, h % 3)
      @corners[h] = vertex
      @vertex_offsets[vertex + 1] += 1
      h += 1
    h = 0
    while h < halfedge_count
      a = @corners[h]
      b = @corners[__next(h)]
      key = a < b ? a*@vertex_count + b : b*@vertex_count + a
      if !edge_index.has_key?(key)
        edge_index[key] = true
        keys.push(key)
      h += 1
    @edge_keys = keys.sort
    @edge_count = @edge_keys.size
    @edge_offsets = u32[@edge_count + 1]
    @halfedge_edges = u32[halfedge_count]
    edge = 0
    while edge < @edge_count
      edge_index[@edge_keys[edge]] = edge
      edge += 1
    h = 0
    while h < halfedge_count
      a = @corners[h]
      b = @corners[__next(h)]
      key = a < b ? a*@vertex_count + b : b*@vertex_count + a
      edge = edge_index[key]
      @halfedge_edges[h] = edge
      @edge_offsets[edge + 1] += 1
      h += 1
    edge = 0
    while edge < @edge_count
      @edge_offsets[edge + 1] += @edge_offsets[edge]
      edge += 1
    vertex = 0
    while vertex < @vertex_count
      @vertex_offsets[vertex + 1] += @vertex_offsets[vertex]
      vertex += 1
    @edge_halfedges = u32[halfedge_count]
    @vertex_halfedges = u32[halfedge_count]
    edge_cursor = u32[@edge_count]
    vertex_cursor = u32[@vertex_count]
    edge = 0
    while edge < @edge_count
      edge_cursor[edge] = @edge_offsets[edge]
      edge += 1
    vertex = 0
    while vertex < @vertex_count
      vertex_cursor[vertex] = @vertex_offsets[vertex]
      vertex += 1
    h = 0
    while h < halfedge_count
      edge = @halfedge_edges[h]
      vertex = @corners[h]
      @edge_halfedges[edge_cursor[edge]] = h
      edge_cursor[edge] += 1
      @vertex_halfedges[vertex_cursor[vertex]] = h
      vertex_cursor[vertex] += 1
      h += 1

    @boundary_ids = []
    @nonmanifold_ids = []
    @conflict_ids = []
    @duplicate_face_groups = []
    edge = 0
    while edge < @edge_count
      first = @edge_offsets[edge]
      count = @edge_offsets[edge + 1] - first
      if count == 1
        @boundary_ids.push(edge)
      elsif count > 2
        @nonmanifold_ids.push(edge)
      elsif __direction(@edge_halfedges[first]) == __direction(@edge_halfedges[first + 1])
        @conflict_ids.push(edge)
      # A duplicate is emitted only at its smallest edge. The ordinary
      # two-face case needs neither a face-key Hash nor a temporary group.
      high = @edge_keys[edge] % @vertex_count
      if count == 2
        left = @edge_halfedges[first]
        right = @edge_halfedges[first + 1]
        third = @corners[__previous(left)]
        if third > high && third == @corners[__previous(right)]
          @duplicate_face_groups.push([left / 3, right / 3])
      elsif count > 2
        groups = {}
        p = first
        while p < @edge_offsets[edge + 1]
          corner = @edge_halfedges[p]
          third = @corners[__previous(corner)]
          if third > high
            group = groups[third]
            group = [] if group == nil
            group.push(corner / 3)
            groups[third] = group
          p += 1
        groups.each -> (key, group)
          @duplicate_face_groups.push(group) if group.size > 1
      edge += 1
    @duplicate_face_groups = @duplicate_face_groups.sort -> (a, b) a[0] <=> b[0]

    @isolated_vertices = []
    @nonmanifold_vertices = []
    seen_faces = u32[@face_count]
    face_stack = u32[@face_count]
    vertex = 0
    while vertex < @vertex_count
      if @vertex_offsets[vertex] == @vertex_offsets[vertex + 1]
        @isolated_vertices.push(vertex)
      elsif !__manifold_vertex?(vertex, seen_faces, face_stack)
        @nonmanifold_vertices.push(vertex)
      vertex += 1

    # Vertex components include isolated vertices. Surface components omit
    # them; memberships use canonical IDs ordered by the smallest vertex.
    @vertex_component = u32[@vertex_count]
    @connected_component_count = 0
    @surface_component_count = 0
    vertex_stack = u32[@vertex_count]
    start = 0
    while start < @vertex_count
      if @vertex_component[start] == 0
        @connected_component_count += 1
        if @vertex_offsets[start] < @vertex_offsets[start + 1]
          @surface_component_count += 1
        @vertex_component[start] = @connected_component_count
        vertex_stack[0] = start
        size = 1
        while size > 0
          size -= 1
          current = vertex_stack[size]
          p = @vertex_offsets[current]
          while p < @vertex_offsets[current + 1]
            corner = @vertex_halfedges[p]
            k = 1
            while k <= 2
              neighbor = @corners[corner / 3 * 3 + (corner % 3 + k) % 3]
              if @vertex_component[neighbor] == 0
                @vertex_component[neighbor] = @connected_component_count
                vertex_stack[size] = neighbor
                size += 1
              k += 1
            p += 1
      start += 1
    @euler_characteristic = @vertex_count - @edge_count + @face_count

    @orientable = false
    @face_orientation = u8[@face_count]
    @boundary_loops = nil
    if combinatorial_manifold?
      @orientable = true
      start = 0
      while start < @face_count
        if @face_orientation[start] == 0
          @face_orientation[start] = 1
          face_stack[0] = start
          size = 1
          while size > 0
            size -= 1
            current = face_stack[size]
            h = 3*current
            while h < 3*current + 3
              edge = @halfedge_edges[h]
              first = @edge_offsets[edge]
              if @edge_offsets[edge + 1] - first == 2
                other = @edge_halfedges[first]
                other = @edge_halfedges[first + 1] if other == h
                neighbor = other / 3
                wanted = @face_orientation[current]
                wanted = 3 - wanted if __direction(h) == __direction(other)
                if @face_orientation[neighbor] == 0
                  @face_orientation[neighbor] = wanted
                  face_stack[size] = neighbor
                  size += 1
                elsif @face_orientation[neighbor] != wanted
                  @orientable = false
              h += 1
        start += 1

      # Boundary cycles start at their smallest vertex, with the smaller
      # adjacent vertex next. They do not repeat the closing vertex and are
      # canonical independently of the supplied face winding.
      next_a = u32[@vertex_count]
      next_b = u32[@vertex_count]
      boundary_seen = u8[@vertex_count]
      @boundary_ids.each -> (id)
        left = @edge_keys[id] / @vertex_count
        right = @edge_keys[id] % @vertex_count
        if next_a[left] == 0
          next_a[left] = right + 1
        else
          next_b[left] = right + 1
        if next_a[right] == 0
          next_a[right] = left + 1
        else
          next_b[right] = left + 1
      @boundary_loops = []
      start = 0
      while start < @vertex_count
        if next_a[start] != 0 && boundary_seen[start] == 0
          cycle = [start]
          boundary_seen[start] = 1
          previous = start
          current = next_a[start] < next_b[start] ? next_a[start] - 1 : next_b[start] - 1
          while current != start
            cycle.push(current)
            boundary_seen[current] = 1
            following = next_a[current] - 1
            following = next_b[current] - 1 if following == previous
            previous = current
            current = following
          @boundary_loops.push(cycle)
        start += 1

  # Unsupported helpers return scalar values or copies; scratch buffers in
  # the link test belong to the constructor, never to the public report.
  -> __next(h)
    h / 3 * 3 + (h % 3 + 1) % 3

  -> __previous(h)
    h / 3 * 3 + (h % 3 + 2) % 3

  -> __direction(h)
    @corners[h] < @corners[__next(h)] ? 1 : -1

  -> __manifold_vertex?(vertex, seen, stack)
    first = @vertex_offsets[vertex]
    stop = @vertex_offsets[vertex + 1]
    boundary_count = 0
    p = first
    while p < stop
      corner = @vertex_halfedges[p]
      side = 0
      while side < 2
        h = side == 0 ? corner : __previous(corner)
        edge = @halfedge_edges[h]
        count = @edge_offsets[edge + 1] - @edge_offsets[edge]
        return false if count > 2
        boundary_count += 1 if count == 1
        side += 1
      p += 1
    return false if boundary_count != 0 && boundary_count != 2
    stamp = vertex + 1
    start = @vertex_halfedges[first] / 3
    seen[start] = stamp
    stack[0] = start
    size = 1
    visited = 0
    while size > 0
      size -= 1
      face = stack[size]
      visited += 1
      corner = 3*face
      corner += 1 while @corners[corner] != vertex
      side = 0
      while side < 2
        h = side == 0 ? corner : __previous(corner)
        edge = @halfedge_edges[h]
        begin_at = @edge_offsets[edge]
        if @edge_offsets[edge + 1] - begin_at == 2
          other = @edge_halfedges[begin_at]
          other = @edge_halfedges[begin_at + 1] if other == h
          neighbor = other / 3
          if seen[neighbor] != stamp
            seen[neighbor] = stamp
            stack[size] = neighbor
            size += 1
        side += 1
    visited == stop - first

  -> __index(index, count, label)
    if !Integer.value?(index) || index < 0 || index >= count
      raise "triangle mesh topology " + label + " index is out of bounds"
    index

  -> __edges(ids)
    out = []
    ids.each -> (id) out.push(edge(id))
    out

  -> __groups(source)
    return nil if source == nil
    out = []
    source.each -> (group) out.push(group.dup)
    out

  -> vertex_count
    @vertex_count

  -> face_count
    @face_count

  -> edge_count
    @edge_count

  -> edge(index)
    index = __index(index, @edge_count, "edge")
    key = @edge_keys[index]
    [key / @vertex_count, key % @vertex_count]

  -> edges
    out = []
    i = 0
    while i < @edge_count
      out.push(edge(i))
      i += 1
    out

  -> edge_faces(index)
    index = __index(index, @edge_count, "edge")
    out = []
    p = @edge_offsets[index]
    while p < @edge_offsets[index + 1]
      out.push(@edge_halfedges[p] / 3)
      p += 1
    out

  -> vertex_faces(index)
    index = __index(index, @vertex_count, "vertex")
    out = []
    p = @vertex_offsets[index]
    while p < @vertex_offsets[index + 1]
      out.push(@vertex_halfedges[p] / 3)
      p += 1
    out

  -> vertex_neighbors(index)
    index = __index(index, @vertex_count, "vertex")
    found = {}
    p = @vertex_offsets[index]
    while p < @vertex_offsets[index + 1]
      h = @vertex_halfedges[p]
      found[@corners[__next(h)]] = true
      found[@corners[__previous(h)]] = true
      p += 1
    out = []
    found.each -> (vertex, present) out.push(vertex)
    out.sort

  -> face_neighbors(index)
    index = __index(index, @face_count, "face")
    found = {}
    h = 3*index
    while h < 3*index + 3
      edge_faces(@halfedge_edges[h]).each -> (face)
        found[face] = true if face != index
      h += 1
    out = []
    found.each -> (face, present) out.push(face)
    out.sort

  -> vertex_component(index)
    index = __index(index, @vertex_count, "vertex")
    @vertex_component[index] - 1

  -> face_component(index)
    index = __index(index, @face_count, "face")
    @vertex_component[@corners[3*index]] - 1

  -> vertex_components
    out = []
    @connected_component_count.times -> out.push([])
    vertex = 0
    while vertex < @vertex_count
      out[@vertex_component[vertex] - 1].push(vertex)
      vertex += 1
    out

  # Face lists in connected-component order, omitting isolated vertices.
  -> surface_components
    groups = []
    @connected_component_count.times -> groups.push([])
    face = 0
    while face < @face_count
      groups[face_component(face)].push(face)
      face += 1
    out = []
    groups.each -> (group) out.push(group) if group.size > 0
    out

  -> boundary_edges
    __edges(@boundary_ids)

  -> nonmanifold_edges
    __edges(@nonmanifold_ids)

  -> orientation_conflicts
    __edges(@conflict_ids)

  -> duplicate_face_groups
    __groups(@duplicate_face_groups)

  -> isolated_vertices
    @isolated_vertices.dup

  -> nonmanifold_vertices
    @nonmanifold_vertices.dup

  -> connected_component_count
    @connected_component_count

  -> surface_component_count
    @surface_component_count

  -> euler_characteristic
    @euler_characteristic

  -> boundary_loops
    __groups(@boundary_loops)

  -> boundary_component_count
    @boundary_loops == nil ? nil : @boundary_loops.size

  -> edge_manifold?
    @nonmanifold_ids.size == 0

  -> vertex_manifold?
    @nonmanifold_vertices.size == 0

  -> combinatorial_manifold?
    @face_count > 0 && @isolated_vertices.size == 0 && (
      @duplicate_face_groups.size == 0) && edge_manifold? && vertex_manifold?

  -> consistently_oriented?
    combinatorial_manifold? && @conflict_ids.size == 0

  -> closed?
    combinatorial_manifold? && @boundary_ids.size == 0

  -> orientable?
    @orientable

  # Face IDs to flip, using the lowest face in each dual component as an
  # unflipped seed. Nil means no orientable manifold was certified.
  -> orientation_face_flips
    return nil if !@orientable
    out = []
    face = 0
    while face < @face_count
      out.push(face) if @face_orientation[face] == 2
      face += 1
    out

  # Total genus across compact orientable surface components, independent
  # of the input winding: chi = 2*C - 2*g - B.
  -> orientable_genus
    return nil if !@orientable
    numerator = 2*@surface_component_count - boundary_component_count - @euler_characteristic
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
      boundary_component_count: boundary_component_count,
      combinatorial_manifold: combinatorial_manifold?,
      consistently_oriented: consistently_oriented?,
      closed: closed?,
      orientable: orientable?,
      orientable_genus: orientable_genus
    }

  -> inspect
    "TriangleMeshTopology(V=" + @vertex_count.to_s + ", E=" + (
      @edge_count.to_s) + ", F=" + @face_count.to_s + ", chi=" + (
      @euler_characteristic.to_s) + ")"

  -> to_s
    inspect
