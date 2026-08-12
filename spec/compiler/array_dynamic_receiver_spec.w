# Array source and native methods must remain representation-safe when the
# receiver's static type is erased at a function boundary.

-> check(name, got, want)
  if got != want
    << "FAIL [name]: got=[got] want=[want]"
    exit(1)

-> erased_size(values)
  values.size

-> erased_cap(values)
  values.cap

-> erased_empty(values)
  values.empty?

-> erased_first(values)
  values.first

-> erased_last(values)
  values.last

-> erased_take(values, count)
  values.take(count)

-> erased_drop(values, count)
  values.drop(count)

-> erased_reverse(values)
  values.reverse

-> erased_copy(values, start, count)
  values.copy(start, count)

-> erased_uniq(values)
  values.uniq

-> erased_minmax(values)
  values.minmax

-> erased_join(values, separator)
  values.join(separator)

-> erased_concat(values, tail)
  values.concat(tail)

-> erased_sort(values)
  values.sort

-> erased_stable_sort(values)
  values.stable_sort

-> erased_sum(values)
  values.sum

-> erased_each_sum(values)
  total = 0
  values.each -> (value)
    total += value
  total

plain = [3, 1, 3, 2]
check("plain size", erased_size(plain), 4)
check("plain cap", erased_cap(plain) >= erased_size(plain), true)
check("plain empty", erased_empty(plain), false)
check("plain first", erased_first(plain), 3)
check("plain last", erased_last(plain), 2)
check("plain take", erased_take(plain, 2), [3, 1])
check("plain drop", erased_drop(plain, 2), [3, 2])
check("plain reverse", erased_reverse(plain), [2, 3, 1, 3])
check("plain copy", erased_copy(plain, 1, 2), [1, 3])
check("plain uniq", erased_uniq(plain), [3, 1, 2])
check("plain minmax", erased_minmax(plain), [1, 3])
check("plain join", erased_join(plain, ":"), "3:1:3:2")
check("plain concat", erased_concat(plain, [9]), [3, 1, 3, 2, 9])
check("plain sort", erased_sort(plain), [1, 2, 3, 3])
check("plain stable sort", erased_stable_sort(plain), [1, 2, 3, 3])
check("plain native sum", erased_sum(plain), 9)
check("plain each", erased_each_sum(plain), 9)

bytes = u8[4]
bytes[0] = 250
bytes[1] = 2
bytes[2] = 7
bytes[3] = 2
check("typed size", erased_size(bytes), 4)
check("typed cap", erased_cap(bytes), 4)
check("typed first", erased_first(bytes), 250)
check("typed last", erased_last(bytes), 2)
check("typed reverse", erased_reverse(bytes), [2, 7, 2, 250])
check("typed copy", erased_copy(bytes, 1, 2), [2, 7])
check("typed uniq", erased_uniq(bytes), [250, 2, 7])
check("typed native sum", erased_sum(bytes), 261)
check("typed each", erased_each_sum(bytes), 261)

bits = bool[3]
check("bit-packed zero fill", bits[0], false)
bits[0] = true
bits[1] = false
bits[2] = true
check("bit-packed direct size", bits.size, 3)
check("bit-packed size", erased_size(bits), 3)
check("bit-packed first", erased_first(bits), true)
check("bit-packed last", erased_last(bits), true)
check("bit-packed reverse", erased_reverse(bits), [true, false, true])

shifted = [9, 8, 7]
shifted.shift
check("shifted size", erased_size(shifted), 2)
check("shifted first", erased_first(shifted), 8)
check("shifted last", erased_last(shifted), 7)
check("shifted reverse", erased_reverse(shifted), [7, 8])

check("empty size", erased_size([]), 0)
check("empty predicate", erased_empty([]), true)
check("empty first", erased_first([]), nil)
check("empty last", erased_last([]), nil)

<< "array_dynamic_receiver_spec: all checks passed"
