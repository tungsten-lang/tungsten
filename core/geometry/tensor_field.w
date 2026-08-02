# TensorField — symbolic components plus explicit index-variance metadata.

+ TensorIndex
  -> new(@variance, @label = nil)
    if @variance != :covariant && @variance != :contravariant
      raise "tensor index variance must be covariant or contravariant"

  -> .covariant(label = nil)
    TensorIndex.new(:covariant, label)

  -> .contravariant(label = nil)
    TensorIndex.new(:contravariant, label)

  -> variance
    @variance

  -> label
    @label

  -> covariant?
    @variance == :covariant

  -> contravariant?
    @variance == :contravariant

  -> to_s
    prefix = self.covariant? ? "_" : "^"
    @label == nil ? prefix : prefix + @label.to_s

  -> inspect
    to_s


+ TensorField
  -> new(@chart, components, indices)
    if @chart.class_name != "Chart"
      raise "tensor field needs a Chart"
    if indices.class_name != "Array"
      raise "tensor field indices must be an Array"
    @indices = []
    indices.each -> (index)
      if index.class_name != "TensorIndex"
        raise "tensor field index metadata must contain TensorIndex values"
      @indices.push(index)
    @components = Geometry.wrap_tensor(
      components, @chart.dimension, @indices.size)

  -> chart
    @chart

  -> dimension
    @chart.dimension

  -> rank
    @indices.size

  -> indices
    Geometry.copy_array(@indices)

  -> components
    Geometry.deep_copy(@components)

  -> component(indices)
    positions = indices.class_name == "Array" ? indices : [indices]
    if positions.size != self.rank
      raise "tensor component needs one position per index"
    Geometry.component_at(@components, positions)

  -> component(left, right)
    component([left, right])

  -> component(first, second, third)
    component([first, second, third])

  -> component(first, second, third, fourth)
    component([first, second, third, fourth])

  -> at(indices)
    component(indices)

  -> [](index)
    component([index])

  -> [](left, right)
    component([left, right])

  -> [](first, second, third)
    component([first, second, third])

  -> [](first, second, third, fourth)
    component([first, second, third, fourth])

  -> evaluate(point)
    Geometry.evaluate_tensor(@components, @chart.bindings(point))

  -> simplified
    TensorField.new(@chart, Geometry.simplify_tensor(@components), @indices)

  -> to_s
    "TensorField(rank=" + self.rank.to_s + ", dim=" + self.dimension.to_s + ")"

  -> inspect
    to_s
