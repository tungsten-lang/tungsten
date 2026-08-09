# Shared exact helpers for finite combinatorics.

+ Combinatorics
  -> .integer?(value)
    name = value.class_name
    name == "Integer" || name == "Int" || name == "BigInt"

  -> .require_nonnegative_integer(value, name)
    if !Combinatorics.integer?(value) || value < 0
      raise name + " must be a nonnegative integer"
    value

  -> .copy_vector(vector)
    out = []
    vector.each -> (value)
      out.push(value)
    out

  -> .copy_matrix(matrix)
    out = []
    matrix.each -> (row)
      out.push(Combinatorics.copy_vector(row))
    out

  -> .binomial(n, k)
    Combinatorics.require_nonnegative_integer(n, "n")
    raise "k must be an integer" if !Combinatorics.integer?(k)
    return 0 if k < 0 || k > n
    complement = n - k
    k = complement if complement < k
    value = 1
    i = 1
    while i <= k
      value = value * (n - k + i) / i
      i += 1
    value

  -> .hamming_distance(left, right)
    if (left.class_name != "Array" || right.class_name != "Array" ||
        left.size != right.size)
      raise "Hamming vectors must be arrays of equal length"
    distance = 0
    i = 0
    while i < left.size
      distance += 1 if left[i] != right[i]
      i += 1
    distance

  -> .dot(left, right)
    if (left.class_name != "Array" || right.class_name != "Array" ||
        left.size != right.size)
      raise "dot-product vectors must be arrays of equal length"
    value = 0
    i = 0
    while i < left.size
      value += left[i] * right[i]
      i += 1
    value
