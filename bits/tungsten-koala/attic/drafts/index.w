# Index — row labels for DataFrames and Series
# Unlike pandas, Index is simple and predictable. No confusing alignment surprises.

in Tungsten:Koala

+ Index
  ro :labels
  ro :name

  -> new(labels, name: nil)
    @labels = case labels
    => Range -> labels.to_a
    => Array -> labels
    => Int   -> (0...labels).to_a
    @name = name

  -> size    @labels.size
  -> [](key) @labels[key]
  -> to_a    @labels

  -> contains?(label)
    @labels.include?(label)

  -> loc(label)
    @labels.index(label)

  -> slice(from, to)
    self.class.new(@labels[from..to], name: @name)

  -> reset
    self.class.new(@labels.size, name: @name)

  -> rename(new_name)
    self.class.new(@labels, name: new_name)

  -> ==(other)
    case other
    => Index -> @labels == other.labels
    => Array -> @labels == other

  -> to_s
    "Index([labels.join(", ")], name: [name || "nil"])"

  -> each(&block)
    @labels.each(&block)

  -> map(&block)
    self.class.new(@labels.map(&block), name: @name)
