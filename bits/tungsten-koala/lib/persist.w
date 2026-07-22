# Persist — save a FITTED koala model to text and load it back, with the
# guarantee that the loaded model predicts IDENTICALLY to the saved one.
#
#     text  = Persist.dumps(model)      # a String, or nil
#     again = Persist.loads(text)       # the model, or nil
#     again.predict(x) == model.predict(x)      # element for element, exactly
#
# Every fitted koala object round-trips: LinearRegression, KNNClassifier,
# LogisticRegression, GaussianNB, KMeans, DecisionTreeClassifier,
# DecisionTreeRegressor, the three transformers (Scaler / Imputer /
# Encoder) and a Pipeline of any of them, nested to any depth.
#
# --- Why a format of koala's own ---
#
# The requirement that decides the format is EXACT FLOAT FIDELITY: a
# reloaded coefficient that differs in its last bit is a different model,
# and a decision tree whose threshold moved by one ulp routes a query row
# down the other branch and predicts a different LABEL. So the format has
# to reproduce an f64 bit for bit, and it has to do so on both engines.
#
# `Float#to_s` cannot: it prints SIX significant digits on both the
# interpreter and the compiler, so `(1.to_f / 3.to_f).to_s.to_f` is NOT
# the value it came from — measured, not assumed. There is no
# printf-style formatter to ask for more (`format` is undefined, `"%.17g"
# % v` is not an operator here, `to_s(17)` ignores its argument), so no
# amount of care with a decimal encoder — and no JSON encoder built on
# one — can carry an f64 across intact. A sibling bit's `Undefined method
# 'encode_string'` from core `JSON.encode` under the interpreter is a
# second reason not to lean on one, but the float problem alone settles
# it.
#
# What IS available on both engines is exact ARITHMETIC. Multiplying or
# dividing an f64 by two is exact in IEEE754, and `Float#floor` gives an
# integer. So a finite float is written as its own bits, in four small
# integers:
#
#     b <neg> <e> <hi> <lo>          v = (-1)^neg * (hi/2^27 + lo/2^53) * 2^e
#
# where the mantissa is normalized into [0.5, 1) by exact halving/doubling
# and then split across TWO integers — hi < 2^27 and lo < 2^26 — because
# the interpreter's integers are 48-bit and a 53-bit mantissa does not fit
# in one. Reading it back re-divides by powers of two, every step exact,
# and lands on the identical double. Verified on both engines over
# 1/3, sqrt(2), -22/7, e, log(7)/3 and 1/(7*13): all round-trip with `==`.
#
# A float whose SHORT decimal form already round-trips (checked, not
# assumed — `s.to_f == v`) is written as `d <decimal>` instead, so the
# common 0 / 1 / 2.5 / -3 stay readable in the payload. The check is what
# makes that safe: a value takes the readable form only when the engine
# itself confirms the text reproduces it.
#
# NaN and the infinities have no bits form (they would not normalize), so
# they get their own tags — `w Q`, `w P`, `w M`. A model should never hold
# one, but a format that hangs or lies on one is not a format.
#
# --- The format ---
#
# A line-oriented DEPTH-FIRST token stream, `\n`-joined. The first line is
# the version stamp; every later line is one node, tagged by its first
# character:
#
#     koala-model 1     the header: name and format VERSION
#     z                 nil
#     T / F             true / false
#     i <int>           Integer
#     d <decimal>       Float, short decimal (only when it round-trips)
#     b <neg> <e> <hi> <lo>   Float, exact bits (see above)
#     w Q / w P / w M   NaN / +inf / -inf
#     s <text>          String   (\ and newline backslash-escaped)
#     y <text>          Symbol   (same escaping)
#     a <n>             Array, followed by n nodes
#     h <n>             Hash, followed by n KEY, VALUE node pairs
#     o <ClassName>     a koala object, followed by ONE `h` node — its state
#
# Hash keys are emitted in sorted order (by `to_s`), so a payload is
# DETERMINISTIC and byte-identical on both engines rather than inheriting
# whatever order `Hash#keys` happens to give. A decision tree needs no
# special case at all: its nodes are plain hashes holding plain hashes,
# which is exactly what `h` encodes.
#
# --- nil, never a crash ---
#
# `dumps` answers nil for anything it cannot save — a nil, a plain value,
# an object outside the table below, or a model that is NOT FITTED (there
# is no state to write, and a payload that pretended otherwise would load
# as a model claiming to be fitted).
#
# `loads` answers nil for: a missing or wrong version stamp, a class name
# it does not know, a truncated stream, trailing junk, a state that is not
# a hash, and a state missing what its class needs. That last one is the
# guard against a payload written by a DIFFERENT estimator: the class name
# selects the loader, and the loader checks that the state actually
# carries its own learned fields, so a LinearRegression body relabelled
# `KNNClassifier` loads as nil rather than as a KNN that quietly answers
# predictions.
#
# --- Strings only ---
#
# There are no file helpers, deliberately: `File` (and `IO`) are undefined
# on the interpreter and only exist compiled, so a `Persist.save(model,
# path)` would work on one engine and raise on the other. Writing the
# string is the caller's job, on whichever side of the bit has file
# access:
#
#     text = Persist.dumps(model)
#     # ... hand `text` to whatever storage you have ...
#     model = Persist.loads(text)
#
# --- Adding a class ---
#
# A persistable class answers three things — `persist_name` (its tag in
# the payload), `to_state` (a hash of hyperparameters AND learned state)
# and a class-level `.load_state(state)` that rebuilds a FITTED instance
# or nil — and gets one line in `Persist.rebuild` below. `to_state` is
# also how Persist RECOGNIZES an object: `respond_to?("to_state")`,
# behaviour rather than `type`, because `type(obj)` on an instance is
# "Hash" on the interpreter and cannot tell an object from a hash.
#
# NOTE: no float literal appears here (every float derives via .to_f), no
# `return` sits inside a closure-bearing method, arrays are built with
# push, and respond_to? is passed a STRING — the bit's portability rules.
+ Persist
  # The format version this build writes, and the only one it reads.
  -> .version
    1

  # The payload's first line — name and version in one stamp.
  -> .header
    "koala-model " + Persist.version.to_s

  # --- The public pair ---

  # `model` as a self-contained String, or nil when it cannot be saved:
  # nil, a non-koala value, a class outside the table, or a model that has
  # not been fitted.
  -> .dumps(model)
    out = nil
    if Persist.persistable?(model)
      if model.fitted?
        lines = []
        lines.push(Persist.header)
        out = lines.join("\n") if Persist.encode(model, lines)
    out

  # The model `text` holds, or nil when text is not a payload this build
  # can read (see the header's nil list).
  -> .loads(text)
    out = nil
    if text != nil && type(text) == "String"
      lines = Persist.payload_lines(text)
      if lines.size > 1 && lines[0] == Persist.header
        res = Persist.decode(lines, 1)
        out = res[:v] if res[:ok] && res[:i] == lines.size
    out

  # `text` split into nodes, with TRAILING BLANK lines dropped. A payload
  # that has been through a file, a here-doc or a `<<` acquires a final
  # newline, and refusing to load it would make the format usable only by
  # the process that wrote it. Blank lines are not junk — every node line
  # carries a tag — so dropping them costs no strictness anywhere else:
  # trailing content that is not blank still fails, since the decoder must
  # finish on the LAST line.
  -> .payload_lines(text)
    raw = text.split("\n")
    n = raw.size
    while n > 0 && raw[n - 1] == ""
      n -= 1
    out = []
    i = 0
    while i < n
      out.push(raw[i])
      i += 1
    out

  # Is this something dumps can write? A koala object answers to_state,
  # persist_name and fitted? — all three, tested by BEHAVIOUR, because
  # type() cannot tell an instance from a hash on the interpreter.
  -> .persistable?(value)
    out = false
    if value != nil
      out = value.respond_to?("to_state") && value.respond_to?("persist_name") && value.respond_to?("fitted?")
    out

  # --- Class dispatch: name -> a rebuilt, fitted instance (or nil) ---
  #
  # Explicit rather than dynamic on purpose: an unknown name has to be a
  # clean nil, and there is no portable name-to-class lookup here anyway.
  -> .rebuild(name, state)
    out = nil
    out = LinearRegression.load_state(state) if name == "LinearRegression"
    out = Lasso.load_state(state) if name == "Lasso"
    out = ElasticNet.load_state(state) if name == "ElasticNet"
    out = KNNClassifier.load_state(state) if name == "KNNClassifier"
    out = LogisticRegression.load_state(state) if name == "LogisticRegression"
    out = GaussianNB.load_state(state) if name == "GaussianNB"
    out = KMeans.load_state(state) if name == "KMeans"
    out = DBSCAN.load_state(state) if name == "DBSCAN"
    out = DecisionTreeClassifier.load_state(state) if name == "DecisionTreeClassifier"
    out = DecisionTreeRegressor.load_state(state) if name == "DecisionTreeRegressor"
    out = RandomForestClassifier.load_state(state) if name == "RandomForestClassifier"
    out = RandomForestRegressor.load_state(state) if name == "RandomForestRegressor"
    out = Scaler.load_state(state) if name == "Scaler"
    out = PCA.load_state(state) if name == "PCA"
    out = Imputer.load_state(state) if name == "Imputer"
    out = Encoder.load_state(state) if name == "Encoder"
    out = Pipeline.load_state(state) if name == "Pipeline"
    out

  # --- Encoding ---

  # Append `value`'s node lines to `lines`; false when it holds something
  # the format has no node for.
  -> .encode(value, lines)
    out = false
    if value == nil
      lines.push("z")
      out = true
    else
      out = Persist.encode_value(value, lines)
    out

  # The non-nil half of encode. The OBJECT test comes before the hash test
  # because an instance answers type() "Hash" on the interpreter; the hash
  # test then excludes anything that looks like a koala object it could
  # not encode, so a stray unsupported instance is a clean false on both
  # engines rather than a hash of its innards on one.
  -> .encode_value(value, lines)
    kind = type(value)
    out = false
    if kind == "Boolean"
      flag = "F"
      flag = "T" if value
      lines.push(flag)
      out = true
    if kind == "Integer"
      lines.push("i " + value.to_s)
      out = true
    if kind == "Float"
      lines.push(Persist.float_line(value))
      out = true
    if kind == "String"
      lines.push("s " + Persist.escape_text(value))
      out = true
    if kind == "Symbol"
      lines.push("y " + Persist.escape_text(value.to_s))
      out = true
    if kind == "Array"
      out = Persist.encode_array(value, lines)
    if !out && value.respond_to?("to_state")
      out = Persist.encode_object(value, lines)
    if !out && kind == "Hash" && !value.respond_to?("fitted?")
      out = Persist.encode_hash(value, lines)
    out

  # An array as `a <n>` and its n element nodes, in order.
  -> .encode_array(values, lines)
    lines.push("a " + values.size.to_s)
    out = true
    values.each -> (v)
      out = false if !Persist.encode(v, lines)
    out

  # A hash as `h <n>` and n KEY, VALUE node pairs, keys sorted by their
  # string form so the payload is the same on both engines.
  -> .encode_hash(pairs, lines)
    keys = Persist.sorted_keys(pairs)
    lines.push("h " + keys.size.to_s)
    out = true
    keys.each -> (k)
      out = false if !Persist.encode(k, lines)
      out = false if !Persist.encode(pairs[k], lines)
    out

  # A koala object as `o <ClassName>` and its state hash.
  -> .encode_object(model, lines)
    out = false
    if model.respond_to?("persist_name")
      name = model.persist_name
      state = model.to_state
      if name != nil && state != nil && type(state) == "Hash"
        lines.push("o " + name.to_s)
        out = Persist.encode(state, lines)
    out

  # A hash's keys, ascending by `to_s` — an explicit insertion sort, since
  # Array#sort's order is not portable and symbols do not compare across
  # engines at all (the DecisionTree.sorted_copy convention).
  -> .sorted_keys(pairs)
    out = []
    pairs.keys.each -> (k)
      out.push(k)
    n = out.size
    i = 1
    while i < n
      cur = out[i]
      ck = cur.to_s
      j = i - 1
      while j >= 0 && out[j].to_s > ck
        out[j + 1] = out[j]
        j -= 1
      out[j + 1] = cur
      i += 1
    out

  # --- Floats ---

  # One line for a float: the readable decimal when the engine confirms it
  # round-trips, the exact bits otherwise, a tag for the three values that
  # have no bits form.
  -> .float_line(v)
    out = "w Q"
    if v == v
      out = "w P"
      out = "w M" if v < 0.to_f
      out = Persist.finite_float_line(v) if v - v == 0.to_f
    out

  -> .finite_float_line(v)
    short = v.to_s
    out = nil
    out = "d " + short if short.to_f == v
    out = Persist.bits_line(v) if out == nil
    out

  # v as `b <neg> <e> <hi> <lo>` — see the header for the decomposition.
  # The normalize loops are bounded so no input can spin them forever.
  -> .bits_line(v)
    neg = 0
    a = v
    if a < 0.to_f
      neg = 1
      a = 0.to_f - a
    half = 1.to_f / 2.to_f
    one = 1.to_f
    two = 2.to_f
    e = 0
    guard = 0
    while a >= one && guard < 2200
      a = a / two
      e += 1
      guard += 1
    while a > 0.to_f && a < half && guard < 2200
      a = a * two
      e -= 1
      guard += 1
    t = a
    27.times -> (c)
      t = t * two
    hi = t.floor
    frac = t - hi.to_f
    26.times -> (c)
      frac = frac * two
    lo = frac.floor
    "b " + neg.to_s + " " + e.to_s + " " + hi.to_s + " " + lo.to_s

  # The inverse of bits_line: every step a power-of-two multiply, so the
  # reconstruction is exact.
  -> .from_bits(neg, e, hi, lo)
    two = 2.to_f
    a = hi.to_f
    27.times -> (c)
      a = a / two
    b = lo.to_f
    53.times -> (c)
      b = b / two
    m = a + b
    k = e
    guard = 0
    while k > 0 && guard < 2200
      m = m * two
      k -= 1
      guard += 1
    while k < 0 && guard < 2200
      m = m / two
      k += 1
      guard += 1
    m = 0.to_f - m if neg == 1
    m

  # +inf, built by doubling — there is no float literal to write it with,
  # and no portable way to divide by zero for one.
  -> .infinity
    out = 1.to_f
    1100.times -> (c)
      out = out * 2.to_f
    out

  # --- Escaping ---

  # `\` and newline, backslash-escaped, so a node stays on ONE line. Byte
  # by byte, which is safe for UTF-8: neither escaped byte can appear
  # inside a multi-byte sequence, and the untouched bytes are rejoined
  # unchanged. Strings without either character are returned as they are.
  -> .escape_text(s)
    out = s
    if s.include?("\\") || s.include?("\n")
      parts = []
      i = 0
      n = s.size
      while i < n
        c = s.slice(i, 1)
        piece = c
        piece = "\\\\" if c == "\\"
        piece = "\\n" if c == "\n"
        parts.push(piece)
        i += 1
      out = parts.join("")
    out

  -> .unescape_text(s)
    out = s
    if s.include?("\\")
      parts = []
      i = 0
      n = s.size
      while i < n
        c = s.slice(i, 1)
        step = 1
        piece = c
        if c == "\\" && i + 1 < n
          nxt = s.slice(i + 1, 1)
          piece = "\\"
          piece = "\n" if nxt == "n"
          step = 2
        parts.push(piece)
        i += step
      out = parts.join("")
    out

  # --- Decoding ---
  #
  # Every reader takes (lines, i) and answers { ok:, v:, i: } — the value
  # and the index of the line AFTER it. Returning the cursor rather than
  # mutating one keeps the parser a pure function, so a failure deep in a
  # tree unwinds without leaving a half-advanced position behind. `ok` is
  # separate from `v` because nil is a legitimate value.

  -> .decode(lines, i)
    out = { ok: false, v: nil, i: i }
    out = Persist.decode_line(lines, i) if i >= 0 && i < lines.size
    out

  -> .decode_line(lines, i)
    line = lines[i]
    tag = line.slice(0, 1)
    rest = ""
    rest = line.slice(2, line.size - 2) if line.size > 2
    out = { ok: false, v: nil, i: i }
    if tag == "z" && line.size == 1
      out = { ok: true, v: nil, i: i + 1 }
    if tag == "T" && line.size == 1
      out = { ok: true, v: true, i: i + 1 }
    if tag == "F" && line.size == 1
      out = { ok: true, v: false, i: i + 1 }
    if tag == "i" && Persist.integer_text?(rest)
      out = { ok: true, v: rest.to_i, i: i + 1 }
    if tag == "d" && Persist.float_text?(rest)
      out = { ok: true, v: rest.to_f, i: i + 1 }
    if tag == "b"
      out = Persist.decode_bits(rest, i)
    if tag == "w"
      out = Persist.decode_special(rest, i)
    if tag == "s" && line.size >= 2
      out = { ok: true, v: Persist.unescape_text(rest), i: i + 1 }
    if tag == "y" && line.size > 2
      out = { ok: true, v: Persist.unescape_text(rest).to_sym, i: i + 1 }
    if tag == "a" && Persist.integer_text?(rest)
      out = Persist.decode_array(lines, i, rest.to_i)
    if tag == "h" && Persist.integer_text?(rest)
      out = Persist.decode_hash(lines, i, rest.to_i)
    if tag == "o" && line.size > 2
      out = Persist.decode_object(lines, i, rest)
    out

  -> .decode_bits(rest, i)
    parts = rest.split(" ")
    out = { ok: false, v: nil, i: i }
    if parts.size == 4
      fine = true
      parts.each -> (p)
        fine = false if !Persist.integer_text?(p)
      if fine
        v = Persist.from_bits(parts[0].to_i, parts[1].to_i, parts[2].to_i, parts[3].to_i)
        out = { ok: true, v: v, i: i + 1 }
    out

  -> .decode_special(rest, i)
    out = { ok: false, v: nil, i: i }
    big = Persist.infinity
    out = { ok: true, v: big - big, i: i + 1 } if rest == "Q"
    out = { ok: true, v: big, i: i + 1 } if rest == "P"
    out = { ok: true, v: 0.to_f - big, i: i + 1 } if rest == "M"
    out

  # n nodes after the header line. The count is bounded by the lines that
  # remain — a corrupt `a 999999999` must fail, not spin.
  -> .decode_array(lines, i, n)
    out = { ok: false, v: nil, i: i }
    if n >= 0 && n <= lines.size
      vals = []
      cur = i + 1
      fine = true
      n.times -> (c)
        if fine
          res = Persist.decode(lines, cur)
          if res[:ok]
            vals.push(res[:v])
            cur = res[:i]
          else
            fine = false
      out = { ok: true, v: vals, i: cur } if fine
    out

  # n KEY, VALUE node pairs after the header line.
  -> .decode_hash(lines, i, n)
    out = { ok: false, v: nil, i: i }
    if n >= 0 && n + n <= lines.size
      pairs = {}
      cur = i + 1
      fine = true
      n.times -> (c)
        if fine
          kres = Persist.decode(lines, cur)
          if kres[:ok]
            vres = Persist.decode(lines, kres[:i])
            if vres[:ok]
              pairs[kres[:v]] = vres[:v]
              cur = vres[:i]
            else
              fine = false
          else
            fine = false
      out = { ok: true, v: pairs, i: cur } if fine
    out

  # `o <ClassName>` and the ONE hash node that must follow it. The next
  # line is required to BE a hash node (its tag is checked before it is
  # read) so no loader is ever handed something it would index into.
  -> .decode_object(lines, i, name)
    out = { ok: false, v: nil, i: i }
    shaped = false
    shaped = lines[i + 1].slice(0, 1) == "h" if i + 1 < lines.size
    if shaped
      res = Persist.decode(lines, i + 1)
      if res[:ok]
        model = Persist.rebuild(name, res[:v])
        out = { ok: true, v: model, i: res[:i] } if model != nil
    out

  # --- Text predicates (a corrupt number must be nil, not zero) ---

  -> .integer_text?(s)
    out = false
    if s != nil && s.size > 0 && s != "-"
      out = true
      i = 0
      n = s.size
      while i < n
        c = s.slice(i, 1)
        good = "0123456789".include?(c)
        good = true if c == "-" && i == 0
        out = false if !good
        i += 1
    out

  -> .float_text?(s)
    out = false
    if s != nil && s.size > 0
      out = true
      i = 0
      n = s.size
      while i < n
        out = false if !"0123456789+-.eE".include?(s.slice(i, 1))
        i += 1
    out
