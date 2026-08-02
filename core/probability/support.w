# Support objects for scalar distributions and finite unions.

use core/probability/primitives

+ ProbabilitySupport
  -> new(@lower, @upper, @lower_closed = true, @upper_closed = true,
         @discrete = false)

  -> lower
    @lower

  -> upper
    @upper

  -> lower_closed?
    @lower_closed

  -> upper_closed?
    @upper_closed

  -> discrete?
    @discrete

  -> continuous?
    !@discrete

  -> bounded?
    @lower != nil && @upper != nil

  -> contains?(value)
    return false if value != value
    return false if @discrete && !ProbabilityNumerics.integer?(value)
    if @lower != nil
      return false if value < @lower
      return false if !@lower_closed && value == @lower
    if @upper != nil
      return false if value > @upper
      return false if !@upper_closed && value == @upper
    true

  -> to_s
    left = @lower_closed ? "[" : "("
    right = @upper_closed ? "]" : ")"
    lower_text = @lower == nil ? "-infinity" : @lower.to_s
    upper_text = @upper == nil ? "infinity" : @upper.to_s
    kind = @discrete ? " integers" : ""
    left + lower_text + ", " + upper_text + right + kind

  -> inspect
    self.to_s


+ ProbabilityUnionSupport
  -> new(supports)
    if supports.class_name != "Array" || supports.size == 0
      raise "probability union support needs a nonempty Array"
    @supports = ProbabilityNumerics.copy_array(supports)
    @discrete = true
    @bounded = true
    i = 0
    while i < @supports.size
      @discrete = false if !@supports[i].discrete?
      @bounded = false if !@supports[i].bounded?
      i += 1
    self

  -> supports
    ProbabilityNumerics.copy_array(@supports)

  -> discrete?
    @discrete

  -> continuous?
    !@discrete

  -> bounded?
    @bounded

  -> lower
    nil

  -> upper
    nil

  -> contains?(value)
    i = 0
    while i < @supports.size
      return true if @supports[i].contains?(value)
      i += 1
    false

  -> to_s
    parts = []
    i = 0
    while i < @supports.size
      parts.push(@supports[i].to_s)
      i += 1
    "union(" + parts.join(", ") + ")"

  -> inspect
    self.to_s
