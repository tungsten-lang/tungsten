# ConfusionMatrix / ClassificationReport — multiclass classification
# metrics (pure Tungsten, CPU-only). Koala's binary Metrics.precision /
# recall / f1 take a single pos_label; these generalize the same
# definitions to any number of classes one-vs-rest, tying the existing
# Metrics to KNNClassifier's predicted-label arrays the way scikit-learn's
# confusion_matrix / classification_report do.
#
#     cm = Metrics.confusion_matrix(predictions, actual)
#     cm.labels                 # classes, first-seen order
#     cm.matrix                 # matrix[i][j] = count(actual i, predicted j)
#     cm.count(actual, pred)    # a single cell
#     cm.to_df                  # DataFrame: :actual column + one per predicted
#
#     rep = Metrics.classification_report(predictions, actual)
#     rep.precision(:cat)       # per-class precision / recall / f1 / support
#     rep.accuracy              # overall accuracy
#     rep.macro_f1              # unweighted mean over classes
#     rep.weighted_precision    # support-weighted mean over classes
#     rep.to_df                 # pandas-style report table
#
# Argument order is koala's Metrics order, (predictions, actual) — the
# same as accuracy / precision / recall / f1, NOT scikit-learn's
# (y_true, y_pred). Class order is first-seen over actual then predictions
# (Array#sort is not portable across engines — the Pivot / Encoder
# convention); per-class values are order-independent, so they match
# scikit-learn regardless. Labels are opaque — integers, strings, or
# symbols all count.
#
# NOTE: locals are hoisted from ivars before any `-> (x)` block, methods
# containing closures avoid early `return`, ivars are assigned at the END
# of the constructor, and every float derives from the data via .to_f —
# the same conventions as the rest of koala.

+ ConfusionMatrix
  ro :labels   # class labels, first-seen order (actual then predictions)
  ro :matrix   # matrix[i][j] = count(actual == labels[i], pred == labels[j])

  -> new(predictions, actual)
    labels = []
    actual.each -> (a)
      labels.push(a) if !labels.include?(a)
    predictions.each -> (p)
      labels.push(p) if !labels.include?(p)
    n = labels.size
    mat = []
    n.times -> (r)
      row = []
      n.times -> (c)
        row.push(0)
      mat.push(row)
    i = 0
    actual.each -> (a)
      ri = ConfusionMatrix.index_of(labels, a)
      ci = ConfusionMatrix.index_of(labels, predictions[i])
      mat[ri][ci] = mat[ri][ci] + 1
      i += 1
    @labels = labels
    @matrix = mat

  # First index of v in labels, or -1.
  -> .index_of(labels, v)
    out = -1
    i = 0
    labels.each -> (l)
      out = i if l == v
      i += 1
    out

  # The count for (actual_label, predicted_label); 0 for unknown labels.
  -> count(actual_label, predicted_label)
    ri = ConfusionMatrix.index_of(@labels, actual_label)
    ci = ConfusionMatrix.index_of(@labels, predicted_label)
    out = 0
    out = @matrix[ri][ci] if ri != -1 && ci != -1
    out

  # DataFrame view: a leading :actual label column, then one integer
  # column per predicted label (named by the label value, Pivot-style).
  -> to_df
    labels = @labels
    matrix = @matrix
    pairs = [[:actual, labels]]
    j = 0
    labels.each -> (pl)
      col = []
      i = 0
      labels.each -> (al)
        col.push(matrix[i][j])
        i += 1
      pairs.push([pl, col])
      j += 1
    DataFrame.new(pairs)

