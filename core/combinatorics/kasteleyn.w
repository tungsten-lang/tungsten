# Kasteleyn's theorem: perfect matchings of a planar graph as a determinant.
#
# Counting perfect matchings is the permanent of an adjacency matrix, and
# permanents are hard. Kasteleyn's insight was that a planar graph admits an
# orientation — one where every bounded face has an odd number of edges
# running clockwise — for which the *signed* adjacency matrix A, which is
# skew-symmetric, satisfies
#
#     number of perfect matchings = |Pf(A)|,        Pf(A)^2 = det(A)
#
# turning an exponential count into linear algebra. The permanent's sign
# chaos becomes the determinant's cancellation, and cancellation is cheap.
#
# For the m x n grid the orientation is explicit: send every horizontal edge
# in the +x direction, and every vertical edge in column x in the +y direction
# when x is even, -y when x is odd. Each unit face then carries an odd number
# of clockwise edges — 3 when x is even, 1 when x is odd — so it is Pfaffian.
#
# Two exact routes are provided and they must agree. `determinant` is
# Bareiss fraction-free elimination, which stays in integers throughout (every
# division it performs is exact), giving det(A) = (matchings)^2 in O(n^3).
# `pfaffian` is the genuine recursive Pfaffian expansion along the first row,
# which is exponential but computes the signed quantity itself rather than its
# square root. `DimerCovering` reaches the same numbers by transfer matrix,
# so three independent methods cross-check one another.

+ Kasteleyn
  -> .index_of(x, y, width)
    y * width + x

  # The skew-symmetric Kasteleyn matrix of the width x height grid graph.
  -> .matrix(width, height)
    raise "grid dimensions must be positive" if width < 1 || height < 1
    n = width * height
    a = []
    i = 0
    while i < n
      row = []
      j = 0
      while j < n
        row.push(0)
        j += 1
      a.push(row)
      i += 1
    y = 0
    while y < height
      x = 0
      while x < width
        here = Kasteleyn.index_of(x, y, width)
        # Horizontal edges always run in the +x direction.
        if x + 1 < width
          there = Kasteleyn.index_of(x + 1, y, width)
          a[here][there] = 1
          a[there][here] = 0 - 1
        # Vertical edges run +y in even columns and -y in odd ones.
        if y + 1 < height
          there = Kasteleyn.index_of(x, y + 1, width)
          up = x % 2 == 0
          a[here][there] = up ? 1 : 0 - 1
          a[there][here] = up ? 0 - 1 : 1
        x += 1
      y += 1
    a

  # Exact integer determinant by Bareiss fraction-free elimination. Each
  # division below is exact — that is the content of the algorithm — so no
  # rationals are ever needed and no precision is lost.
  -> .determinant(matrix)
    n = matrix.size
    return 1 if n == 0
    m = []
    i = 0
    while i < n
      row = []
      j = 0
      while j < n
        raise "determinant needs a square matrix" if matrix[i].size != n
        row.push(matrix[i][j])
        j += 1
      m.push(row)
      i += 1
    sign = 1
    previous = 1
    k = 0
    while k < n - 1
      if m[k][k] == 0
        swapped = false
        r = k + 1
        while r < n && !swapped
          if m[r][k] != 0
            tmp = m[k]
            m[k] = m[r]
            m[r] = tmp
            sign = 0 - sign
            swapped = true
          r += 1
        return 0 if !swapped
      i = k + 1
      while i < n
        j = k + 1
        while j < n
          m[i][j] = (m[i][j] * m[k][k] - m[i][k] * m[k][j]) / previous
          j += 1
        i += 1
      previous = m[k][k]
      k += 1
    sign * m[n - 1][n - 1]

  # The Pfaffian of a skew-symmetric matrix, by expansion along the first row:
  #   Pf(A) = sum_j (-1)^j a_{1j} Pf(A with rows and columns 1 and j deleted)
  # Exact, and exponential in the matrix size — use it to confirm the identity
  # Pf^2 = det on small cases, and Bareiss for real work.
  -> .pfaffian(matrix)
    n = matrix.size
    return 0 if n % 2 == 1
    return 1 if n == 0
    total = 0
    j = 1
    while j < n
      if matrix[0][j] != 0
        minor = []
        r = 1
        while r < n
          if r != j
            row = []
            c = 1
            while c < n
              row.push(matrix[r][c]) if c != j
              c += 1
            minor.push(row)
          r += 1
        term = matrix[0][j] * Kasteleyn.pfaffian(minor)
        total += (j % 2 == 1) ? term : 0 - term
      j += 1
    total

  -> .skew_symmetric?(matrix)
    n = matrix.size
    i = 0
    while i < n
      return false if matrix[i][i] != 0
      j = 0
      while j < n
        return false if matrix[i][j] != 0 - matrix[j][i]
        j += 1
      i += 1
    true

  -> .integer_sqrt(value)
    raise "cannot take the square root of a negative count" if value < 0
    return 0 if value == 0
    guess = value
    better = (guess + 1) / 2
    while better < guess
      guess = better
      better = (guess + value / guess) / 2
    raise "value is not a perfect square" if guess * guess != value
    guess

  # Domino tilings of the grid, via det(A) = (matchings)^2.
  -> .tilings(width, height)
    return 0 if (width * height) % 2 == 1
    Kasteleyn.integer_sqrt(Kasteleyn.determinant(Kasteleyn.matrix(width, height)))

  # Domino tilings via the Pfaffian itself. Same number, exponential cost.
  -> .tilings_by_pfaffian(width, height)
    value = Kasteleyn.pfaffian(Kasteleyn.matrix(width, height))
    value < 0 ? 0 - value : value
