# Series — a single typed column of data
# Backed by Apache Arrow arrays for zero-copy slicing and interop.

in Tungsten:Koala

+ Series
  ro :name
  ro :dtype
  ro :values
  ro :index

  -> new(values, name: nil, dtype: nil, index: nil)
    @values = Arrow:Array.from(values)
    @name   = name
    @dtype  = dtype || @values.type
    @index  = index || Index.new(0...@values.size)

  -> size  @values.size
  -> empty? @values.size == 0
  -> length self.size

  # --- Access ---

  -> [](key)
    case key
    => Int       -> @values[key]
    => Range     -> self.class.new(@values[key], name: @name, dtype: @dtype)
    => Array     -> self.class.new(key.map(-> (k) @values[k]), name: @name)

  -> head(n = 5) self[0...n]
  -> tail(n = 5) self[-n..]
  -> first       @values[0]
  -> last        @values[-1]

  # --- Aggregations ---

  -> sum          Stats.sum(@values)
  -> mean         Stats.mean(@values)
  -> median       Stats.median(@values)
  -> std          Stats.std(@values)
  -> var          Stats.var(@values)
  -> min          Stats.min(@values)
  -> max          Stats.max(@values)
  -> count        @values.reject(&:nil?).size
  -> nunique      @values.uniq.size
  -> percentile(p) Stats.percentile(@values, p)
  -> describe     Stats.describe(self)

  # --- Transforms ---

  -> map(&block)
    self.class.new(@values.map(&block), name: @name)

  -> select(&block)
    mask = @values.map(&block)
    self.class.new(@values.select_mask(mask), name: @name)

  -> reject(&block)
    self.select(-> (v) !block.call(v))

  -> sort(order = :asc)
    sorted = case order
    => :asc  -> @values.sort
    => :desc -> @values.sort.reverse
    self.class.new(sorted, name: @name, dtype: @dtype)

  -> unique
    self.class.new(@values.uniq, name: @name)

  -> value_counts
    counts = @values.tally
    DataFrame.new(
      value: counts.keys,
      count: counts.values
    ).sort_by(:count, :desc)

  -> fillna(value)
    self.class.new(@values.map(-> (v) v || value), name: @name, dtype: @dtype)

  -> dropna
    self.class.new(@values.reject(&:nil?), name: @name, dtype: @dtype)

  -> clip(low: nil, high: nil)
    self.map -> (v)
      v = [v, low].max if low
      v = [v, high].min if high
      v

  # --- Rolling ---

  -> rolling(window:, min_periods: 1)
    Rolling.new(self, window: window, min_periods: min_periods)

  # --- Arithmetic ---

  -> +(other)  self.elementwise(:+, other)
  -> -(other)  self.elementwise(:-, other)
  -> *(other)  self.elementwise(:*, other)
  -> /(other)  self.elementwise(:/, other)
  -> **(other) self.elementwise(:**, other)

  # --- Comparison ---

  -> >(other)  self.compare(:>, other)
  -> <(other)  self.compare(:<, other)
  -> >=(other) self.compare(:>=, other)
  -> <=(other) self.compare(:<=, other)
  -> ==(other) self.compare(:==, other)

  # --- Casting ---

  -> to_a      @values.to_a
  -> to_list   @values.to_a
  -> to_vector Vector.new(@values.to_a)

  -> to_s
    lines = ["Series: [name]  dtype: [dtype]  length: [self.size]"]
    display = [self.size, 10].min
    display.times -> (i)
      lines.push("  [@index[i]]  [@values[i]]")
    lines.push("  ...") if self.size > 10
    lines.join("\n")

  # --- Internal ---

  [private]

  -> elementwise(op, other)
    other_vals = case other
    => Series  -> other.values
    => Numeric -> Array.new(self.size, other)
    self.class.new(@values.zip(other_vals).map(-> (a, b) a.send(op, b)), name: @name)

  -> compare(op, other)
    other_vals = case other
    => Series  -> other.values
    => Numeric -> Array.new(self.size, other)
    self.class.new(@values.zip(other_vals).map(-> (a, b) a.send(op, b)), name: @name)
