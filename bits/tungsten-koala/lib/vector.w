# Vector — mathematical vector with GPU acceleration
# Supports dot product (·), cross product (×), tensor product (⊗), and standard arithmetic.

in Tungsten:Koala

+ Vector
  ro :values
  ro :device

  -> new(values, device: nil)
    @values = values.to_a
    @device = Device.resolve(device, elements: @values.size)
    @buffer = nil
    self.upload if @device.gpu?

  -> size      @values.size
  -> length    self.size
  -> dim       self.size
  -> [](index) @values[index]

  -> to_a   @values.dup
  -> to_s   "Vector([values.join(", ")])"
  -> inspect "Vector([values.join(", ")], device: [device.kind])"

  # --- Arithmetic ---

  # Element-wise addition.
  -> +(other)
    case other
    => Vector  -> self.class.new(@values.zip(other.values).map(-> (a, b) a + b), device: @device)
    => Numeric -> self.class.new(@values.map(-> (v) v + other), device: @device)

  # Element-wise subtraction.
  -> -(other)
    case other
    => Vector  -> self.class.new(@values.zip(other.values).map(-> (a, b) a - b), device: @device)
    => Numeric -> self.class.new(@values.map(-> (v) v - other), device: @device)

  # Element-wise multiplication.
  -> *(other)
    case other
    => Vector  -> self.class.new(@values.zip(other.values).map(-> (a, b) a * b), device: @device)
    => Numeric -> self.class.new(@values.map(-> (v) v * other), device: @device)

  # Element-wise division.
  -> /(other)
    case other
    => Vector  -> self.class.new(@values.zip(other.values).map(-> (a, b) a / b), device: @device)
    => Numeric -> self.class.new(@values.map(-> (v) v / other), device: @device)

  # Dot product — `a · b` (U+00B7 middle dot)
  #
  #     a = vector [1, 2, 3]
  #     b = vector [4, 5, 6]
  #     a · b  # => 32
  -> ·(other)
    <! DimensionError, "Dot product requires equal dimensions" unless self.size == other.size
    @values.zip(other.values).map(-> (a, b) a * b).sum

  # Dot product — ASCII alias.
  -> dot(other) self · other

  # Cross product — `a × b` (U+00D7)
  # Only defined for 3D vectors.
  #
  #     a = vector [1, 0, 0]
  #     b = vector [0, 1, 0]
  #     a × b  # => Vector(0, 0, 1)
  -> ×(other)
    <! DimensionError, "Cross product requires 3D vectors" unless self.size == 3 && other.size == 3
    self.class.new([
      @values[1] * other[2] - @values[2] * other[1],
      @values[2] * other[0] - @values[0] * other[2],
      @values[0] * other[1] - @values[1] * other[0]
    ])

  # Cross product — ASCII alias.
  -> cross(other) self × other

  # Tensor product — `a ⊗ b` (U+2297)
  # Returns a Matrix (outer product of two vectors).
  #
  #     a = vector [1, 2]
  #     b = vector [3, 4]
  #     a ⊗ b  # => matrix [3 4; 6 8]
  -> ⊗(other)
    rows = @values.map -> (vi)
      other.values.map(-> (vj) vi * vj)
    Matrix.new(rows)

  # Tensor product — ASCII alias.
  -> outer(other) self ⊗ other

  # --- Norms & distance ---

  # Euclidean norm (L2).
  -> norm
    Math.sqrt(@values.map(-> (v) v * v).sum)

  # L1 norm (Manhattan).
  -> norm_l1
    @values.map(&:abs).sum

  # Lp norm.
  -> norm_lp(p)
    @values.map(-> (v) v.abs ** p).sum ** (1.0 / p)

  # Normalize to unit length.
  -> normalize
    n = self.norm
    <! ZeroDivisionError, "Cannot normalize zero vector" if n == 0
    self / n

  # Euclidean distance to another vector.
  -> distance(other)
    (self - other).norm

  # Cosine similarity.
  -> cosine_similarity(other)
    (self · other) / (self.norm * other.norm)

  # Angle between vectors (radians).
  -> angle(other)
    Math.acos(self.cosine_similarity(other).clamp(-1.0, 1.0))

  # --- Projections ---

  # Project self onto other.
  -> project_onto(other)
    other * ((self · other) / (other · other))

  # Component of self perpendicular to other.
  -> reject_from(other)
    self - self.project_onto(other)

  # --- Predicates ---

  -> zero?
    @values.all?(-> (v) v == 0)

  -> parallel?(other)
    return true if self.zero? || other.zero?
    self.normalize == other.normalize || self.normalize == other.normalize * -1

  -> orthogonal?(other)
    (self · other).abs < 1e-10

  # --- Conversion ---

  -> to_matrix
    Matrix.new([@values])

  -> to_column_matrix
    Matrix.new(@values.map(-> (v) [v]))

  -> to_series(name: nil)
    Series.new(@values, name: name)

  # --- Device management ---

  # Transfer vector to a different device.
  -> to(target_device)
    self.class.new(@values, device: target_device)

  [private]

  -> upload
    @buffer = DeviceMemory.alloc(@device, @values.size * 8)
    # Transfer data from CPU to GPU
    cpu_mem = DeviceMemory.new(Device.cpu, @values.data_pointer, @values.size * 8)
    DeviceMemory.transfer(cpu_mem, @device)
