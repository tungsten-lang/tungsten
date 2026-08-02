# Chart — one named smooth coordinate patch.
#
# Domains are optional caller metadata.  No inequality prover is implied: the
# chart records the coordinates and turns points into Expression bindings.

+ Chart
  -> new(names, domains = nil)
    if names.class_name != "Array" || names.size == 0
      raise "coordinate chart needs a nonempty Array of names"
    @names = []
    names.each -> (name)
      symbol = name.class_name == "Symbol" ? name : name.to_s.to_sym
      if @names.include?(symbol)
        raise "coordinate chart names must be unique"
      @names.push(symbol)
    @coordinates = Calculus.symbols(@names)
    if domains == nil
      @domains = []
      @names.size.times -> @domains.push(nil)
    else
      if domains.class_name != "Array" || domains.size != @names.size
        raise "coordinate chart domains must match the coordinate count"
      @domains = Geometry.copy_array(domains)

  -> names
    Geometry.copy_array(@names)

  -> coordinates
    Geometry.copy_array(@coordinates)

  -> coordinate(index)
    @coordinates[index]

  -> coordinate_name(index)
    @names[index]

  -> domain(index)
    @domains[index]

  -> domains
    Geometry.copy_array(@domains)

  -> dimension
    @names.size

  -> bindings(point)
    return point if point.class_name == "Hash"
    if point.class_name != "Array" || point.size != self.dimension
      raise "chart point must be an Array with one value per coordinate"
    out = {}
    i = 0
    while i < self.dimension
      out[@names[i]] = point[i]
      i += 1
    out

  -> to_s
    "Chart(" + @names.join(", ") + ")"

  -> inspect
    to_s
