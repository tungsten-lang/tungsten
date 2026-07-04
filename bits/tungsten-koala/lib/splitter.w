# Splitter — dataset splitting strategies for training and evaluation
#
#     train, test = Splitter.train_test(df, test_size: 0.2)
#     folds = Splitter.kfold(df, k: 5)
#     train, test = Splitter.stratified(df, target: :label, test_size: 0.2)

in Tungsten:Koala

+ Splitter
  # Train/test split.
  #
  #     train, test = Splitter.train_test(df, test_size: 0.2, shuffle: true, seed: 42)
  -> .train_test(df, test_size: 0.2, shuffle: true, seed: nil)
    n = df.row_count
    test_n = (n * test_size).round
    train_n = n - test_n

    indices = (0...n).to_a
    if shuffle
      rng = seed ? Random.new(seed) : Random
      indices = indices.shuffle(random: rng)

    train_idx = indices[0...train_n]
    test_idx  = indices[train_n..]

    (df.take(train_idx), df.take(test_idx))

  # K-fold cross-validation splits.
  #
  #     folds = Splitter.kfold(df, k: 5, shuffle: true)
  #     folds.each -> (train, val)
  #       model.fit(train)
  #       score = model.score(val)
  -> .kfold(df, k: 5, shuffle: true, seed: nil)
    n = df.row_count
    indices = (0...n).to_a
    if shuffle
      rng = seed ? Random.new(seed) : Random
      indices = indices.shuffle(random: rng)

    fold_size = n / k
    k.times.map -> (i)
      val_start = i * fold_size
      val_end   = (i == k - 1) ? n : (i + 1) * fold_size
      val_idx   = indices[val_start...val_end]
      train_idx = indices[0...val_start] + indices[val_end..]
      (df.take(train_idx), df.take(val_idx))

  # Stratified train/test split — preserves class distribution.
  #
  #     train, test = Splitter.stratified(df, target: :label, test_size: 0.2)
  -> .stratified(df, target:, test_size: 0.2, shuffle: true, seed: nil)
    target = target.to_sym
    labels = df[target].to_a
    rng = seed ? Random.new(seed) : Random

    # Group indices by class
    groups = {}
    labels.each_with_index -> (label, i)
      groups[label] ||= []
      groups[label].push(i)

    train_idx = []
    test_idx  = []

    groups.each -> (_, indices)
      indices = indices.shuffle(random: rng) if shuffle
      test_n = [1, (indices.size * test_size).round].max
      test_idx  += indices[0...test_n]
      train_idx += indices[test_n..]

    train_idx = train_idx.shuffle(random: rng) if shuffle
    test_idx  = test_idx.shuffle(random: rng) if shuffle

    (df.take(train_idx), df.take(test_idx))

  # Stratified K-fold.
  -> .stratified_kfold(df, target:, k: 5, shuffle: true, seed: nil)
    target = target.to_sym
    labels = df[target].to_a
    rng = seed ? Random.new(seed) : Random

    groups = {}
    labels.each_with_index -> (label, i)
      groups[label] ||= []
      groups[label].push(i)

    # Distribute each class evenly across folds
    fold_indices = k.times.map(-> [])
    groups.each -> (_, indices)
      indices = indices.shuffle(random: rng) if shuffle
      indices.each_with_index(-> (idx, i) fold_indices[i % k].push(idx))

    k.times.map -> (i)
      val_idx = fold_indices[i]
      train_idx = fold_indices.each_with_index
        .reject(-> (_, j) j == i)
        .flat_map(&:first)
      (df.take(train_idx), df.take(val_idx))

  # Time-series split — expanding window, no shuffle.
  #
  #     folds = Splitter.time_series(df, n_splits: 5)
  -> .time_series(df, n_splits: 5)
    n = df.row_count
    min_train = n / (n_splits + 1)

    n_splits.times.map -> (i)
      train_end = min_train + (i * min_train)
      val_end   = train_end + min_train
      val_end   = [val_end, n].min
      train_idx = (0...train_end).to_a
      val_idx   = (train_end...val_end).to_a
      (df.take(train_idx), df.take(val_idx))

  # Leave-one-out cross-validation.
  -> .leave_one_out(df)
    n = df.row_count
    n.times.map -> (i)
      train_idx = (0...n).to_a.reject(-> (j) j == i)
      (df.take(train_idx), df.take([i]))
