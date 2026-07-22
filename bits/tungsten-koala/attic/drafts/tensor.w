# Tensor — n-dimensional array with GPU acceleration
# Supports arbitrary rank tensors for deep learning and scientific computing.

in Tungsten:Koala

+ Tensor
  ro :shape
  ro :data     # flat row-major array
  ro :dtype
  ro :device

  # Create a tensor from nested arrays or flat data.
  #
  #     t = Tensor.new([[1, 2], [3, 4]])           # 2×2 tensor
  #     t = Tensor.new([[[1, 2], [3, 4]]])          # 1×2×2 tensor
  #     t = Tensor.new(flat: [1, 2, 3, 4], shape: [2, 2])
  -> new(nested = nil, flat: nil, shape: nil, dtype: :float64, device: nil)
    case
    => flat
      @data  = flat.to_a
      @shape = shape
    => nested
      @shape = self.class.infer_shape(nested)
      @data  = self.class.flatten(nested)
    @dtype  = dtype
    @device = Device.resolve(device, elements: @data.size)
    @buffer = nil
    self.upload if @device.gpu?

  # --- Factories ---

  -> .zeros(shape, dtype: :float64, device: nil)
    self.new(flat: Array.new(shape.reduce(:*), 0), shape: shape, dtype: dtype, device: device)

  -> .ones(shape, dtype: :float64, device: nil)
    self.new(flat: Array.new(shape.reduce(:*), 1), shape: shape, dtype: dtype, device: device)

  -> .random(shape, dtype: :float64, device: nil)
    self.new(flat: Array.new(shape.reduce(:*)) { Random.float }, shape: shape, dtype: dtype, device: device)

  -> .arange(start, stop, step = 1, dtype: :float64, device: nil)
    values = (start...stop).step(step).to_a
    self.new(flat: values, shape: [values.size], dtype: dtype, device: device)

  -> .linspace(start, stop, n, dtype: :float64, device: nil)
    step = (stop - start).to_f / (n - 1)
    values = n.times.map(-> (i) start + i * step)
    self.new(flat: values, shape: [n], dtype: dtype, device: device)

  # --- Properties ---

  -> rank    @shape.size
  -> ndim    self.rank
  -> numel   @data.size
  -> empty?  @data.empty?

  # --- Access ---

  -> [](*indices)
    case
    => indices.size == @shape.size
      # Scalar access
      flat_idx = self.flat_index(indices)
      @data[flat_idx]
    => indices.size < @shape.size
      # Slice — return sub-tensor
      self.slice_at(indices)

  -> []=(*indices_and_value)
    value = indices_and_value.pop
    indices = indices_and_value
    @data[self.flat_index(indices)] = value

  # --- Arithmetic ---

  -> +(other) self.elementwise(:+, other)
  -> -(other) self.elementwise(:-, other)
  -> *(other) self.elementwise(:*, other)
  -> /(other) self.elementwise(:/, other)

  # Matrix multiplication for 2D tensors — `A @ B`
  -> @(other)
    <! RankError, "@ requires 2D tensors" unless self.rank == 2 && other.rank == 2
    self.to_matrix.@(other.to_matrix).to_tensor

  # Dot product — `a · b` for 1D tensors
  -> ·(other)
    <! RankError, "· requires 1D tensors" unless self.rank == 1 && other.rank == 1
    <! DimensionError, "Tensors must have same length" unless self.numel == other.numel
    @data.zip(other.data).map(-> (a, b) a * b).sum

  # Tensor product — `a ⊗ b`
  -> ⊗(other)
    new_shape = @shape + other.shape
    data = @data.flat_map -> (a)
      other.data.map(-> (b) a * b)
    self.class.new(flat: data, shape: new_shape, dtype: @dtype, device: @device)

  # --- Reshape & transform ---

  -> reshape(*new_shape)
    total = new_shape.reduce(:*)
    <! DimensionError, "Cannot reshape [numel] elements to [new_shape]" unless total == self.numel
    self.class.new(flat: @data.dup, shape: new_shape, dtype: @dtype, device: @device)

  -> flatten
    self.class.new(flat: @data.dup, shape: [self.numel], dtype: @dtype, device: @device)

  -> squeeze
    new_shape = @shape.reject(-> (d) d == 1)
    new_shape = [1] if new_shape.empty?
    self.reshape(*new_shape)

  -> unsqueeze(dim)
    new_shape = @shape.dup
    new_shape.insert(dim, 1)
    self.reshape(*new_shape)

  -> transpose(dim0 = 0, dim1 = 1)
    <! RankError, "Transpose requires at least 2 dimensions" unless self.rank >= 2
    perm = (0...self.rank).to_a
    perm[dim0], perm[dim1] = perm[dim1], perm[dim0]
    self.permute(*perm)

  -> permute(*dims)
    new_shape = dims.map(-> (d) @shape[d])
    # Compute permuted flat data
    new_data = Array.new(self.numel)
    self.each_index -> (indices)
      new_indices = dims.map(-> (d) indices[d])
      old_flat = self.flat_index(indices)
      new_flat = self.flat_index_for(new_indices, new_shape)
      new_data[new_flat] = @data[old_flat]
    self.class.new(flat: new_data, shape: new_shape, dtype: @dtype, device: @device)

  # --- Reduction ---

  -> sum(dim: nil)
    return @data.sum unless dim
    self.reduce_dim(dim, :+)

  -> mean(dim: nil)
    return @data.sum.to_f / self.numel unless dim
    sums = self.reduce_dim(dim, :+)
    sums / @shape[dim]

  -> max(dim: nil)
    return @data.max unless dim
    self.reduce_dim(dim, :max)

  -> min(dim: nil)
    return @data.min unless dim
    self.reduce_dim(dim, :min)

  # --- Conversion ---

  -> to_matrix
    <! RankError, "to_matrix requires 2D tensor" unless self.rank == 2
    Matrix.new(flat: @data.dup, rows: @shape[0], cols: @shape[1], device: @device)

  -> to_vector
    <! RankError, "to_vector requires 1D tensor" unless self.rank == 1
    Vector.new(@data.dup, device: @device)

  -> to_a
    self.class.unflatten(@data, @shape)

  -> to(target_device)
    self.class.new(flat: @data, shape: @shape, dtype: @dtype, device: target_device)

  -> to_s
    "Tensor(shape: [shape], dtype: [dtype], device: [device.kind])"

  # --- Internal ---

  [private]

  -> flat_index(indices)
    idx = 0
    stride = 1
    (indices.size - 1).downto(0) -> (i)
      idx += indices[i] * stride
      stride *= @shape[i]
    idx

  -> flat_index_for(indices, shape)
    idx = 0
    stride = 1
    (indices.size - 1).downto(0) -> (i)
      idx += indices[i] * stride
      stride *= shape[i]
    idx

  -> .infer_shape(nested)
    shape = []
    current = nested
    loop
      break unless current.is_a?(Array)
      shape.push(current.size)
      current = current.first
    shape

  -> .flatten(nested)
    case nested.first
    => Array -> nested.flat_map(-> (sub) self.flatten(sub))
    => _     -> nested.to_a

  -> .unflatten(flat, shape)
    return flat.dup if shape.size == 1
    chunk_size = shape[1..].reduce(:*)
    flat.each_slice(chunk_size).map(-> (chunk) self.unflatten(chunk, shape[1..]))

  -> upload
    @buffer = DeviceMemory.alloc(@device, @data.size * 8)

  -> elementwise(op, other)
    case other
    => Tensor
      <! DimensionError, "Shape mismatch" unless @shape == other.shape
      self.class.new(flat: @data.zip(other.data).map(-> (a, b) a.send(op, b)), shape: @shape, dtype: @dtype, device: @device)
    => Numeric
      self.class.new(flat: @data.map(-> (v) v.send(op, other)), shape: @shape, dtype: @dtype, device: @device)

+ RankError < Error
