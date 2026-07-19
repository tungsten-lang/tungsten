# Enumerable trait
#
# Include in classes that implement each(block) to get map, select, reduce, etc.
# Most iterators yield one value. Hash keeps its established two-argument
# `(key, value)` each contract and overrides the two internal adapter methods
# below; public combinator bodies still have one source of truth in this trait.

trait Enumerable
  # Hot combinators select one storage shape once per call: ordinary
  # single-yield iterator (0), integer-indexed sequence (1), or pair-yielding
  # iterator (2). The public algorithms remain here in the trait.
  -> __enumerable_iteration_mode
    0

  -> __enumerable_yields_pair?
    false

  # Normalize the storage iterator to a two-slot internal callback. This
  # wrapper is intentionally arity-correct: forwarding a two-parameter
  # closure directly to Array#each would call it through the one-argument C
  # closure ABI. Hot combinators below use branch-specific direct iterators;
  # the adapter remains the safe generic path for the rest of the trait.
  -> __enumerable_each(block)
    each -> (item)
      block.call(item, nil)

  -> to_a() []
    pairs = __enumerable_yields_pair?
    consumer = -> (first, second)
      if pairs
        out.push([first, second])
      else
        out.push(first)

    __enumerable_each(consumer)
  # @todo initialize size and type of array
  # &[$size]
  -> map(&block) []
    mode = __enumerable_iteration_mode
    if mode == 2
      self.each -> (first, second)
        out.push block(first, second)
    elsif mode == 1
      i = 0
      n = self.size
      while i < n
        out.push block(self[i])
        i++
    else
      self.each -> (item)
        out.push block(item)
  # @todo initialize type of array
  # &[]
  -> select(&block) []
    mode = __enumerable_iteration_mode
    if mode == 2
      self.each -> (first, second)
        if block(first, second)
          out.push([first, second])
    elsif mode == 1
      i = 0
      n = self.size
      while i < n
        item = self[i]
        if block(item)
          out.push(item)
        i++
    else
      self.each -> (item)
        if block(item)
          out.push(item)
  # @todo initialize type of array
  # &[]
  -> reject(&block) []
    mode = __enumerable_iteration_mode
    if mode == 2
      self.each -> (first, second)
        if !block(first, second)
          out.push([first, second])
    elsif mode == 1
      i = 0
      n = self.size
      while i < n
        item = self[i]
        if !block(item)
          out.push(item)
        i++
    else
      self.each -> (item)
        if !block(item)
          out.push(item)
  # @todo initialize type of array
  -> __enumerable_find_pair(block)
    self.each -> (first, second)
      if block(first, second)
        return [first, second]
    nil

  -> __enumerable_find_single(block)
    self.each -> (item)
      if block(item)
        return item
    nil

  -> find(&block)
    mode = __enumerable_iteration_mode
    if mode == 2
      return __enumerable_find_pair(block)
    elsif mode == 1
      i = 0
      n = self.size
      while i < n
        item = self[i]
        if block(item)
          return item
        i++
    else
      return __enumerable_find_single(block)
    nil

  -> detect(&block)
    find(block)

  # Pair-yielding collections pass their canonical `[first, second]` entry as
  # reduce's item so the accumulator + item callback remains a two-arg call.
  -> reduce(init, &block)
    acc = init
    mode = __enumerable_iteration_mode
    if mode == 2
      self.each -> (first, second)
        acc = block(acc, [first, second])
    elsif mode == 1
      i = 0
      n = self.size
      while i < n
        acc = block(acc, self[i])
        i++
    else
      self.each -> (item)
        acc = block(acc, item)
    acc

  -> all?/&
    pairs = __enumerable_yields_pair?
    consumer = -> (first, second)
      matched = false
      if pairs
        matched = &(first, second)
      else
        matched = &(first)
      return false unless matched
    __enumerable_each(consumer)
    true

  -> any?
    pairs = __enumerable_yields_pair?
    consumer = -> (first, second)
      return true if pairs || first
    __enumerable_each(consumer)
    false

  -> any?/&
    pairs = __enumerable_yields_pair?
    consumer = -> (first, second)
      matched = false
      if pairs
        matched = &(first, second)
      else
        matched = &(first)
      return true if matched
    __enumerable_each(consumer)
    false

  -> none?/&
    pairs = __enumerable_yields_pair?
    consumer = -> (first, second)
      matched = false
      if pairs
        matched = &(first, second)
      else
        matched = &(first)
      return false if matched
    __enumerable_each(consumer)
    true

  -> count() 0
    consumer = -> (first, second)
      acc++

    __enumerable_each(consumer)
  -> count/& 0
    pairs = __enumerable_yields_pair?
    consumer = -> (first, second)
      matched = false
      if pairs
        matched = &(first, second)
      else
        matched = &(first)
      acc++ if matched

    __enumerable_each(consumer)
  -> sum() 0
    pairs = __enumerable_yields_pair?
    consumer = -> (first, second)
      if pairs
        acc += [first, second]
      else
        acc += first

    __enumerable_each(consumer)
  -> sum(init) init
    pairs = __enumerable_yields_pair?
    consumer = -> (first, second)
      if pairs
        acc += [first, second]
      else
        acc += first

    __enumerable_each(consumer)
  -> min() nil
    pairs = __enumerable_yields_pair?
    consumer = -> (first, second)
      item = first
      if pairs
        item = [first, second]
      out = item if out == nil || item < out

    __enumerable_each(consumer)
  -> max() nil
    pairs = __enumerable_yields_pair?
    consumer = -> (first, second)
      item = first
      if pairs
        item = [first, second]
      out = item if out == nil || item > out

    __enumerable_each(consumer)
  -> minmax
    [min, max]

  # Element for which the block returns the smallest / largest value. The key
  # block runs once per element; comparison is on the keys via `<` / `>`. A
  # `seen` flag (not `best == nil`) so an enumerable containing nil elements
  # still compares correctly. Returns nil when empty.
  -> min_by(&block)
    best = nil
    best_key = nil
    seen = false
    mode = __enumerable_iteration_mode
    if mode == 2
      self.each -> (first, second)
        k = block(first, second)
        if !seen || k < best_key
          best = [first, second]
          best_key = k
          seen = true
    elsif mode == 1
      i = 0
      n = self.size
      while i < n
        item = self[i]
        k = block(item)
        if !seen || k < best_key
          best = item
          best_key = k
          seen = true
        i++
    else
      self.each -> (item)
        k = block(item)
        if !seen || k < best_key
          best = item
          best_key = k
          seen = true
    best

  -> max_by(&block)
    best = nil
    best_key = nil
    seen = false
    mode = __enumerable_iteration_mode
    if mode == 2
      self.each -> (first, second)
        k = block(first, second)
        if !seen || k > best_key
          best = [first, second]
          best_key = k
          seen = true
    elsif mode == 1
      i = 0
      n = self.size
      while i < n
        item = self[i]
        k = block(item)
        if !seen || k > best_key
          best = item
          best_key = k
          seen = true
        i++
    else
      self.each -> (item)
        k = block(item)
        if !seen || k > best_key
          best = item
          best_key = k
          seen = true
    best

  -> first
    pairs = __enumerable_yields_pair?
    consumer = -> (first, second)
      if pairs
        return [first, second]
      else
        return first
    __enumerable_each(consumer)
    nil

  -> include?(value)
    pairs = __enumerable_yields_pair?
    consumer = -> (first, second)
      item = first
      if pairs
        item = [first, second]
      return true if item == value
    __enumerable_each(consumer)
    false

  -> flat_map(&block) []
    mode = __enumerable_iteration_mode
    if mode == 2
      self.each -> (first, second)
        sub = block(first, second)
        if type(sub) == "Array"
          sub.__enumerable_append_to(out)
        else
          out.push(sub)
    elsif mode == 1
      i = 0
      n = self.size
      while i < n
        sub = block(self[i])
        if type(sub) == "Array"
          sub.__enumerable_append_to(out)
        else
          out.push(sub)
        i++
    else
      self.each -> (item)
        sub = block(item)
        if type(sub) == "Array"
          sub.__enumerable_append_to(out)
        else
          out.push(sub)
  # A pair-yielding collection uses `[first, second]` as the item so index
  # remains the callback's second argument.
  -> each_with_index(&block)
    mode = __enumerable_iteration_mode
    if mode == 2
      i = 0
      self.each -> (first, second)
        block([first, second], i)
        i++
    elsif mode == 1
      i = 0 ## i64
      n = self.size ## i64
      while i < n
        block(self[i], i)
        i++
    else
      i = 0
      self.each -> (item)
        block(item, i)
        i++
    self
  -> map_with_index/& []
    pairs = __enumerable_yields_pair?
    i = 0
    consumer = -> (first, second)
      if pairs
        out.push &([first, second], i)
      else
        out.push &(first, i)
      i++

    __enumerable_each(consumer)
  -> join(sep = "") ""
    pairs = __enumerable_yields_pair?
    first_item = true
    consumer = -> (first, second)
      if first_item
        first_item = false
      else
        out += sep
      if pairs
        out += [first, second].to_s
      else
        out += first.to_s

    __enumerable_each(consumer)
  # @todo initialize size and type of array
  -> take(n) []
    pairs = __enumerable_yields_pair?
    i = 0
    consumer = -> (first, second)
      if i < n
        if pairs
          out.push([first, second])
        else
          out.push(first)
      i++

    __enumerable_each(consumer)
  # @todo initialize size and type of array
  -> drop(n) []
    pairs = __enumerable_yields_pair?
    i = 0
    consumer = -> (first, second)
      if i >= n
        if pairs
          out.push([first, second])
        else
          out.push(first)
      i++

    __enumerable_each(consumer)
  -> empty?
    consumer = -> (first, second)
      return false
    __enumerable_each(consumer)
    true

  -> sort
    to_a.sort

  -> uniq() []
    pairs = __enumerable_yields_pair?
    seen = {}
    consumer = -> (first, second)
      item = first
      if pairs
        item = [first, second]
      if !seen.has_key?(item)
        seen[item] = true
        out.push(item)

    __enumerable_each(consumer)
  -> group_by(&block) groups={}
    mode = __enumerable_iteration_mode
    if mode == 2
      self.each -> (first, second)
        key = block(first, second)
        item = [first, second]
        bucket = groups[key]
        if bucket == nil
          bucket = []
          groups[key] = bucket
        bucket.push(item)
    elsif mode == 1
      i = 0
      n = self.size
      while i < n
        item = self[i]
        key = block(item)
        bucket = groups[key]
        if bucket == nil
          bucket = []
          groups[key] = bucket
        bucket.push(item)
        i++
    else
      self.each -> (item)
        key = block(item)
        bucket = groups[key]
        if bucket == nil
          bucket = []
          groups[key] = bucket
        bucket.push(item)
  # @todo initialize type of arrays
  -> partition(&block)
    mode = __enumerable_iteration_mode
    yes = []
    no  = []
    if mode == 2
      self.each -> (first, second)
        matched = block(first, second)
        item = [first, second]
        if matched
          yes.push(item)
        else
          no.push(item)
    elsif mode == 1
      i = 0
      n = self.size
      while i < n
        item = self[i]
        if block(item)
          yes.push(item)
        else
          no.push(item)
        i++
    else
      self.each -> (item)
        if block(item)
          yes.push(item)
        else
          no.push(item)
    [yes, no]

  -> zip/1 []
    a = to_a
    b = @1.to_a
    maxsize = [a.size, b.size].max
    (0...maxsize).each -> (i)
      out.push [a[i], b[i]]

  -> reverse() []
    arr = to_a
    i = arr.size - 1
    while i >= 0
      out.push arr[i]
      i--

  -> each_slice(n, &)
    pairs = __enumerable_yields_pair?
    slice = []
    consumer = -> (first, second)
      if pairs
        slice.push([first, second])
      else
        slice.push(first)
      if slice.size == n
        &(slice)
        slice = []
    __enumerable_each(consumer)
    if slice.size > 0
      &(slice)

  -> each_cons(n, &)
    pairs = __enumerable_yields_pair?
    buf = []
    consumer = -> (first, second)
      if pairs
        buf.push([first, second])
      else
        buf.push(first)
      if buf.size > n
        buf = buf.drop(1)
      if buf.size == n
        &(buf.to_a)

    __enumerable_each(consumer)
  -> tally() counts={}
    mode = __enumerable_iteration_mode
    if mode == 2
      self.each -> (first, second)
        item = [first, second]
        count = counts[item]
        if count == nil
          counts[item] = 1
        else
          counts[item] = count + 1
    elsif mode == 1
      i = 0
      n = self.size
      while i < n
        item = self[i]
        count = counts[item]
        if count == nil
          counts[item] = 1
        else
          counts[item] = count + 1
        i++
    else
      self.each -> (item)
        count = counts[item]
        if count == nil
          counts[item] = 1
        else
          counts[item] = count + 1
