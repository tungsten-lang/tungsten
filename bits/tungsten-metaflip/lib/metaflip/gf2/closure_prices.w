# The rank-only composition closure: the cheapest rank that block sums and Kronecker products of known schemes reach for
# every sorted shape up to `max`. A price, not a witness. Port of the dynamic programme of the campaign's closure.py.
#
#   price(s) = min(rank of the best witness or the naive n*m*p, block split along any axis, componentwise Kronecker
#                  product of two smaller shapes)
#
# Shapes are sorted triples n <= m <= p; the table is a typed i64 array indexed by the triple, so the whole grid of 5,984
# shapes up to 32 is priced in milliseconds.
#
#   ClosurePrices.board_with_leaves(board, max)   the board plus the rank-1 shapes n*m and Strassen's 7 for <2,2,2>
#   ClosurePrices.compute(board, max)             [price (i64[]), recipe {slot => text}, shapes in pricing order]
#   ClosurePrices.leads(computed, board, lille, tol, max)   the shapes whose price is within `tol` of the listed rank (or below)
#                                                 and improves the board: rows [difference, shape, price, listed, ours, recipe]
#                                                 in ascending order of difference, then shape
#   ClosurePrices.row_text(row)                   the row as Python prints the tuple
#
# `board` and `lille` are Hashes from "NxMxP" to rank (the board as its rows list the shapes, the listed ranks by sorted shape).
use record_board

+ Metaflip:Gf2:ClosurePrices
  # The slot of a sorted triple in the price table.
  -> .slot(a, b, c, max) (i64 i64 i64 i64) i64
    (a * (max + 1) + b) * (max + 1) + c

  # The slot of three extents in any order.
  -> .slot_of(x, y, z, max) (i64 i64 i64 i64) i64
    a = x ## i64
    b = y ## i64
    c = z ## i64
    t = 0 ## i64
    if a > b
      t = a
      a = b
      b = t
    if b > c
      t = b
      b = c
      c = t
    if a > b
      t = a
      a = b
      b = t
    (a * (max + 1) + b) * (max + 1) + c

  -> .tuple_text(x, y, z)
    sorted = [x, y, z].sort
    "(" + sorted[0].to_s + ", " + sorted[1].to_s + ", " + sorted[2].to_s + ")"

  -> .board_with_leaves(board, max)
    full = {}
    board.each -> (key, rank)
      full[key] = rank
    (1..max).each -> (n)
      (1..max).each -> (m)
        key = Metaflip:Gf2:RecordBoard.sorted_key([1, n, m])
        full[key] = n * m if !full.key?(key)
    two = Metaflip:Gf2:RecordBoard.sorted_key([2, 2, 2])
    full[two] = 7 if !full.key?(two) || full[two] > 7
    full

  # Prices every sorted shape up to `max` in ascending order of volume.
  -> .compute(board, max)
    size = (max + 1) * (max + 1) * (max + 1)
    price = i64[size]
    recipe = {}
    shapes = []
    (1..max).each -> (a)
      (a..max).each -> (b)
        (b..max).each -> (c)
          shapes.push([a * b * c, a, b, c])
    shapes = shapes.sort
    divisors = []
    (0..max).each -> (n)
      found = []
      (1..max).each -> (d)
        found.push(d) if n > 0 && n % d == 0
      divisors.push(found)
    order = []
    shapes.each -> (entry)
      n = entry[1]
      m = entry[2]
      p = entry[3]
      key = Metaflip:Gf2:RecordBoard.sorted_key([n, m, p])
      best = entry[0] ## i64
      how = "naive"
      if board.key?(key)
        best = board[key]
        how = "witness"
      extent = [n, m, p]
      axis = 0 ## i64
      while axis < 3
        cut = 1 ## i64
        half = extent[axis] / 2 ## i64
        while cut <= half
          x = [n, m, p]
          y = [n, m, p]
          x[axis] = cut
          y[axis] = extent[axis] - cut
          value = price[Metaflip:Gf2:ClosurePrices.slot_of(x[0], x[1], x[2], max)] + price[Metaflip:Gf2:ClosurePrices.slot_of(y[0], y[1], y[2], max)] ## i64
          if value < best
            best = value
            how = "split axis" + axis.to_s + " " + Metaflip:Gf2:ClosurePrices.tuple_text(x[0], x[1], x[2]) + "+" + Metaflip:Gf2:ClosurePrices.tuple_text(y[0], y[1], y[2])
          cut += 1
        axis += 1
      divisors[n].each -> (f0)
        divisors[m].each -> (f1)
          divisors[p].each -> (f2)
            g0 = n / f0
            g1 = m / f1
            g2 = p / f2
            if f0 * f1 * f2 != 1 && g0 * g1 * g2 != 1
              value = price[Metaflip:Gf2:ClosurePrices.slot_of(f0, f1, f2, max)] * price[Metaflip:Gf2:ClosurePrices.slot_of(g0, g1, g2, max)] ## i64
              if value < best
                best = value
                how = "kron " + Metaflip:Gf2:ClosurePrices.tuple_text(f0, f1, f2) + "x" + Metaflip:Gf2:ClosurePrices.tuple_text(g0, g1, g2)
      slot = Metaflip:Gf2:ClosurePrices.slot(n, m, p, max) ## i64
      price[slot] = best
      recipe[slot] = how
      order.push([n, m, p])
    [price, recipe, order]

  -> .leads(computed, board, lille, tol, max)
    price = computed[0]
    recipe = computed[1]
    rows = []
    computed[2].each -> (shape)
      key = Metaflip:Gf2:RecordBoard.sorted_key(shape)
      if shape[0] >= 2 && lille.key?(key)
        slot = Metaflip:Gf2:ClosurePrices.slot(shape[0], shape[1], shape[2], max) ## i64
        value = price[slot]
        listed = lille[key]
        ours = board.key?(key) ? board[key] : nil
        limit = (listed * ~1.0) * (~1.0 + tol)
        if (value * ~1.0) <= limit && (ours == nil || value < ours)
          rows.push([value - listed, shape, value, listed, ours, recipe[slot]])
    keyed = rows.map -> (row)
      [Textx.zero_pad(row[0] + 1000000, 9) + "|" + Metaflip:Gf2:RecordBoard.order_key(row[1].join("x")), row]
    keyed.sort_by(-> (pair) pair[0]).map(-> (pair) pair[1])

  # The row as Python prints the tuple: (difference, (n, m, p), price, listed, ours-or-None, 'recipe').
  -> .row_text(row)
    ours = row[4] == nil ? "None" : row[4].to_s
    "(" + row[0].to_s + ", (" + row[1].join(", ") + "), " + row[2].to_s + ", " + row[3].to_s + ", " + ours + ", '" + row[5] + "')"