+ ClassificationReport
  ro :labels     # class labels, first-seen order
  ro :accuracy   # overall accuracy (fraction correct)
  ro :total      # total sample count (== sum of per-class support)

  -> new(predictions, actual)
    cm = ConfusionMatrix.new(predictions, actual)
    labels = cm.labels
    matrix = cm.matrix
    n = labels.size
    precisions = []
    recalls = []
    f1s = []
    supports = []
    total = 0
    correct = 0
    n.times -> (k)
      tp = matrix[k][k]
      col_sum = 0
      row_sum = 0
      n.times -> (t)
        col_sum += matrix[t][k]
        row_sum += matrix[k][t]
      prec = 0.to_f
      prec = tp.to_f / col_sum.to_f if col_sum > 0
      rec = 0.to_f
      rec = tp.to_f / row_sum.to_f if row_sum > 0
      f = 0.to_f
      f = 2.to_f * prec * rec / (prec + rec) if (prec + rec) > 0
      precisions.push(prec)
      recalls.push(rec)
      f1s.push(f)
      supports.push(row_sum)
      total += row_sum
      correct += tp
    acc = 0.to_f
    acc = correct.to_f / total.to_f if total > 0
    @labels = labels
    @precisions = precisions
    @recalls = recalls
    @f1s = f1s
    @supports = supports
    @total = total
    @accuracy = acc

  # Index of label in @labels, or -1.
  -> index_of(label)
    ConfusionMatrix.index_of(@labels, label)

  # Per-class precision (TP / predicted-positive); nil for an unknown label.
  -> precision(label)
    i = self.index_of(label)
    out = nil
    out = @precisions[i] if i != -1
    out

  # Per-class recall (TP / actual-positive); nil for an unknown label.
  -> recall(label)
    i = self.index_of(label)
    out = nil
    out = @recalls[i] if i != -1
    out

  # Per-class F1 (harmonic mean of precision and recall); nil for unknown.
  -> f1(label)
    i = self.index_of(label)
    out = nil
    out = @f1s[i] if i != -1
    out

  # Per-class support (number of actual rows in the class); nil for unknown.
  -> support(label)
    i = self.index_of(label)
    out = nil
    out = @supports[i] if i != -1
    out

  # Macro averages: the unweighted mean of the per-class scores.
  -> macro_precision
    Stats.mean(@precisions)

  -> macro_recall
    Stats.mean(@recalls)

  -> macro_f1
    Stats.mean(@f1s)

  # Weighted averages: the per-class scores weighted by support / total.
  -> weighted_precision
    self.weighted(@precisions)

  -> weighted_recall
    self.weighted(@recalls)

  -> weighted_f1
    self.weighted(@f1s)

  # Support-weighted mean of a per-class score array.
  -> weighted(values)
    supports = @supports
    total = @total
    acc = 0.to_f
    i = 0
    values.each -> (v)
      acc += v * supports[i].to_f
      i += 1
    out = 0.to_f
    out = acc / total.to_f if total > 0
    out

  # Pandas-style report table: one row per class (:label / :precision /
  # :recall / :f1 / :support), then "accuracy", "macro avg" and
  # "weighted avg" rows. The accuracy row carries the score in :f1 and
  # nil in :precision / :recall, matching scikit-learn's text report.
  -> to_df
    labels = @labels
    precisions = @precisions
    recalls = @recalls
    f1s = @f1s
    supports = @supports
    label_col = []
    prec_col = []
    rec_col = []
    f1_col = []
    sup_col = []
    i = 0
    labels.each -> (l)
      label_col.push(l)
      prec_col.push(precisions[i])
      rec_col.push(recalls[i])
      f1_col.push(f1s[i])
      sup_col.push(supports[i])
      i += 1
    label_col.push("accuracy")
    prec_col.push(nil)
    rec_col.push(nil)
    f1_col.push(@accuracy)
    sup_col.push(@total)
    label_col.push("macro avg")
    prec_col.push(self.macro_precision)
    rec_col.push(self.macro_recall)
    f1_col.push(self.macro_f1)
    sup_col.push(@total)
    label_col.push("weighted avg")
    prec_col.push(self.weighted_precision)
    rec_col.push(self.weighted_recall)
    f1_col.push(self.weighted_f1)
    sup_col.push(@total)
    DataFrame.new([[:label, label_col], [:precision, prec_col], [:recall, rec_col], [:f1, f1_col], [:support, sup_col]])
