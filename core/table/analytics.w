+ Table
  # ------------------------------------------------------------ statistics --

  -> __numeric_column?(j)
    seen = false
    i = 0
    while i < @rows
      v = @cols[j][i]
      if v != nil
        return false if !Table.numeric?(v)
        seen = true
      i += 1
    seen

  -> numeric_columns
    out = []
    j = 0
    while j < @names.size
      out.push(@names[j]) if __numeric_column?(j)
      j += 1
    out

  -> __values(name)
    pos = __require(name)
    out = []
    i = 0
    while i < @rows
      out.push(@cols[pos][i]) if @cols[pos][i] != nil
      i += 1
    out

  -> __numeric_values(name)
    values = __values(name)
    i = 0
    while i < values.size
      if !Table.numeric?(values[i])
        raise "Table column '" + Table.normalize_name(name).to_s + "' is not numeric"
      i += 1
    values

  # Hash of name => the aggregation applied to every numeric column.
  -> aggregate(agg)
    out = {}
    names = numeric_columns
    i = 0
    while i < names.size
      out[names[i]] = Table.reduce_values(__numeric_values(names[i]), agg)
      i += 1
    out

  -> __agg(name, agg)
    return @rows if name == nil && agg == :count
    Table.reduce_values(__numeric_values(name), agg)

  -> count
    @rows

  -> counts
    out = {}
    j = 0
    while j < @names.size
      out[@names[j]] = counts(@names[j])
      j += 1
    out

  -> counts(name)
    __values(name).size

  -> sum
    aggregate(:sum)

  -> sum(name)
    Table.sum_values(__numeric_values(name))

  -> mean
    aggregate(:mean)

  -> mean(name)
    Table.mean_values(__numeric_values(name))

  -> min
    aggregate(:min)

  -> min(name)
    Table.min_values(__numeric_values(name))

  -> max
    aggregate(:max)

  -> max(name)
    Table.max_values(__numeric_values(name))

  -> median
    aggregate(:median)

  -> median(name)
    Table.median_values(__numeric_values(name))

  -> product
    aggregate(:product)

  -> product(name)
    Table.product_values(__numeric_values(name))

  -> variance
    aggregate(:variance)

  -> variance(name)
    Table.variance_values(__numeric_values(name))

  -> std(name)
    v = variance(name)
    return nil if v == nil
    Math.sqrt(v.to_f)

  # Most frequent value, ties broken by first appearance. Works on any column.
  -> mode
    out = {}
    j = 0
    while j < @names.size
      out[@names[j]] = mode(@names[j])
      j += 1
    out

  -> mode(name)
    values = __values(name)
    return nil if values.size == 0
    order = []
    tally = {}
    i = 0
    while i < values.size
      sig = type(values[i]) + ":" + Table.render(values[i])
      if !tally.has_key?(sig)
        tally[sig] = 0
        order.push(sig)
      tally[sig] = tally[sig] + 1
      i += 1
    best = order[0]
    i = 1
    while i < order.size
      best = order[i] if tally[order[i]] > tally[best]
      i += 1
    i = 0
    while i < values.size
      sig = type(values[i]) + ":" + Table.render(values[i])
      return values[i] if sig == best
      i += 1
    nil

  # q in 0..1, linear interpolation between order statistics.
  -> quantile(q)
    out = {}
    names = numeric_columns
    i = 0
    while i < names.size
      out[names[i]] = quantile(names[i], q)
      i += 1
    out

  -> quantile(name, q)
    values = __numeric_values(name).sort
    return nil if values.size == 0
    n = values.size
    if q <= 0
      return values[0]
    if q >= 1
      return values[n - 1]
    spot = (q + 0.to_d) * (n - 1)
    low = spot.to_i
    high = low + 1
    return values[low] if high >= n
    weight = spot - low
    values[low] + (values[high] - values[low]) * weight

  # 1-based competition ranking: ties share the lowest rank.
  -> rank(name)
    pos = __require(name)
    values = []
    i = 0
    while i < @rows
      values.push(@cols[pos][i])
      i += 1
    ordered = values.dup.sort
    out = []
    i = 0
    while i < values.size
      spot = 0
      k = 0
      while k < ordered.size
        if ordered[k] == values[i]
          spot = k
          k = ordered.size
        else
          k += 1
      out.push(spot + 1)
      i += 1
    out

  -> skew(name)
    values = __numeric_values(name)
    n = values.size
    return nil if n < 3
    m = Table.mean_values(values).to_f
    s2 = 0.0.to_f
    s3 = 0.0.to_f
    i = 0
    while i < n
      d = values[i].to_f - m
      s2 = s2 + d * d
      s3 = s3 + d * d * d
      i += 1
    variance = s2 / (n - 1).to_f
    return nil if variance == 0.0.to_f
    sd = Math.sqrt(variance)
    (n.to_f / ((n - 1).to_f * (n - 2).to_f)) * (s3 / (sd * sd * sd))

  # Excess kurtosis (normal distribution = 0), sample-corrected.
  -> kurtosis(name)
    values = __numeric_values(name)
    n = values.size
    return nil if n < 4
    m = Table.mean_values(values).to_f
    s2 = 0.0.to_f
    s4 = 0.0.to_f
    i = 0
    while i < n
      d = values[i].to_f - m
      s2 = s2 + d * d
      s4 = s4 + d * d * d * d
      i += 1
    variance = s2 / (n - 1).to_f
    return nil if variance == 0.0.to_f
    nf = n.to_f
    scale = (nf * (nf + 1.0.to_f)) / ((nf - 1.0.to_f) * (nf - 2.0.to_f) * (nf - 3.0.to_f))
    tail = (3.0.to_f * (nf - 1.0.to_f) * (nf - 1.0.to_f)) / ((nf - 2.0.to_f) * (nf - 3.0.to_f))
    scale * (s4 / (variance * variance)) - tail

  -> covariance(a, b)
    xs = __numeric_values(a)
    ys = __numeric_values(b)
    if xs.size != ys.size
      raise "Table#covariance needs columns without nil gaps"
    n = xs.size
    return nil if n < 2
    mx = Table.mean_values(xs)
    my = Table.mean_values(ys)
    total = 0.to_d
    i = 0
    while i < n
      total = total + (xs[i] - mx) * (ys[i] - my)
      i += 1
    total / (n - 1)

  -> correlation(a, b)
    cov = covariance(a, b)
    return nil if cov == nil
    sa = std(a)
    sb = std(b)
    return nil if sa == nil || sb == nil
    return nil if sa == 0 || sb == 0
    cov.to_f / (sa * sb)

  # Square matrix over the numeric columns, with a :column label column.
  -> covariance
    __pairwise(:covariance)

  -> correlation
    __pairwise(:correlation)

  -> __pairwise(kind)
    names = numeric_columns
    result_names = [:column]
    cols = [names.dup]
    j = 0
    while j < names.size
      col = []
      i = 0
      while i < names.size
        if kind == :covariance
          col.push(covariance(names[i], names[j]))
        else
          col.push(correlation(names[i], names[j]))
        i += 1
      result_names.push(names[j])
      cols.push(col)
      j += 1
    t = Table.build(result_names, cols, nil)
    t.__set_rows(names.size)
    t

  # Running aggregate down each numeric column (:sum, :product, :min, :max).
  -> cumulative(agg)
    cols = []
    j = 0
    while j < @names.size
      if __numeric_column?(j)
        col = @cols[j]
        out = []
        acc = nil
        i = 0
        while i < @rows
          v = col[i]
          if v == nil
            out.push(acc)
          elsif acc == nil
            acc = v
            out.push(acc)
          else
            acc = Table.combine(acc, v, agg)
            out.push(acc)
          i += 1
        cols.push(out)
      else
        cols.push(@cols[j].dup)
      j += 1
    t = Table.build(@names.dup, cols, __index_copy)
    t.__set_rows(@rows)
    t

  -> .combine(acc, v, agg)
    return acc + v if agg == :sum
    return acc * v if agg == :product
    if agg == :min
      return v if v < acc
      return acc
    if agg == :max
      return v if v > acc
      return acc
    raise "Unknown cumulative aggregation '" + agg.to_s + "'; use sum, product, min or max"

  # Row-to-row differences in each numeric column; the first n rows are nil.
  -> diff
    diff(1)

  -> diff(n)
    cols = []
    j = 0
    while j < @names.size
      if __numeric_column?(j)
        col = @cols[j]
        out = []
        i = 0
        while i < @rows
          from = i - n
          if from < 0 || from >= @rows || col[i] == nil || col[from] == nil
            out.push(nil)
          else
            out.push(col[i] - col[from])
          i += 1
        cols.push(out)
      else
        cols.push(@cols[j].dup)
      j += 1
    t = Table.build(@names.dup, cols, __index_copy)
    t.__set_rows(@rows)
    t

  # Numeric columns get equal-width bins (:lower, :upper, :count); anything
  # else gets a frequency table (:value, :count).
  -> histogram(name)
    histogram(name, 10)

  -> histogram(name, bins)
    pos = __require(name)
    if !__numeric_column?(pos)
      return __frequency(pos)
    values = __numeric_values(name)
    if values.size == 0
      t = Table.build([:lower, :upper, :count], [[], [], []], nil)
      return t
    low = Table.min_values(values)
    high = Table.max_values(values)
    span = high - low
    span = 1 if span == 0
    width = (span + 0.to_d) / bins
    lowers = []
    uppers = []
    tally = []
    b = 0
    while b < bins
      lowers.push(low + width * b)
      uppers.push(low + width * (b + 1))
      tally.push(0)
      b += 1
    i = 0
    while i < values.size
      slot = ((values[i] - low + 0.to_d) / width).to_i
      slot = bins - 1 if slot >= bins
      slot = 0 if slot < 0
      tally[slot] = tally[slot] + 1
      i += 1
    t = Table.build([:lower, :upper, :count], [lowers, uppers, tally], nil)
    t.__set_rows(bins)
    t

  -> __frequency(pos)
    order = []
    labels = {}
    tally = {}
    i = 0
    while i < @rows
      v = @cols[pos][i]
      sig = type(v) + ":" + Table.render(v)
      if !tally.has_key?(sig)
        tally[sig] = 0
        labels[sig] = v
        order.push(sig)
      tally[sig] = tally[sig] + 1
      i += 1
    values = []
    counts = []
    i = 0
    while i < order.size
      values.push(labels[order[i]])
      counts.push(tally[order[i]])
      i += 1
    t = Table.build([:value, :count], [values, counts], nil)
    t.__set_rows(order.size)
    t

  # count / mean / min / max for every numeric column, one row per statistic.
  -> describe
    names = numeric_columns
    stats = ["count", "mean", "min", "max"]
    result_names = [:statistic]
    cols = [stats.dup]
    j = 0
    while j < names.size
      values = __numeric_values(names[j])
      col = [values.size, Table.mean_values(values), Table.min_values(values), Table.max_values(values)]
      result_names.push(names[j])
      cols.push(col)
      j += 1
    t = Table.build(result_names, cols, nil)
    t.__set_rows(stats.size)
    t

  -> all
    j = 0
    while j < @names.size
      i = 0
      while i < @rows
        return false if !Table.truthy?(@cols[j][i])
        i += 1
      j += 1
    true

  -> any
    j = 0
    while j < @names.size
      i = 0
      while i < @rows
        return true if Table.truthy?(@cols[j][i])
        i += 1
      j += 1
    false

  # ------------------------------------------------------------- cashflows --

  # Net present value of a cashflow column, one period per row.
  -> npv(rate, name)
    values = __numeric_values(name)
    total = 0.to_d
    discount = 1.to_d
    factor = 1 + rate
    i = 0
    while i < values.size
      total = total + values[i] / discount
      discount = discount * factor
      i += 1
    total

  # Internal rate of return: the rate where npv is zero. Bisection on
  # (-0.999999, 100), nil when the cashflows never change sign.
  -> irr(name)
    values = __numeric_values(name)
    return nil if !Table.signs_change?(values)
    low = -0.999999.to_f
    high = 100.0.to_f
    i = 0
    while i < 200
      mid = (low + high) / 2.0.to_f
      if Table.npv_at(values, mid) > 0.0.to_f
        low = mid
      else
        high = mid
      i += 1
    (low + high) / 2.0.to_f

  # Cashflows dated by day offsets, discounted on a 365-day year.
  -> xnpv(rate, name, days_name)
    values = __numeric_values(name)
    days = __numeric_values(days_name)
    if values.size != days.size
      raise "Table#xnpv needs value and day columns of equal length"
    Table.xnpv_at(values, days, rate.to_f)

  -> xirr(name, days_name)
    values = __numeric_values(name)
    days = __numeric_values(days_name)
    return nil if !Table.signs_change?(values)
    low = -0.999999.to_f
    high = 100.0.to_f
    i = 0
    while i < 200
      mid = (low + high) / 2.0.to_f
      if Table.xnpv_at(values, days, mid) > 0.0.to_f
        low = mid
      else
        high = mid
      i += 1
    (low + high) / 2.0.to_f

  -> .signs_change?(values)
    positive = false
    negative = false
    i = 0
    while i < values.size
      positive = true if values[i] > 0
      negative = true if values[i] < 0
      i += 1
    positive && negative

  -> .npv_at(values, rate)
    total = 0.0.to_f
    discount = 1.0.to_f
    factor = 1.0.to_f + rate
    i = 0
    while i < values.size
      total = total + values[i].to_f / discount
      discount = discount * factor
      i += 1
    total

  -> .xnpv_at(values, days, rate)
    total = 0.0.to_f
    base = 1.0.to_f + rate
    start = days[0].to_f
    i = 0
    while i < values.size
      years = (days[i].to_f - start) / 365.0.to_f
      total = total + values[i].to_f / Math.exp(years * Math.log(base))
      i += 1
    total

  # -------------------------------------------------- column-wise reducers --

  -> .sum_values(values)
    return 0 if values.size == 0
    total = values[0]
    i = 1
    while i < values.size
      total = total + values[i]
      i += 1
    total

  -> .product_values(values)
    return 1 if values.size == 0
    total = values[0]
    i = 1
    while i < values.size
      total = total * values[i]
      i += 1
    total

  # Exact where the language is: the accumulator starts as a Decimal so an Int
  # column never falls into integer division.
  -> .mean_values(values)
    return nil if values.size == 0
    total = 0.to_d
    i = 0
    while i < values.size
      total = total + values[i]
      i += 1
    total / values.size

  -> .min_values(values)
    return nil if values.size == 0
    best = values[0]
    i = 1
    while i < values.size
      best = values[i] if values[i] < best
      i += 1
    best

  -> .max_values(values)
    return nil if values.size == 0
    best = values[0]
    i = 1
    while i < values.size
      best = values[i] if values[i] > best
      i += 1
    best

  -> .median_values(values)
    return nil if values.size == 0
    sorted = values.dup.sort
    n = sorted.size
    return sorted[n / 2] if n % 2 == 1
    (sorted[n / 2 - 1] + sorted[n / 2] + 0.to_d) / 2

  -> .variance_values(values)
    n = values.size
    return nil if n < 2
    m = Table.mean_values(values)
    total = 0.to_d
    i = 0
    while i < n
      d = values[i] - m
      total = total + d * d
      i += 1
    total / (n - 1)

  # ------------------------------------------------------------ arithmetic --

  -> +(other)
    __elementwise(other, :add)

  -> -(other)
    __elementwise(other, :subtract)

  -> *(other)
    __elementwise(other, :multiply)

  -> /(other)
    __elementwise(other, :divide)

  -> %(other)
    __elementwise(other, :mod)

  -> add(other)
    __elementwise(other, :add)

  -> subtract(other)
    __elementwise(other, :subtract)

  -> multiply(other)
    __elementwise(other, :multiply)

  -> divide(other)
    __elementwise(other, :divide)

  -> mod(other)
    __elementwise(other, :mod)

  # A scalar applies to every numeric cell; a Table applies cell by cell and
  # must have the same column names in the same order and the same row count.
  -> __elementwise(other, op)
    scalar = type(other) != "Table"
    if scalar
      if !Table.numeric?(other)
        raise "Table arithmetic needs a number or a Table on the right, got " + type(other)
    else
      if other.columns != @names
        raise "Table arithmetic needs matching columns: " + Table.name_list(@names) + " vs " + Table.name_list(other.columns)
      if other.size != @rows
        raise "Table arithmetic needs matching row counts: " + @rows.to_s + " vs " + other.size.to_s
    cols = []
    j = 0
    while j < @names.size
      col = @cols[j]
      right = nil
      right = other.column(@names[j]) if !scalar
      out = []
      i = 0
      while i < @rows
        left = col[i]
        rv = other
        rv = right[i] if !scalar
        if left == nil || rv == nil || !Table.numeric?(left) || !Table.numeric?(rv)
          out.push(left)
        else
          out.push(Table.apply_op(left, rv, op))
        i += 1
      cols.push(out)
      j += 1
    t = Table.build(@names.dup, cols, __index_copy)
    t.__set_rows(@rows)
    t

  -> .apply_op(a, b, op)
    return a + b if op == :add
    return a - b if op == :subtract
    return a * b if op == :multiply
    return a / b if op == :divide
    return a % b if op == :mod
    raise "Unknown Table operation '" + op.to_s + "'"

  # Matrix product: self's numeric columns against other's numeric rows. The
  # result's columns are other's.
  -> dot(other)
    left = numeric_columns
    right = other.columns
    if left.size != other.size
      raise "Table#dot needs " + left.size.to_s + " rows on the right, got " + other.size.to_s
    cols = []
    j = 0
    while j < right.size
      rc = other.column(right[j])
      col = []
      i = 0
      while i < @rows
        total = 0
        k = 0
        while k < left.size
          total = total + at(i, left[k]) * rc[k]
          k += 1
        col.push(total)
        i += 1
      cols.push(col)
      j += 1
    t = Table.build(right.dup, cols, __index_copy)
    t.__set_rows(@rows)
    t

  # --------------------------------------------------------------- export --

  -> to_a
    out = []
    i = 0
    while i < @rows
      out.push(row(i))
      i += 1
    out

  -> to_records
    to_a

  -> to_h
    out = {}
    j = 0
    while j < @names.size
      out[@names[j]] = @cols[j].dup
      j += 1
    out

  -> to_csv
    to_csv(",")

  -> to_csv(separator)
    buf = StringBuffer(64)
    n_cols = @names.size
    j = 0
    while j < n_cols
      buf << separator if j > 0
      Table.csv_field_into(@names[j].to_s, separator, buf)
      j += 1
    buf << "\n"
    i = 0
    while i < @rows
      j = 0
      while j < n_cols
        buf << separator if j > 0
        Table.csv_field_into(Table.render(@cols[j][i]), separator, buf)
        j += 1
      buf << "\n"
      i += 1
    buf.to_s

  -> .csv_field_into(s, separator, buf_in)
    buf = buf_in ## StringBuffer
    str = s ## String
    sep = separator ## String
    view = ccall("w_string_bytes_view", str) ## u8[]
    n = view.size ## i64
    if n == 0
      return nil
    sep_view = ccall("w_string_bytes_view", sep) ## u8[]
    sep_n = sep_view.size ## i64
    sep_b = sep_view[0]
    needs = false
    if sep_n == 1
      i = 0
      while i < n
        b = view[i]
        if b == sep_b || b == 34 || b == 10 || b == 13
          needs = true
          break
        i += 1
    else
      needs = true if str.contains?(sep)
      needs = true if str.contains?("\"")
      needs = true if str.contains?("\n")
      needs = true if str.contains?("\r")
    if !needs
      buf << str
      return nil
    buf << "\""
    run_start = 0
    i = 0
    while i < n
      if view[i] == 34
        buf << str.slice(run_start, i - run_start) if i > run_start
        buf << "\"\""
        run_start = i + 1
      i += 1
    buf << str.slice(run_start, n - run_start) if n > run_start
    buf << "\""
    nil

  -> .csv_field(s, separator)
    buf = StringBuffer(32)
    Table.csv_field_into(s, separator, buf)
    buf.to_s

  -> to_json
    buf = StringBuffer(64)
    buf << "\["
    n_cols = @names.size
    key_prefixes = []
    j = 0
    while j < n_cols
      pbuf = StringBuffer(32)
      if j == 0
        pbuf << "{"
      else
        pbuf << ","
      Table.json_string_into(@names[j].to_s, pbuf)
      pbuf << ":"
      key_prefixes.push(pbuf.to_s)
      j += 1
    i = 0
    while i < @rows
      buf << "," if i > 0
      if n_cols == 0
        buf << "{}"
      else
        j = 0
        while j < n_cols
          buf << key_prefixes[j]
          Table.json_value_into(@cols[j][i], buf)
          j += 1
        buf << "}"
      i += 1
    buf << "\]"
    buf.to_s

  -> .json_value_into(v, buf_in)
    buf = buf_in ## StringBuffer
    if v == nil
      buf << "null"
      return nil
    if v == true
      buf << "true"
      return nil
    if v == false
      buf << "false"
      return nil
    if Table.numeric?(v)
      buf << v.to_s
      return nil
    Table.json_string_into(v.to_s, buf)

  -> .json_string_into(s, buf_in)
    buf = buf_in ## StringBuffer
    str = s ## String
    view = ccall("w_string_bytes_view", str) ## u8[]
    n = view.size ## i64
    buf << "\""
    run_start = 0
    i = 0
    while i < n
      b = view[i]
      if b == 34 || b == 92 || b == 10 || b == 13 || b == 9
        buf << str.slice(run_start, i - run_start) if i > run_start
        if b == 34
          buf << "\\\""
        elsif b == 92
          buf << "\\\\"
        elsif b == 10
          buf << "\\n"
        elsif b == 13
          buf << "\\r"
        else
          buf << "\\t"
        run_start = i + 1
      i += 1
    if run_start == 0
      buf << str
    elsif n > run_start
      buf << str.slice(run_start, n - run_start)
    buf << "\""
    nil

  -> .json_value(v)
    return "null" if v == nil
    return "true" if v == true
    return "false" if v == false
    return v.to_s if Table.numeric?(v)
    Table.json_string(v.to_s)

  -> .json_string(s)
    buf = StringBuffer(32)
    Table.json_string_into(s, buf)
    buf.to_s

  -> to_html
    out = "<table>\n  <thead>\n    <tr>"
    j = 0
    while j < @names.size
      out += "<th>" + Table.xml_escape(@names[j].to_s) + "</th>"
      j += 1
    out += "</tr>\n  </thead>\n  <tbody>\n"
    i = 0
    while i < @rows
      out += "    <tr>"
      j = 0
      while j < @names.size
        out += "<td>" + Table.xml_escape(Table.render(@cols[j][i])) + "</td>"
        j += 1
      out += "</tr>\n"
      i += 1
    out + "  </tbody>\n</table>"

  -> to_xml
    to_xml("row")

  -> to_xml(row_tag)
    out = "<table>\n"
    i = 0
    while i < @rows
      out += "  <" + row_tag + ">\n"
      j = 0
      while j < @names.size
        tag = @names[j].to_s
        out += "    <" + tag + ">" + Table.xml_escape(Table.render(@cols[j][i])) + "</" + tag + ">\n"
        j += 1
      out += "  </" + row_tag + ">\n"
      i += 1
    out + "</table>"

  -> .xml_escape(s)
    out = ""
    i = 0
    while i < s.size
      ch = s[i]
      if ch == "&"
        out += "&amp;"
      elsif ch == "<"
        out += "&lt;"
      elsif ch == ">"
        out += "&gt;"
      else
        out += ch
      i += 1
    out

  # One INSERT statement per row. Strings are single-quoted with doubled
  # quotes; no connection is opened.
  -> to_sql(table_name)
    out = ""
    i = 0
    while i < @rows
      out += "INSERT INTO " + table_name + " ("
      j = 0
      while j < @names.size
        out += ", " if j > 0
        out += @names[j].to_s
        j += 1
      out += ") VALUES ("
      j = 0
      while j < @names.size
        out += ", " if j > 0
        out += Table.sql_value(@cols[j][i])
        j += 1
      out += ");\n"
      i += 1
    out

  -> .sql_value(v)
    return "NULL" if v == nil
    return v.to_s if Table.numeric?(v)
    return "TRUE" if v == true
    return "FALSE" if v == false
    s = v.to_s
    out = "'"
    i = 0
    while i < s.size
      ch = s[i]
      out += "'" if ch == "'"
      out += ch
      i += 1
    out + "'"

  # -------------------------------------------------------------- printing --

  -> to_s
    return "(0 rows, 0 columns)" if @names.size == 0
    labels = []
    raw = index
    i = 0
    while i < @rows
      labels.push(Table.render(raw[i]))
      i += 1
    label_width = 1
    i = 0
    while i < labels.size
      label_width = labels[i].size if labels[i].size > label_width
      i += 1
    widths = []
    right = []
    cells = []
    j = 0
    while j < @names.size
      w = @names[j].to_s.size
      column_cells = []
      i = 0
      while i < @rows
        s = Table.render(@cols[j][i])
        w = s.size if s.size > w
        column_cells.push(s)
        i += 1
      widths.push(w)
      right.push(__numeric_column?(j))
      cells.push(column_cells)
      j += 1
    line = "#".rpad(label_width)
    j = 0
    while j < @names.size
      if right[j]
        line += " | " + @names[j].to_s.lpad(widths[j])
      else
        line += " | " + @names[j].to_s.rpad(widths[j])
      j += 1
    out = Table.trim_right(line)
    line = Table.dashes(label_width)
    j = 0
    while j < @names.size
      line += "-+-" + Table.dashes(widths[j])
      j += 1
    out += "\n" + line
    i = 0
    while i < @rows
      line = labels[i].rpad(label_width)
      j = 0
      while j < @names.size
        if right[j]
          line += " | " + cells[j][i].lpad(widths[j])
        else
          line += " | " + cells[j][i].rpad(widths[j])
        j += 1
      out += "\n" + Table.trim_right(line)
      i += 1
    out

  -> .dashes(n)
    out = ""
    i = 0
    while i < n
      out += "-"
      i += 1
    out

  -> .trim_right(s)
    stop = s.size
    while stop > 0 && s[stop - 1] == " "
      stop -= 1
    return s if stop == s.size
    out = ""
    i = 0
    while i < stop
      out += s[i]
      i += 1
    out

  -> inspect
    to_s + "\n(" + @rows.to_s + " rows, " + @names.size.to_s + " columns)"

  # ------------------------------------------------------------- equality --

  -> ==(other)
    return false if type(other) != "Table"
    return false if other.columns != @names
    return false if other.size != @rows
    j = 0
    while j < @names.size
      mine = @cols[j]
      theirs = other.column(@names[j])
      i = 0
      while i < @rows
        return false if mine[i] != theirs[i]
        i += 1
      j += 1
    true

  -> eql?(other)
    self == other

