# Exact finite simple graphs and bounded complete-graph edge-color audits.

+ FiniteSimpleGraph
  -> new(adjacency)
    if adjacency.class_name != "Array" || adjacency.size == 0
      raise "finite simple graph needs a nonempty adjacency matrix"
    @order = adjacency.size
    @adjacency = []
    i = 0
    while i < @order
      row = adjacency[i]
      if row.class_name != "Array" || row.size != @order
        raise "finite simple graph adjacency matrix must be square"
      copy = []
      j = 0
      while j < @order
        bit = row[j]
        if !Combinatorics.integer?(bit) || (bit != 0 && bit != 1)
          raise "finite simple graph entries must be zero or one"
        if i == j && bit != 0
          raise "finite simple graph diagonal must be zero"
        copy.push(bit)
        j += 1
      @adjacency.push(copy)
      i += 1
    i = 0
    while i < @order
      j = i + 1
      while j < @order
        if @adjacency[i][j] != @adjacency[j][i]
          raise "finite simple graph adjacency matrix must be symmetric"
        j += 1
      i += 1

  -> order
    @order

  -> size
    @order

  -> adjacency_matrix
    Combinatorics.copy_matrix(@adjacency)

  -> valid_vertex?(vertex)
    (Combinatorics.integer?(vertex) && vertex >= 0 && vertex < @order)

  -> adjacent?(left, right)
    if !valid_vertex?(left) || !valid_vertex?(right)
      raise "graph vertex is out of range"
    @adjacency[left][right] == 1

  -> neighbors(vertex)
    raise "graph vertex is out of range" if !valid_vertex?(vertex)
    out = []
    candidate = 0
    while candidate < @order
      out.push(candidate) if @adjacency[vertex][candidate] == 1
      candidate += 1
    out

  -> degree(vertex, active = nil)
    raise "graph vertex is out of range" if !valid_vertex?(vertex)
    if active != nil && active.size != @order
      raise "active vertex mask has the wrong size"
    count = 0
    candidate = 0
    while candidate < @order
      enabled = active == nil || active[candidate]
      count += 1 if enabled && @adjacency[vertex][candidate] == 1
      candidate += 1
    count

  -> edge_count
    total = 0
    left = 0
    while left < @order
      right = left + 1
      while right < @order
        total += 1 if @adjacency[left][right] == 1
        right += 1
      left += 1
    total

  -> connected?
    seen = []
    @order.times -> seen.push(false)
    seen[0] = true
    queue = [0]
    cursor = 0
    while cursor < queue.size
      vertex = queue[cursor]
      candidate = 0
      while candidate < @order
        if @adjacency[vertex][candidate] == 1 && !seen[candidate]
          seen[candidate] = true
          queue.push(candidate)
        candidate += 1
      cursor += 1
    seen.each -> (visited)
      return false if !visited
    true

  -> bipartite?
    colors = []
    @order.times -> colors.push(-1)
    seed = 0
    while seed < @order
      if colors[seed] == -1
        colors[seed] = 0
        queue = [seed]
        cursor = 0
        while cursor < queue.size
          vertex = queue[cursor]
          candidate = 0
          while candidate < @order
            if @adjacency[vertex][candidate] == 1
              if colors[candidate] == -1
                colors[candidate] = 1 - colors[vertex]
                queue.push(candidate)
              elsif colors[candidate] == colors[vertex]
                return false
            candidate += 1
          cursor += 1
      seed += 1
    true

  -> acyclic?
    seen = []
    @order.times -> seen.push(false)
    seed = 0
    while seed < @order
      if !seen[seed]
        seen[seed] = true
        queue = [[seed, -1]]
        cursor = 0
        while cursor < queue.size
          vertex = queue[cursor][0]
          parent = queue[cursor][1]
          candidate = 0
          while candidate < @order
            if @adjacency[vertex][candidate] == 1
              if !seen[candidate]
                seen[candidate] = true
                queue.push([candidate, vertex])
              elsif candidate != parent
                return false
            candidate += 1
          cursor += 1
      seed += 1
    true

  -> triangle
    left = 0
    while left < @order
      middle = left + 1
      while middle < @order
        if @adjacency[left][middle] == 1
          right = middle + 1
          while right < @order
            if (@adjacency[left][right] == 1 &&
                @adjacency[middle][right] == 1)
              return [left, middle, right]
            right += 1
        middle += 1
      left += 1
    nil

  -> triangle_free?
    triangle == nil

  -> degeneracy_certificate
    active = []
    @order.times -> active.push(true)
    ordering = []
    witness = []
    claimed = 0
    remaining = @order
    while remaining > 0
      selected = -1
      selected_degree = @order + 1
      vertex = 0
      while vertex < @order
        if active[vertex]
          value = degree(vertex, active)
          if value < selected_degree
            selected = vertex
            selected_degree = value
        vertex += 1
      if selected_degree > claimed
        claimed = selected_degree
        witness = []
        vertex = 0
        while vertex < @order
          witness.push(vertex) if active[vertex]
          vertex += 1
      ordering.push(selected)
      active[selected] = false
      remaining -= 1
    GraphDegeneracyCertificate.new(self, claimed, ordering, witness)

  -> degeneracy
    degeneracy_certificate.claimed_degeneracy

  -> degeneracy_ordering
    degeneracy_certificate.ordering

  -> proof_kind
    :exact_finite_simple_graph


