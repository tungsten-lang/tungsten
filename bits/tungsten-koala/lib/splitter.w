# Splitter — deterministic train/test splitting
#
#     pair = Splitter.train_test(df, 30)       # last 30% tests, in order
#     pair = Splitter.train_test(df, 30, 42)   # seeded shuffle first
#     train = pair[0]
#     test = pair[1]
#     pair = Splitter.every_nth(df, 3)         # rows 0,3,6,... test
#
# Core Random exposes no seeded PRNG (only crypto bytes and UUIDs), so
# Splitter is deterministic by construction: with seed = nil rows are
# NOT shuffled — the first rows train and the tail tests — and an
# integer seed shuffles with a built-in MINSTD Lehmer generator
# (state * 48271 mod 2^31-1; the worst-case product ~1.04e14 stays
# inside the boxed-int range). The same seed always produces the same
# split, on both engines.
#
# test_pct is an INTEGER percent — float parameters do not cross
# engine boundaries reliably. The test row count is
# (rows * test_pct) / 100, rounded down and clamped to 0..rows.
+ Splitter
  # [train, test] DataFrames; seed = nil keeps input order.
  -> .train_test(df, test_pct = 25, seed = nil)
    n = df.row_count
    test_n = (n * test_pct) / 100
    test_n = 0 if test_n < 0
    test_n = n if test_n > n
    train_n = n - test_n
    order = Splitter.indices(n, seed)
    train_idx = []
    test_idx = []
    i = 0
    order.each -> (ix)
      if i < train_n
        train_idx.push(ix)
      else
        test_idx.push(ix)
      i += 1
    # TODO: assign-then-return works around a parser bug — a BARE tail
    # array literal whose elements are method calls fails to parse
    # ("Expected 55, got COMMA"); the compiler tree is out of scope here.
    pair = [df.take(train_idx), df.take(test_idx)]
    pair

  # [train, test] with rows offset, offset+nth, offset+2*nth, ... as
  # test — fully deterministic with no seed at all.
  -> .every_nth(df, nth, offset = 0)
    rows = df.row_count
    train_idx = []
    test_idx = []
    rows.times -> (i)
      pick = false
      if i >= offset
        pick = (i - offset) % nth == 0
      if pick
        test_idx.push(i)
      else
        train_idx.push(i)
    # TODO: same bare-tail-array-literal parser bug as train_test.
    pair = [df.take(train_idx), df.take(test_idx)]
    pair

  # 0...n, identity order for seed = nil, Fisher-Yates shuffled by the
  # MINSTD stream otherwise.
  -> .indices(n, seed = nil)
    idx = []
    n.times -> (i)
      idx.push(i)
    if seed != nil && n > 1
      state = seed % 2147483647
      state = 1 if state <= 0
      (n - 1).times -> (k)
        i = n - 1 - k
        state = (state * 48271) % 2147483647
        j = state % (i + 1)
        tmp = idx[i]
        idx[i] = idx[j]
        idx[j] = tmp
    idx
