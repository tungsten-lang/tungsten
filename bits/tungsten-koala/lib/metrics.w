# Metrics — model evaluation metrics for regression and classification
#
#     Metrics.accuracy(predictions, actual)
#     Metrics.r2(predictions, actual)
#     Metrics.confusion_matrix(predictions, actual)

in Tungsten:Koala

+ Metrics
  # --- Classification ---

  # Accuracy: fraction of correct predictions.
  -> .accuracy(predictions, actual)
    preds = predictions.to_a
    acts  = actual.to_a
    correct = preds.zip(acts).count(-> (p, a) p == a)
    correct.to_f / preds.size

  # Precision: tp / (tp + fp).
  -> .precision(predictions, actual, positive: 1)
    preds = predictions.to_a
    acts  = actual.to_a
    tp = preds.zip(acts).count(-> (p, a) p == positive && a == positive)
    fp = preds.zip(acts).count(-> (p, a) p == positive && a != positive)
    (tp + fp) == 0 ? 0.0 : tp.to_f / (tp + fp)

  # Recall: tp / (tp + fn).
  -> .recall(predictions, actual, positive: 1)
    preds = predictions.to_a
    acts  = actual.to_a
    tp = preds.zip(acts).count(-> (p, a) p == positive && a == positive)
    fn = preds.zip(acts).count(-> (p, a) p != positive && a == positive)
    (tp + fn) == 0 ? 0.0 : tp.to_f / (tp + fn)

  # F1 score: harmonic mean of precision and recall.
  -> .f1(predictions, actual, positive: 1)
    p = self.precision(predictions, actual, positive: positive)
    r = self.recall(predictions, actual, positive: positive)
    (p + r) == 0 ? 0.0 : 2.0 * p * r / (p + r)

  # Confusion matrix as a DataFrame.
  -> .confusion_matrix(predictions, actual)
    preds = predictions.to_a
    acts  = actual.to_a
    labels = (preds + acts).uniq.sort

    matrix = labels.map -> (actual_label)
      labels.map -> (pred_label)
        preds.zip(acts).count(-> (p, a) p == pred_label && a == actual_label)

    DataFrame.new(
      **({ actual: labels }.merge(
        labels.each_with_index.map(-> (l, i) ["pred_[l]".to_sym, matrix.map(-> (row) row[i])]).to_h
      ))
    )

  # Classification report as a DataFrame.
  -> .classification_report(predictions, actual)
    labels = (predictions.to_a + actual.to_a).uniq.sort
    rows = labels.map -> (label)
      {
        label:     label,
        precision: self.precision(predictions, actual, positive: label),
        recall:    self.recall(predictions, actual, positive: label),
        f1:        self.f1(predictions, actual, positive: label),
        support:   actual.to_a.count(-> (a) a == label)
      }
    DataFrame.from_rows(rows)

  # ROC AUC score (binary classification with probability scores).
  -> .roc_auc(probabilities, actual, positive: 1)
    pairs = probabilities.to_a.zip(actual.to_a)
    positives = pairs.select(-> (_, a) a == positive).map(&:first)
    negatives = pairs.reject(-> (_, a) a == positive).map(&:first)

    return 0.5 if positives.empty? || negatives.empty?

    concordant = 0
    total = positives.size * negatives.size
    positives.each -> (p)
      negatives.each -> (n)
        concordant += 1 if p > n
        concordant += 0.5 if p == n

    concordant.to_f / total

  # Log loss (binary cross-entropy).
  -> .log_loss(probabilities, actual, eps: 1e-15)
    probs = probabilities.to_a
    acts  = actual.to_a
    n = probs.size
    -probs.zip(acts).map -> (p, a)
      p = p.clamp(eps, 1.0 - eps)
      a * Math.log(p) + (1 - a) * Math.log(1 - p)
    .sum / n

  # --- Regression ---

  # Mean squared error.
  -> .mse(predictions, actual)
    preds = predictions.to_a
    acts  = actual.to_a
    preds.zip(acts).map(-> (p, a) (p - a) ** 2).sum / preds.size

  # Root mean squared error.
  -> .rmse(predictions, actual)
    Math.sqrt(self.mse(predictions, actual))

  # Mean absolute error.
  -> .mae(predictions, actual)
    preds = predictions.to_a
    acts  = actual.to_a
    preds.zip(acts).map(-> (p, a) (p - a).abs).sum / preds.size

  # R² (coefficient of determination).
  -> .r2(predictions, actual)
    preds = predictions.to_a
    acts  = actual.to_a
    mean_actual = acts.sum.to_f / acts.size
    ss_res = preds.zip(acts).map(-> (p, a) (a - p) ** 2).sum
    ss_tot = acts.map(-> (a) (a - mean_actual) ** 2).sum
    ss_tot == 0 ? 1.0 : 1.0 - ss_res / ss_tot

  # Adjusted R².
  -> .adjusted_r2(predictions, actual, n_features:)
    n = actual.to_a.size
    r2 = self.r2(predictions, actual)
    1.0 - (1.0 - r2) * (n - 1) / (n - n_features - 1)

  # Mean absolute percentage error.
  -> .mape(predictions, actual)
    preds = predictions.to_a
    acts  = actual.to_a
    preds.zip(acts)
      .reject(-> (_, a) a == 0)
      .map(-> (p, a) ((a - p) / a).abs)
      .sum / preds.size * 100

  # Explained variance score.
  -> .explained_variance(predictions, actual)
    preds = predictions.to_a
    acts  = actual.to_a
    residuals = preds.zip(acts).map(-> (p, a) a - p)
    1.0 - Stats.var(residuals) / Stats.var(acts)

  # --- Distance / Similarity ---

  # Cosine similarity between two arrays.
  -> .cosine_similarity(a, b)
    a = a.to_a
    b = b.to_a
    dot = a.zip(b).map(-> (x, y) x * y).sum
    norm_a = Math.sqrt(a.map(-> (x) x * x).sum)
    norm_b = Math.sqrt(b.map(-> (x) x * x).sum)
    dot / (norm_a * norm_b)

  # Euclidean distance.
  -> .euclidean_distance(a, b)
    a = a.to_a
    b = b.to_a
    Math.sqrt(a.zip(b).map(-> (x, y) (x - y) ** 2).sum)

  # Silhouette score (clustering quality).
  -> .silhouette(data, labels)
    n = labels.to_a.size
    scores = n.times.map -> (i)
      own_cluster = labels.to_a[i]
      # a(i) — mean distance to own cluster
      own_indices = labels.to_a.each_with_index
        .select(-> (l, _) l == own_cluster)
        .map(&:last)
        .reject(-> (j) j == i)
      a = own_indices.empty? ? 0.0 :
        own_indices.map(-> (j) self.euclidean_distance(data[i], data[j])).sum / own_indices.size

      # b(i) — min mean distance to other clusters
      other_clusters = labels.to_a.uniq.reject(-> (l) l == own_cluster)
      b = other_clusters.map -> (cl)
        cl_indices = labels.to_a.each_with_index
          .select(-> (l, _) l == cl)
          .map(&:last)
        cl_indices.map(-> (j) self.euclidean_distance(data[i], data[j])).sum / cl_indices.size
      .min || 0.0

      max_ab = [a, b].max
      max_ab == 0 ? 0.0 : (b - a) / max_ab

    scores.sum / n