+ GraphDegeneracyCertificate
  -> new(@graph, @claimed_degeneracy, ordering, witness_vertices)
    @ordering = Combinatorics.copy_vector(ordering)
    @witness_vertices = Combinatorics.copy_vector(witness_vertices)

  -> graph
    @graph

  -> claimed_degeneracy
    @claimed_degeneracy

  -> ordering
    Combinatorics.copy_vector(@ordering)

  -> witness_vertices
    Combinatorics.copy_vector(@witness_vertices)

  -> proof_kind
    :exact_degeneracy_upper_order_and_lower_core

  -> verified?
    if (!Combinatorics.integer?(@claimed_degeneracy) ||
        @claimed_degeneracy < 0 || @ordering.size != @graph.order ||
        @witness_vertices.size == 0)
      return false
    seen = []
    active = []
    @graph.order.times ->
      seen.push(false)
      active.push(true)
    maximum = 0
    @ordering.each -> (vertex)
      return false if !@graph.valid_vertex?(vertex) || seen[vertex]
      value = @graph.degree(vertex, active)
      maximum = value if value > maximum
      seen[vertex] = true
      active[vertex] = false
    return false if maximum > @claimed_degeneracy
    witness_mask = []
    @graph.order.times -> witness_mask.push(false)
    @witness_vertices.each -> (vertex)
      return false if !@graph.valid_vertex?(vertex) || witness_mask[vertex]
      witness_mask[vertex] = true
    @witness_vertices.each -> (vertex)
      return false if @graph.degree(vertex, witness_mask) < @claimed_degeneracy
    true


+ CompleteGraphEdgeColoring
  -> new(colors, color_count = nil)
    if colors.class_name != "Array" || colors.size < 2
      raise "complete-graph edge coloring needs at least two vertices"
    @order = colors.size
    @colors = []
    inferred = 0
    i = 0
    while i < @order
      row = colors[i]
      if (row.class_name != "Array" || row.size != @order ||
          row[i] != -1)
        raise "edge-color matrix has the wrong shape"
      copy = []
      j = 0
      while j < @order
        color = row[j]
        if i != j
          if !Combinatorics.integer?(color) || color < 0
            raise "off-diagonal colors must be nonnegative integers"
          inferred = color + 1 if color + 1 > inferred
        copy.push(color)
        j += 1
      @colors.push(copy)
      i += 1
    i = 0
    while i < @order
      j = i + 1
      while j < @order
        if @colors[i][j] != @colors[j][i]
          raise "edge colors must be symmetric"
        j += 1
      i += 1
    @color_count = color_count == nil ? inferred : color_count
    if !Combinatorics.integer?(@color_count) || @color_count < inferred
      raise "color count does not cover the edge colors"

  -> order
    @order

  -> color_count
    @color_count

  -> color(left, right)
    @colors[left][right]

  -> monochromatic_triangle
    left = 0
    while left < @order
      middle = left + 1
      while middle < @order
        right = middle + 1
        while right < @order
          value = @colors[left][middle]
          if (@colors[left][right] == value &&
              @colors[middle][right] == value)
            return [left, middle, right, value]
          right += 1
        middle += 1
      left += 1
    nil

  -> triangle_free?
    monochromatic_triangle == nil

  -> proof_kind
    :exact_complete_graph_edge_coloring_replay


+ TriangleRamseyAudit
  -> .edge_count(vertices)
    Combinatorics.require_nonnegative_integer(vertices, "vertices")
    vertices * (vertices - 1) / 2

  -> .coloring_from_code(vertices, color_count, code)
    if (!Combinatorics.integer?(vertices) || vertices < 2 ||
        !Combinatorics.integer?(color_count) || color_count < 1 ||
        !Combinatorics.integer?(code) || code < 0)
      raise "invalid bounded Ramsey coloring dimensions"
    colors = []
    vertices.times ->
      row = []
      vertices.times -> row.push(-1)
      colors.push(row)
    rest = code
    left = 0
    while left < vertices
      right = left + 1
      while right < vertices
        color = rest % color_count
        rest = rest / color_count
        colors[left][right] = color
        colors[right][left] = color
        right += 1
      left += 1
    CompleteGraphEdgeColoring.new(colors, color_count)

  -> .every_coloring_forces_triangle?(vertices, color_count,
                                      coloring_limit = 16_777_216)
    if (!Combinatorics.integer?(vertices) || vertices < 2 ||
        !Combinatorics.integer?(color_count) || color_count < 1)
      raise "invalid bounded Ramsey coloring dimensions"
    total = color_count ** TriangleRamseyAudit.edge_count(vertices)
    if total > coloring_limit
      raise "Ramsey coloring exhaustion exceeds its explicit limit"
    code = 0
    while code < total
      coloring = TriangleRamseyAudit.coloring_from_code(
        vertices, color_count, code)
      return [false, code + 1] if coloring.triangle_free?
      code += 1
    [true, total]
