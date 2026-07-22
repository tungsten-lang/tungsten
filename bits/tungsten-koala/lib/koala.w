# Koala — data science and machine learning for Tungsten
# A friendlier pandas: Series, DataFrame, group_by, stats, metrics,
# dense linear algebra (Vector / Matrix / LinAlg), ML preprocessing
# (Scaler / Encoder / Imputer / Splitter / Pipeline), estimation
# (LinearRegression — fit / predict / score with optional ridge alpha,
# alone or as a Pipeline tail; KNNClassifier — k-nearest-neighbors
# classification, the companion classifier to Metrics.accuracy / f1;
# GaussianNB — multiclass Gaussian naive Bayes, a closed-form generative
# classifier), clustering (KMeans — Lloyd's algorithm, koala's first
# unsupervised learner), model evaluation (KFold / CrossValidation — k-fold
# cross-validation that re-fits an estimator on each fold and averages
# the held-out score, supervised or not), and model selection (GridSearch
# — exhaustive hyperparameter search scoring every point of a param grid
# by cross-validation, through the estimator contract alone).
#
# All five estimators answer ONE declared contract (lib/estimator_base.w):
# `is Estimable` plus `is SupervisedEstimator` (LinearRegression,
# KNNClassifier, LogisticRegression, GaussianNB) or `is
# UnsupervisedEstimator` (KMeans). That contract adds `supervised?`,
# `params`, `with_params(overrides)` and `estimator_name` to the familiar
# new / fitted? / fit / predict / score, and puts the ONE definition of
# every accepted input shape on the neutral `Estimator` base rather than on
# a concrete sibling. It is what generic tooling — CrossValidation and
# GridSearch — dispatches through, without ever naming a concrete class.
#
# The three PREPROCESSING transformers (Scaler / Imputer / Encoder)
# declare the hyperparameter half of that contract on its own,
# `is Tunable` — `params` / `with_params` and nothing more, since a
# transformer has no predict and no fit arity to declare. That is the
# whole entry fee for a Pipeline's tunable surface, so a grid search
# tunes the SCALING or the FILL RULE alongside the model's alpha, with no
# code in pipeline.w or grid_search.w aware that scaling exists. What fit
# LEARNED answers to `learned_params` (Encoder: `categories`), keeping
# `params` meaning "the knobs you set" everywhere in the bit.

use version
use stats
use series
use data_frame
use group_by
use metrics
use classification
use roc
use rolling
use join
use pivot
use vector
use matrix
use linalg
use estimator_base
use linear_regression
use knn
use logistic_regression
use gaussian_nb
use scaler
use encoder
use imputer
use splitter
use pipeline
use cross_validation
use kmeans
use grid_search

# The remaining modules under lib/ (tensor, resample, transformer,
# estimator, index, sparse, gpu, device) are unported design drafts —
# they do not parse as Tungsten yet and are not loaded. estimator.w's
# linear-regression payoff shipped as linear_regression.w above, its
# k-NN sketch shipped as knn.w, and its logistic-regression sketch
# shipped as logistic_regression.w; the draft stays only as the sketch
# for the decision-tree / lasso follow-ups. NOTE that the draft
# estimator.w sketches its own `+ Estimator` / `trait Predictable` — those
# are SUPERSEDED by estimator_base.w's `Estimator` / `Estimable`, which is
# the loaded, working contract; do not load the draft alongside it. Port a
# draft into the manifest above only after
# `bin/tungsten -c` passes on it AND it runs on both engines (spec
# coverage in spec/*.w).

+ Koala
  # Create a DataFrame from ordered [name, values] column pairs.
  #
  #     df = Koala.frame([
  #       [:name, ["Alice", "Bob"]],
  #       [:age,  [30, 25]]
  #     ])
  -> .frame(columns)
    DataFrame.new(columns)

  # Create a Series from values.
  -> .series(values, name = "series")
    Series.new(values, name)

  # Create a Vector from values.
  -> .vector(values)
    Vector.new(values)

  # Create a Matrix from nested row arrays.
  -> .matrix(rows)
    Matrix.new(rows)
