# Exact offline GF(2) compression when two factor spans have dimension <= 2.
# The remaining factor is unrestricted: the tensor has only four columns on
# that side, so its intrinsic span has dimension <= 4. This is not a general
# rank search or a production fleet policy. Materialized schemes still need
# the full tensor admission gate.
require_relative "cancellation_patterns"

module MetaflipMatrixPockets
  module_function

  def small_term(a, b, c)
    raise "invalid pocket coordinate" unless a.is_a?(Integer) && a.between?(0, 15) &&
      [b, c].all? { |v| v.is_a?(Integer) && v.between?(0, 3) }
    bits = 0
    4.times { |i| 2.times { |j| 2.times { |k| bits ^= (a[i] & b[j] & c[k]) << (4 * i + 2 * j + k) } } }
    bits
  end

  # Every 4x2x2 tensor is a sum of its four elementary (b,c) columns.
  # Enumerate every sum of <=3 of the 135 nonzero rank-one tensors first.
  # Distinct summands suffice in characteristic two; repeated ones cancel.
  def table
    @table ||= begin
      terms = (1..15).flat_map { |a| (1..3).flat_map { |b| (1..3).map { |c| [a, b, c].freeze } } }.freeze
      words = terms.map { |t| small_term(*t) }
      result = Array.new(65_536)
      result[0] = [].freeze
      terms.each_with_index { |t, i| result[words[i]] = [t].freeze }
      terms.each_index.to_a.combination(2) { |i, j| result[words[i] ^ words[j]] ||= [terms[i], terms[j]].freeze }
      terms.each_index.to_a.combination(3) do |i, j, k|
        result[words[i] ^ words[j] ^ words[k]] ||= [terms[i], terms[j], terms[k]].freeze
      end
      result.each_index do |bits|
        next if result[bits]
        result[bits] = 4.times.filter_map do |column|
          a = 4.times.sum { |i| bits[4 * i + column] << i }
          [a, 1 << (column / 2), 1 << (column % 2)].freeze unless a.zero?
        end.freeze
      end
      result.freeze
    end
  end

  # All shortest decompositions through rank three. Rank-four entries retain
  # only the elementary-column witness, not an exhaustive neutral orbit.
  def alternative_table
    @alternative_table ||= begin
      result = Array.new(65_536) { [] }
      terms = (1..15).to_a.product((1..3).to_a, (1..3).to_a).map(&:freeze)
      words = terms.map { |t| small_term(*t) }
      result[0] = [[]]
      terms.each_with_index { |t, i| result[words[i]] << [t].freeze }
      [2, 3].each do |size|
        terms.each_index.to_a.combination(size) do |ids|
          bits = ids.reduce(0) { |v, i| v ^ words[i] }
          result[bits] << ids.map { |i| terms[i] }.freeze if table[bits].length == size
        end
      end
      result.each_with_index { |rows, bits| rows << table[bits] if rows.empty?; rows.freeze }
      result.freeze
    end
  end

  def validate_terms(terms)
    raise "invalid nonzero binary terms" unless terms.is_a?(Array) && !terms.empty? && terms.all? do |t|
      t.is_a?(Array) && t.length == 3 && t.all? { |v| v.is_a?(Integer) && v.positive? && v.bit_length <= 256 }
    end
  end

  def plane(values)
    a = values.first
    b = values.find { |v| v != a } || 0
    palette = [0, a, b, a ^ b]
    codes = values.map { |v| palette.index(v) }
    codes.include?(nil) ? nil : [[a, b], codes]
  end

  # Return an exact <=4-term decomposition, or nil when a small axis does
  # not fit a plane. The chosen basis consists of original tensor columns,
  # not necessarily original first factors.
  def encode(terms, axis)
    validate_terms(terms)
    raise "invalid factor axis" unless (0..2).include?(axis)
    others = (0..2).to_a - [axis]
    small = others.map { |a| plane(terms.map { |t| t[a] }) }
    return nil if small.include?(nil)
    columns = Array.new(4, 0)
    terms.each_with_index do |t, i|
      b, c = small.map { |entry| entry[1][i] }
      2.times { |j| 2.times { |k| columns[2 * j + k] ^= t[axis] if (b[j] & c[k]) == 1 } }
    end
    rows = {}; basis = []; codes = []
    columns.each do |column|
      remainder = column; code = 0
      rows.keys.sort.reverse_each do |pivot|
        next unless remainder[pivot] == 1
        row, combination = rows.fetch(pivot)
        remainder ^= row; code ^= combination
      end
      unless remainder.zero?
        bit = 1 << basis.length
        basis << column
        rows[remainder.bit_length - 1] = [remainder, code ^ bit]
        code = bit
      end
      codes << code
    end
    bits = 4.times.sum { |i| 4.times.sum { |j| codes[j][i] << (4 * i + j) } }
    { axis: axis, others: others, small: small, basis: basis, tensor: bits }
  end

  def lift(row, encoding)
    axis, others, small, basis = encoding.values_at(:axis, :others, :small, :basis)
    row.map do |a, b, c|
      t = [0, 0, 0]
      t[axis] = basis.each_with_index.reduce(0) { |v, (word, i)| v ^ (a[i] == 1 ? word : 0) }
      others.zip([b, c], small).each do |other, code, entry|
        t[other] = entry[0].each_with_index.reduce(0) { |v, (word, i)| v ^ (code[i] == 1 ? word : 0) }
      end
      t
    end.reject { |t| t.include?(0) }
  end

  def replacement(terms, axis)
    encoding = encode(terms, axis)
    return nil unless encoding
    result = lift(table[encoding[:tensor]], encoding)
    raise "pocket rank grew" if result.length > terms.length
    { replacement: result, dimension: encoding[:basis].length, tensor: encoding[:tensor] }
  end

  def alternatives(terms, axis)
    encoding = encode(terms, axis)
    return nil unless encoding
    alternative_table[encoding[:tensor]].map { |row| lift(row, encoding).sort }.uniq
  end

  # Enumerate maximal pockets whose two small spans each have dimension two.
  # Any such pocket contains two occupied cells differing on both axes,
  # unless all its cells share one factor (handled by matrix compression).
  # Choose that pair canonically, avoiding an O(rank^2) retained seen-set.
  def each_pocket(terms)
    validate_terms(terms)
    return enum_for(__method__, terms) unless block_given?
    3.times do |axis|
      others = (0..2).to_a - [axis]
      cells = terms.each_index.group_by { |i| others.map { |a| terms[i][a] } }
      keys = cells.keys.sort
      keys.combination(2) do |left, right|
        next if left[0] == right[0] || left[1] == right[1]
        palettes = 2.times.map { |a| [left[a], right[a], left[a] ^ right[a]].sort }
        occupied = palettes[0].product(palettes[1]).select { |cell| cells.key?(cell) }
        next if occupied.sum { |cell| cells.fetch(cell).length } < 3
        canonical = occupied.combination(2).find { |x, y| x[0] != y[0] && x[1] != y[1] }
        next unless canonical == [left, right]
        yield axis, occupied.flat_map { |cell| cells.fetch(cell) }.sort
      end
    end
  end

  def scan(terms)
    best = nil; histogram = Hash.new(0); dimensions = Hash.new(0); pockets = 0
    each_pocket(terms) do |axis, ids|
      old = ids.map { |i| terms[i] }
      row = replacement(old, axis)
      raise "indexed pocket outside plane" unless row
      pockets += 1; histogram[ids.length] += 1; dimensions[row[:dimension]] += 1
      next unless row[:replacement].length < ids.length
      key = [row[:replacement].length - ids.length, row[:replacement].flatten.sum { |v| v.to_s(2).count("1") }, axis, ids]
      if !best || (key <=> best[:key]) == -1
        best = row.merge(axis: axis, indices: ids, key: key)
      end
    end
    { pockets: pockets, sizes: histogram.sort.to_h, dimensions: dimensions.sort.to_h, best: best }
  end

  # Finite exact-macro neighborhood: shortest pocket decompositions followed
  # by whole-state shared-factor compression. Only strictly better rank or
  # coefficient-density endpoints are returned. The caller admits the winner.
  def scan_variants(terms)
    best = nil; pockets = 0; variants = 0; distinct = 0; reductions = 0
    initial_key = [terms.length, terms.flatten.sum { |v| v.to_s(2).count("1") }]
    each_pocket(terms) do |axis, ids|
      pockets += 1
      old = ids.map { |i| terms[i] }.sort
      rest = nil
      alternatives(old, axis).each do |replacement|
        variants += 1
        next if replacement == old
        distinct += 1
        rest ||= terms.each_with_index.filter_map { |t, i| t unless ids.include?(i) }
        candidate, history = MetaflipSharedFactorCompression.compress_terms(rest + replacement)
        key = [candidate.length, candidate.flatten.sum { |v| v.to_s(2).count("1") }]
        reductions += 1 if key[0] < initial_key[0]
        next unless (key <=> initial_key) == -1
        if !best || (key <=> best[:key]) == -1
          best = { axis: axis, indices: ids, replacement: replacement,
            terms: candidate, compression: history, key: key }
        end
      end
    end
    { pockets: pockets, variants: variants, distinct: distinct, reductions: reductions, best: best }
  end
end
