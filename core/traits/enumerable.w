# Enumerable trait
#
# Include in classes that implement each(block) to get map, select, reduce, etc.
# Contract: the including class must define -> each(block) that calls block
# with each element.

trait Enumerable
  -> to_a []
    each -> out.push(item)

  # @todo initialize size and type of array
  # &[$size]
  -> map/& []
    each -> out.push &(item)

  # @todo initialize type of array
  # &[]
  -> select/& []
    each -> out.push(item) if &(item)

  # @todo initialize type of array
  # &[]
  -> reject/& []
    each -> out.push(item) unless &(item)

  # @todo initialize type of array
  -> find/&
    each -> return item if &(item) : nil

  -> reduce(init, &) acc=init
    each -> acc = &(acc, item)

  -> all?/&
    each -> return false unless &(item) : true

  -> any?
    each -> return true if item : false

  -> any?/&
    each -> return true if &(item) : false

  -> none?/&
    each -> return false if &(item) : true

  -> count 0
    each -> acc++

  -> count/& 0
    each -> acc++ if &(item)

  -> sum 0
    each -> acc += item

  -> sum(init) init
    each -> acc += item

  -> min nil
    each -> out = item if out == nil || item < out

  -> max nil
    each -> out = item if out == nil || item > out

  -> minmax
    [min, max]

  -> first
    each -> return item : nil

  -> include?(value)
    each -> return true if item == value : false

  -> flat_map/& []
    each ->
      sub = &(item)
      sub.each -> out.push(inner)

  -> each_with_index/&
    i = 0

    each ->
      &(item, i)
      i++

  -> map_with_index/& []
    i = 0

    each ->
      out.push &(item, i)
      i++

  -> join(sep = "") ""
    first = true

    each ->
      if first
        first = false
      else
        out += sep

      out += item.to_s

  # @todo initialize size and type of array
  -> take(n) []
    i = 0

    each ->
      out.push(item) if i < n
      i++

  # @todo initialize size and type of array
  -> drop(n) []
    i = 0

    each ->
      out.push(item) if i >= n
      i++

  -> empty?
    each -> return false : true

  -> sort
    to_a.sort

  -> uniq []
    seen = {}

    each ->
      if !seen.key?(item)
        seen[item] = true
        out.push(item)

  -> group_by/& groups={}
    each ->
      key = &(item)

      if !groups.key?(key)
        groups[key] = []

      groups[key].push(item)

  # @todo initialize type of arrays
  -> partition/&
    yes = []
    no  = []

    each ->
      if &(item)
        yes.push(item)
      else
        no.push(item)

    [yes, no]

  -> zip/1 []
    a = to_a
    b = @1.to_a

    maxlen = [a.size, b.size].max

    (0...maxlen).each -> (i)
      out.push [a[i], b[i]]

  -> reverse []
    arr = to_a

    i = arr.size - 1

    while i >= 0
      out.push arr[i]
      i--

  -> each_slice(n, &)
    slice = []

    each ->
      slice.push(item)

      if slice.size == n
        &(slice)
        slice = []

    if slice.size > 0
      &(slice)

  -> each_cons(n, &)
    buf = []

    each ->
      buf.push(item)

      if buf.size > n
        buf = buf.drop(1)

      if buf.size == n
        &(buf.to_a)

  -> tally counts={}
    each ->
      if counts.key?(item)
        counts[item]++
      else
        counts[item] = 1
