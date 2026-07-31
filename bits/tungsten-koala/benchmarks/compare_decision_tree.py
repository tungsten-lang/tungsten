"""Reproducible Koala/scikit-learn decision-tree speed and parity probe.

Run from the repository root in an environment with scikit-learn:

    uv run --with scikit-learn==1.7.2 \
      python bits/tungsten-koala/benchmarks/compare_decision_tree.py

The benchmark uses the exact deterministic fixture and fit/predict counts in
decision_tree_speed.w. Seven samples and the median keep process noise from
deciding the result. Ordinary-tree accuracy, predictions, and node count plus
targeted pruning, split-floor, and missing-route fixtures are exact parity
gates. The larger missing
workload has a quality/size gate instead: scikit-learn randomizes feature
visitation even when every feature is considered, so equal-gain lower nodes
can legitimately produce different predictions. Feature-importance checksums
are reported but not gated for the same reason. A 50-tree, single-threaded
forest adds held-out accuracy and OOB quality gates; a one-percent
minimum-weight floor must also deliver a measured training-speed gain without
exceeding its quality budget. The forest RNG is intentionally different, so
checksums and node identities are reported rather than equated.
The same fixture drives a 50-tree regression forest with held-out and OOB R²
gates, covering the probability-free batch projection independently.
"""

from __future__ import annotations

import statistics
import subprocess
import tempfile
import time
from pathlib import Path

import numpy as np
import sklearn
from sklearn.ensemble import RandomForestClassifier, RandomForestRegressor
from sklearn.tree import DecisionTreeClassifier, DecisionTreeRegressor


ROOT = Path(__file__).resolve().parents[3]
BENCH = Path(__file__).resolve().parent
SAMPLES = 7
FITS = 2
PREDICTIONS = 250
PINNED_SKLEARN = "1.7.2"
MISSING_ACCURACY_TOLERANCE = 0.005
MISSING_NODE_RATIO_LIMIT = 1.1
FOREST_TREES = 50
FOREST_PREDICTIONS = 10
FOREST_ACCURACY_TOLERANCE = 0.02
FOREST_OOB_TOLERANCE = 0.05
FOREST_MIN_WEIGHT_ACCURACY_TOLERANCE = 0.05
FOREST_MIN_WEIGHT_QUALITY_DROP = 0.05
FOREST_MIN_WEIGHT_SPEEDUP_FLOOR = 1.03
FOREST_MAX_SAMPLES_ACCURACY_TOLERANCE = 0.05
FOREST_MAX_SAMPLES_QUALITY_DROP = 0.03
FOREST_REGRESSION_R2_TOLERANCE = 0.02


def fixture(n: int = 1200, width: int = 12) -> tuple[np.ndarray, np.ndarray]:
    rows: list[list[int]] = []
    labels: list[int] = []
    for i in range(n):
        row = [
            (i * (37 + j * 2) + j * 101 + i * j * 3) % 1009
            for j in range(width)
        ]
        signal = row[0] + row[3] - row[5]
        label = 1 if signal > 450 else 0
        if row[7] < 200 and row[1] > 600:
            label = 2
        rows.append(row)
        labels.append(label)
    return np.asarray(rows, dtype=np.float64), np.asarray(labels, dtype=np.int64)


def regression_targets(x: np.ndarray) -> np.ndarray:
    return (x[:, 0] * 2 + x[:, 3] - x[:, 5]) / 7 + np.mod(x[:, 7], 113)


def parse_metrics(text: str) -> dict[str, float]:
    out: dict[str, float] = {}
    for line in text.splitlines():
        if "," in line:
            name, value = line.split(",", 1)
            out[name] = float(value)
    return out


def koala_samples(executable: Path) -> list[dict[str, float]]:
    return [
        parse_metrics(
            subprocess.run(
                [str(executable)],
                cwd=ROOT,
                check=True,
                text=True,
                capture_output=True,
            ).stdout
        )
        for _ in range(SAMPLES)
    ]


def sklearn_sample(x: np.ndarray, y: np.ndarray) -> dict[str, float]:
    started = time.perf_counter()
    model: DecisionTreeClassifier | None = None
    for _ in range(FITS):
        model = DecisionTreeClassifier(
            criterion="gini",
            max_depth=8,
            min_samples_split=2,
            min_samples_leaf=2,
            random_state=0,
        ).fit(x, y)
    train_ms = (time.perf_counter() - started) * 1000
    assert model is not None

    checksum = 0
    started = time.perf_counter()
    for _ in range(PREDICTIONS):
        checksum += int(model.predict(x).sum())
    predict_ms = (time.perf_counter() - started) * 1000
    leaf_index_checksum = 0
    started = time.perf_counter()
    for _ in range(PREDICTIONS):
        leaf_index_checksum += int(model.apply(x).sum())
    leaf_index_ms = (time.perf_counter() - started) * 1000
    last_probabilities: np.ndarray | None = None
    started = time.perf_counter()
    for _ in range(PREDICTIONS):
        last_probabilities = model.predict_proba(x)
    predict_proba_ms = (time.perf_counter() - started) * 1000
    assert last_probabilities is not None
    predict_proba_checksum = sum(
        (class_index + 1) * float(last_probabilities[:, class_index].sum())
        for class_index in range(last_probabilities.shape[1])
    )
    last_probability_column: np.ndarray | None = None
    started = time.perf_counter()
    for _ in range(PREDICTIONS):
        last_probability_column = model.predict_proba(x)[:, 1]
    predict_proba_column_ms = (time.perf_counter() - started) * 1000
    assert last_probability_column is not None
    predict_proba_column_checksum = float(last_probability_column.sum())
    importance_checksum = sum(
        (feature + 1) * importance
        for feature, importance in enumerate(model.feature_importances_)
    )
    out = {
        "decision_tree_train_ms": train_ms,
        "decision_tree_predict_ms": predict_ms,
        "decision_tree_leaf_index_ms": leaf_index_ms,
        "decision_tree_leaf_index_checksum": float(leaf_index_checksum),
        "decision_tree_predict_proba_ms": predict_proba_ms,
        "decision_tree_predict_proba_checksum": predict_proba_checksum,
        "decision_tree_predict_proba_column_ms": predict_proba_column_ms,
        "decision_tree_predict_proba_column_checksum": predict_proba_column_checksum,
        "decision_tree_nodes": float(model.tree_.node_count),
        "decision_tree_accuracy": float(model.score(x, y)),
        "decision_tree_checksum": float(checksum),
        "decision_tree_importance_checksum": float(importance_checksum),
    }

    started = time.perf_counter()
    entropy_model: DecisionTreeClassifier | None = None
    for _ in range(FITS):
        entropy_model = DecisionTreeClassifier(
            criterion="entropy",
            max_depth=8,
            min_samples_split=2,
            min_samples_leaf=2,
            random_state=0,
        ).fit(x, y)
    out["decision_tree_entropy_train_ms"] = (
        time.perf_counter() - started
    ) * 1000
    assert entropy_model is not None
    out["decision_tree_entropy_nodes"] = float(entropy_model.tree_.node_count)
    out["decision_tree_entropy_accuracy"] = float(entropy_model.score(x, y))
    out["decision_tree_entropy_checksum"] = float(entropy_model.predict(x).sum())

    missing_benchmark_x = x.copy()
    for i in range(missing_benchmark_x.shape[0]):
        for j in range(missing_benchmark_x.shape[1]):
            if (i * 17 + j * 31) % 13 == 0:
                missing_benchmark_x[i, j] = np.nan
    started = time.perf_counter()
    missing_benchmark_model: DecisionTreeClassifier | None = None
    for _ in range(FITS):
        missing_benchmark_model = DecisionTreeClassifier(
            criterion="gini",
            max_depth=8,
            min_samples_split=2,
            min_samples_leaf=2,
            random_state=0,
        ).fit(missing_benchmark_x, y)
    out["decision_tree_missing_train_ms"] = (
        time.perf_counter() - started
    ) * 1000
    assert missing_benchmark_model is not None

    missing_checksum = 0
    started = time.perf_counter()
    for _ in range(PREDICTIONS):
        missing_checksum += int(
            missing_benchmark_model.predict(missing_benchmark_x).sum()
        )
    out["decision_tree_missing_predict_ms"] = (
        time.perf_counter() - started
    ) * 1000
    out["decision_tree_missing_nodes"] = float(
        missing_benchmark_model.tree_.node_count
    )
    out["decision_tree_missing_accuracy"] = float(
        missing_benchmark_model.score(missing_benchmark_x, y)
    )
    out["decision_tree_missing_checksum"] = float(missing_checksum)

    started = time.perf_counter()
    forest = RandomForestClassifier(
        n_estimators=FOREST_TREES,
        criterion="gini",
        max_features="sqrt",
        max_depth=8,
        min_samples_split=2,
        min_samples_leaf=2,
        bootstrap=True,
        oob_score=True,
        random_state=42,
        n_jobs=1,
    ).fit(x, y)
    out["random_forest_train_ms"] = (time.perf_counter() - started) * 1000

    forest_checksum = 0
    started = time.perf_counter()
    for _ in range(FOREST_PREDICTIONS):
        forest_checksum += int(forest.predict(x).sum())
    out["random_forest_predict_ms"] = (
        time.perf_counter() - started
    ) * 1000
    forest_leaf_index_checksum = 0
    started = time.perf_counter()
    for _ in range(FOREST_PREDICTIONS):
        forest_leaf_index_checksum += int(forest.apply(x).sum())
    out["random_forest_leaf_index_ms"] = (
        time.perf_counter() - started
    ) * 1000
    out["random_forest_leaf_index_checksum"] = float(
        forest_leaf_index_checksum
    )
    forest_probabilities: np.ndarray | None = None
    started = time.perf_counter()
    for _ in range(FOREST_PREDICTIONS):
        forest_probabilities = forest.predict_proba(x)
    out["random_forest_predict_proba_ms"] = (
        time.perf_counter() - started
    ) * 1000
    assert forest_probabilities is not None
    out["random_forest_predict_proba_checksum"] = sum(
        (class_index + 1) * float(forest_probabilities[:, class_index].sum())
        for class_index in range(forest_probabilities.shape[1])
    )
    forest_probability_column: np.ndarray | None = None
    started = time.perf_counter()
    for _ in range(FOREST_PREDICTIONS):
        forest_probability_column = forest.predict_proba(x)[:, 1]
    out["random_forest_predict_proba_column_ms"] = (
        time.perf_counter() - started
    ) * 1000
    assert forest_probability_column is not None
    out["random_forest_predict_proba_column_checksum"] = float(
        forest_probability_column.sum()
    )
    out["random_forest_tree_count"] = float(len(forest.estimators_))
    out["random_forest_nodes"] = float(
        sum(tree.tree_.node_count for tree in forest.estimators_)
    )
    out["random_forest_accuracy"] = float(forest.score(x, y))
    forest_full_x, forest_full_y = fixture(1600)
    out["random_forest_test_accuracy"] = float(
        forest.score(forest_full_x[1200:], forest_full_y[1200:])
    )
    out["random_forest_checksum"] = float(forest_checksum)
    out["random_forest_oob_score"] = float(forest.oob_score_)

    started = time.perf_counter()
    forest_min_weight = RandomForestClassifier(
        n_estimators=FOREST_TREES,
        criterion="gini",
        max_features="sqrt",
        max_depth=8,
        min_samples_split=2,
        min_samples_leaf=2,
        min_weight_fraction_leaf=0.01,
        bootstrap=True,
        oob_score=True,
        random_state=42,
        n_jobs=1,
    ).fit(x, y)
    out["random_forest_min_weight_001_train_ms"] = (
        time.perf_counter() - started
    ) * 1000
    out["random_forest_min_weight_001_nodes"] = float(
        sum(tree.tree_.node_count for tree in forest_min_weight.estimators_)
    )
    out["random_forest_min_weight_001_accuracy"] = float(
        forest_min_weight.score(x, y)
    )
    out["random_forest_min_weight_001_test_accuracy"] = float(
        forest_min_weight.score(forest_full_x[1200:], forest_full_y[1200:])
    )
    out["random_forest_min_weight_001_checksum"] = float(
        forest_min_weight.predict(x).sum()
    )
    out["random_forest_min_weight_001_oob_score"] = float(
        forest_min_weight.oob_score_
    )

    started = time.perf_counter()
    forest_half_sample = RandomForestClassifier(
        n_estimators=FOREST_TREES,
        criterion="gini",
        max_features="sqrt",
        max_depth=8,
        min_samples_split=2,
        min_samples_leaf=2,
        bootstrap=True,
        max_samples=600,
        oob_score=True,
        random_state=42,
        n_jobs=1,
    ).fit(x, y)
    out["random_forest_half_sample_train_ms"] = (
        time.perf_counter() - started
    ) * 1000
    out["random_forest_half_sample_nodes"] = float(
        sum(tree.tree_.node_count for tree in forest_half_sample.estimators_)
    )
    out["random_forest_half_sample_accuracy"] = float(
        forest_half_sample.score(x, y)
    )
    out["random_forest_half_sample_test_accuracy"] = float(
        forest_half_sample.score(forest_full_x[1200:], forest_full_y[1200:])
    )
    out["random_forest_half_sample_checksum"] = float(
        forest_half_sample.predict(x).sum()
    )
    out["random_forest_half_sample_oob_score"] = float(
        forest_half_sample.oob_score_
    )

    forest_min_split = DecisionTreeClassifier(
        criterion="gini",
        max_depth=8,
        min_samples_split=200,
        min_samples_leaf=2,
        random_state=0,
    ).fit(x, y)
    out["random_forest_min_split_nodes"] = float(
        forest_min_split.tree_.node_count
    )
    out["random_forest_min_split_accuracy"] = float(
        forest_min_split.score(x, y)
    )
    out["random_forest_min_split_checksum"] = float(
        forest_min_split.predict(x).sum()
    )

    regression_y = regression_targets(x)
    started = time.perf_counter()
    regression_forest = RandomForestRegressor(
        n_estimators=FOREST_TREES,
        criterion="squared_error",
        max_features="sqrt",
        max_depth=8,
        min_samples_split=2,
        min_samples_leaf=2,
        bootstrap=True,
        oob_score=True,
        random_state=42,
        n_jobs=1,
    ).fit(x, regression_y)
    out["random_forest_regression_train_ms"] = (
        time.perf_counter() - started
    ) * 1000

    regression_checksum = 0.0
    started = time.perf_counter()
    for _ in range(FOREST_PREDICTIONS):
        regression_checksum += float(regression_forest.predict(x).sum())
    out["random_forest_regression_predict_ms"] = (
        time.perf_counter() - started
    ) * 1000
    out["random_forest_regression_tree_count"] = float(
        len(regression_forest.estimators_)
    )
    out["random_forest_regression_nodes"] = float(
        sum(tree.tree_.node_count for tree in regression_forest.estimators_)
    )
    out["random_forest_regression_r2"] = float(
        regression_forest.score(x, regression_y)
    )
    out["random_forest_regression_test_r2"] = float(
        regression_forest.score(
            forest_full_x[1200:], regression_targets(forest_full_x[1200:])
        )
    )
    out["random_forest_regression_checksum"] = regression_checksum
    out["random_forest_regression_oob_r2"] = float(
        regression_forest.oob_score_
    )

    for label, alpha in (
        ("001", 0.001),
        ("005", 0.005),
        ("020", 0.02),
        ("100", 0.1),
    ):
        pruned = DecisionTreeClassifier(
            criterion="gini",
            max_depth=8,
            min_samples_split=2,
            min_samples_leaf=2,
            random_state=0,
            ccp_alpha=alpha,
        ).fit(x, y)
        out[f"decision_tree_ccp_{label}_nodes"] = float(pruned.tree_.node_count)
        out[f"decision_tree_ccp_{label}_leaves"] = float(pruned.get_n_leaves())
        out[f"decision_tree_ccp_{label}_accuracy"] = float(pruned.score(x, y))
    path = DecisionTreeClassifier(
        criterion="gini",
        max_depth=8,
        min_samples_split=2,
        min_samples_leaf=2,
        random_state=0,
    ).cost_complexity_pruning_path(x, y)
    out["decision_tree_ccp_path_size"] = float(path.ccp_alphas.size)
    out["decision_tree_ccp_path_first_nonzero"] = float(path.ccp_alphas[1])
    out["decision_tree_ccp_path_final_alpha"] = float(path.ccp_alphas[-1])
    out["decision_tree_ccp_path_final_impurity"] = float(path.impurities[-1])

    min_weight_model: DecisionTreeClassifier | None = None
    started = time.perf_counter()
    for _ in range(FITS):
        min_weight_model = DecisionTreeClassifier(
            criterion="gini",
            max_depth=8,
            min_samples_split=2,
            min_samples_leaf=2,
            min_weight_fraction_leaf=0.05,
            random_state=0,
        ).fit(x, y)
    out["decision_tree_min_weight_005_train_ms"] = (
        time.perf_counter() - started
    ) * 1000
    assert min_weight_model is not None
    out["decision_tree_min_weight_005_nodes"] = float(
        min_weight_model.tree_.node_count
    )
    out["decision_tree_min_weight_005_leaves"] = float(
        min_weight_model.get_n_leaves()
    )
    out["decision_tree_min_weight_005_accuracy"] = float(
        min_weight_model.score(x, y)
    )
    out["decision_tree_min_weight_005_checksum"] = float(
        min_weight_model.predict(x).sum()
    )

    weight_x = np.arange(6, dtype=np.float64).reshape(-1, 1)
    weight_values = np.asarray([8, 1, 1, 1, 1, 1], dtype=np.float64)
    weighted_leaf_clf = DecisionTreeClassifier(
        criterion="gini",
        max_depth=3,
        min_weight_fraction_leaf=0.3,
        random_state=0,
    ).fit(
        weight_x,
        np.asarray([0, 0, 0, 1, 0, 1], dtype=np.int64),
        sample_weight=weight_values,
    )
    weighted_leaf_reg = DecisionTreeRegressor(
        criterion="squared_error",
        max_depth=3,
        min_weight_fraction_leaf=0.3,
        random_state=0,
    ).fit(
        weight_x,
        np.asarray([0, 0, 0, 10, 0, 10], dtype=np.float64),
        sample_weight=weight_values,
    )
    out["decision_tree_min_weight_classifier_nodes"] = float(
        weighted_leaf_clf.tree_.node_count
    )
    out["decision_tree_min_weight_classifier_threshold"] = float(
        weighted_leaf_clf.tree_.threshold[0]
    )
    out["decision_tree_min_weight_classifier_checksum"] = float(
        weighted_leaf_clf.predict(weight_x).sum()
    )
    out["decision_tree_min_weight_regression_nodes"] = float(
        weighted_leaf_reg.tree_.node_count
    )
    out["decision_tree_min_weight_regression_threshold"] = float(
        weighted_leaf_reg.tree_.threshold[0]
    )
    out["decision_tree_min_weight_regression_checksum"] = float(
        weighted_leaf_reg.predict(weight_x).sum()
    )

    min_weight_missing_x = np.asarray(
        [[0.0], [1.0], [8.0], [9.0], [np.nan], [np.nan]]
    )
    min_weight_missing_left = DecisionTreeClassifier(
        criterion="gini",
        max_depth=1,
        min_weight_fraction_leaf=0.5,
        random_state=0,
    ).fit(
        min_weight_missing_x,
        np.asarray([0, 0, 1, 1, 0, 0], dtype=np.int64),
    )
    min_weight_missing_right = DecisionTreeClassifier(
        criterion="gini",
        max_depth=1,
        min_weight_fraction_leaf=0.5,
        random_state=0,
    ).fit(
        min_weight_missing_x,
        np.asarray([0, 0, 1, 1, 1, 1], dtype=np.int64),
    )
    out["decision_tree_min_weight_missing_left_threshold"] = float(
        min_weight_missing_left.tree_.threshold[0]
    )
    out["decision_tree_min_weight_missing_left_flag"] = float(
        min_weight_missing_left.tree_.missing_go_to_left[0]
    )
    out["decision_tree_min_weight_missing_left_checksum"] = float(
        min_weight_missing_left.predict(min_weight_missing_x).sum()
    )
    out["decision_tree_min_weight_missing_right_threshold"] = float(
        min_weight_missing_right.tree_.threshold[0]
    )
    out["decision_tree_min_weight_missing_right_flag"] = float(
        min_weight_missing_right.tree_.missing_go_to_left[0]
    )
    out["decision_tree_min_weight_missing_right_checksum"] = float(
        min_weight_missing_right.predict(min_weight_missing_x).sum()
    )

    leaf_index_x = np.arange(6, dtype=np.float64).reshape(-1, 1)
    leaf_index_classifier = DecisionTreeClassifier(random_state=0).fit(
        leaf_index_x, np.asarray([0, 0, 1, 1, 2, 2], dtype=np.int64)
    )
    leaf_index_regressor = DecisionTreeRegressor(random_state=0).fit(
        leaf_index_x, np.asarray([0, 0, 10, 10, 20, 20], dtype=np.float64)
    )
    leaf_index_missing_x = np.asarray(
        [[0], [1], [8], [9], [np.nan], [np.nan]], dtype=np.float64
    )
    leaf_index_missing = DecisionTreeClassifier(random_state=0).fit(
        leaf_index_missing_x,
        np.asarray([0, 0, 1, 1, 0, 0], dtype=np.int64),
    )
    leaf_index_forest = RandomForestClassifier(
        n_estimators=1,
        criterion="gini",
        max_features=1.0,
        min_samples_leaf=1,
        bootstrap=False,
        random_state=0,
        n_jobs=1,
    ).fit(
        leaf_index_x, np.asarray([0, 0, 1, 1, 2, 2], dtype=np.int64)
    )
    out["decision_tree_leaf_index_classifier_checksum"] = float(
        leaf_index_classifier.apply(leaf_index_x).sum()
    )
    out["decision_tree_leaf_index_regression_checksum"] = float(
        leaf_index_regressor.apply(leaf_index_x).sum()
    )
    out["decision_tree_leaf_index_missing_checksum"] = float(
        leaf_index_missing.apply(leaf_index_missing_x).sum()
    )
    out["random_forest_leaf_index_exact_checksum"] = float(
        leaf_index_forest.apply(leaf_index_x).sum()
    )

    for label, min_gain in (
        ("001", 0.001),
        ("005", 0.005),
        ("020", 0.02),
    ):
        regularized: DecisionTreeClassifier | None = None
        repeats = FITS if label == "005" else 1
        started = time.perf_counter()
        for _ in range(repeats):
            regularized = DecisionTreeClassifier(
                criterion="gini",
                max_depth=8,
                min_samples_split=2,
                min_samples_leaf=2,
                min_impurity_decrease=min_gain,
                random_state=0,
            ).fit(x, y)
        if label == "005":
            out["decision_tree_min_gain_005_train_ms"] = (
                time.perf_counter() - started
            ) * 1000
        assert regularized is not None
        out[f"decision_tree_min_gain_{label}_nodes"] = float(
            regularized.tree_.node_count
        )
        out[f"decision_tree_min_gain_{label}_leaves"] = float(
            regularized.get_n_leaves()
        )
        out[f"decision_tree_min_gain_{label}_accuracy"] = float(
            regularized.score(x, y)
        )

    gain_regression_x = np.arange(4, dtype=np.float64).reshape(-1, 1)
    gain_regression_y = np.asarray([0, 2, 4, 6], dtype=np.float64)
    gain_regression_exact = DecisionTreeRegressor(
        min_impurity_decrease=4.0, random_state=0
    ).fit(gain_regression_x, gain_regression_y)
    gain_regression_blocked = DecisionTreeRegressor(
        min_impurity_decrease=4.0001, random_state=0
    ).fit(gain_regression_x, gain_regression_y)
    out["decision_tree_min_gain_regression_exact_nodes"] = float(
        gain_regression_exact.tree_.node_count
    )
    out["decision_tree_min_gain_regression_exact_checksum"] = float(
        gain_regression_exact.predict(gain_regression_x).sum()
    )
    out["decision_tree_min_gain_regression_blocked_nodes"] = float(
        gain_regression_blocked.tree_.node_count
    )
    out["decision_tree_min_gain_regression_blocked_checksum"] = float(
        gain_regression_blocked.predict(gain_regression_x).sum()
    )

    missing_x = np.asarray(
        [[0], [1], [8], [9], [np.nan], [np.nan]], dtype=np.float64
    )
    missing_queries = np.asarray(
        [[np.nan], [np.nan], [0], [9]], dtype=np.float64
    )
    missing_left = DecisionTreeClassifier(random_state=0).fit(
        missing_x, [0, 0, 1, 1, 0, 0]
    )
    missing_right = DecisionTreeClassifier(random_state=0).fit(
        missing_x, [0, 0, 1, 1, 1, 1]
    )
    missing_regression = DecisionTreeRegressor(random_state=0).fit(
        missing_x, [0, 0, 10, 10, 0, 0]
    )
    out.update(
        {
            "decision_tree_missing_left_threshold": float(
                missing_left.tree_.threshold[0]
            ),
            "decision_tree_missing_left_flag": float(
                missing_left.tree_.missing_go_to_left[0]
            ),
            "decision_tree_missing_left_checksum": float(
                missing_left.predict(missing_queries).sum()
            ),
            "decision_tree_missing_right_threshold": float(
                missing_right.tree_.threshold[0]
            ),
            "decision_tree_missing_right_flag": float(
                missing_right.tree_.missing_go_to_left[0]
            ),
            "decision_tree_missing_right_checksum": float(
                missing_right.predict(missing_queries).sum()
            ),
            "decision_tree_missing_regression_threshold": float(
                missing_regression.tree_.threshold[0]
            ),
            "decision_tree_missing_regression_flag": float(
                missing_regression.tree_.missing_go_to_left[0]
            ),
            "decision_tree_missing_regression_checksum": float(
                missing_regression.predict(missing_queries).sum()
            ),
        }
    )
    for label, fallback_x, fallback_y in (
        ("left", [[0], [1], [9], [10]], [0, 0, 0, 1]),
        ("right", [[0], [1], [9], [10]], [0, 1, 1, 1]),
        ("tie", [[0], [1], [8], [9]], [0, 0, 1, 1]),
    ):
        fallback = DecisionTreeClassifier(random_state=0).fit(
            np.asarray(fallback_x, dtype=np.float64), fallback_y
        )
        out[f"decision_tree_missing_fallback_{label}_flag"] = float(
            fallback.tree_.missing_go_to_left[0]
        )
        out[f"decision_tree_missing_fallback_{label}_prediction"] = float(
            fallback.predict([[np.nan]])[0]
        )
    return out


def median_metrics(samples: list[dict[str, float]]) -> dict[str, float]:
    return {
        name: statistics.median(sample[name] for sample in samples)
        for name in samples[0]
    }


def main() -> None:
    if sklearn.__version__ != PINNED_SKLEARN:
        raise SystemExit(
            f"expected scikit-learn {PINNED_SKLEARN}, got {sklearn.__version__}"
        )
    x, y = fixture()
    with tempfile.TemporaryDirectory(prefix="koala-tree-bench-") as temp_dir:
        executable = Path(temp_dir) / "decision-tree-speed"
        subprocess.run(
            [
                str(ROOT / "bin" / "tungsten"),
                "compile",
                str(BENCH / "decision_tree_speed.w"),
                "--out",
                str(executable),
            ],
            cwd=ROOT,
            check=True,
            text=True,
            capture_output=True,
        )
        koala = median_metrics(koala_samples(executable))
    reference = median_metrics([sklearn_sample(x, y) for _ in range(SAMPLES)])

    parity_keys = [
        "decision_tree_nodes",
        "decision_tree_accuracy",
        "decision_tree_checksum",
        "decision_tree_predict_proba_checksum",
        "decision_tree_predict_proba_column_checksum",
        "decision_tree_entropy_nodes",
        "decision_tree_entropy_accuracy",
        "decision_tree_entropy_checksum",
        "random_forest_min_split_nodes",
        "random_forest_min_split_accuracy",
        "random_forest_min_split_checksum",
    ]
    for label in ("001", "005", "020", "100"):
        parity_keys.extend(
            (
                f"decision_tree_ccp_{label}_nodes",
                f"decision_tree_ccp_{label}_leaves",
                f"decision_tree_ccp_{label}_accuracy",
            )
        )
    parity_keys.extend(
        (
            "decision_tree_ccp_path_size",
            "decision_tree_ccp_path_first_nonzero",
            "decision_tree_ccp_path_final_alpha",
            "decision_tree_ccp_path_final_impurity",
            "decision_tree_min_weight_005_nodes",
            "decision_tree_min_weight_005_leaves",
            "decision_tree_min_weight_005_accuracy",
            "decision_tree_min_weight_005_checksum",
            "decision_tree_min_weight_classifier_nodes",
            "decision_tree_min_weight_classifier_threshold",
            "decision_tree_min_weight_classifier_checksum",
            "decision_tree_min_weight_regression_nodes",
            "decision_tree_min_weight_regression_threshold",
            "decision_tree_min_weight_regression_checksum",
            "decision_tree_min_weight_missing_left_threshold",
            "decision_tree_min_weight_missing_left_flag",
            "decision_tree_min_weight_missing_left_checksum",
            "decision_tree_min_weight_missing_right_threshold",
            "decision_tree_min_weight_missing_right_flag",
            "decision_tree_min_weight_missing_right_checksum",
            "decision_tree_leaf_index_classifier_checksum",
            "decision_tree_leaf_index_regression_checksum",
            "decision_tree_leaf_index_missing_checksum",
            "random_forest_leaf_index_exact_checksum",
        )
    )
    for label in ("001", "005", "020"):
        parity_keys.extend(
            (
                f"decision_tree_min_gain_{label}_nodes",
                f"decision_tree_min_gain_{label}_leaves",
                f"decision_tree_min_gain_{label}_accuracy",
            )
        )
    parity_keys.extend(
        (
            "decision_tree_min_gain_regression_exact_nodes",
            "decision_tree_min_gain_regression_exact_checksum",
            "decision_tree_min_gain_regression_blocked_nodes",
            "decision_tree_min_gain_regression_blocked_checksum",
        )
    )
    parity_keys.extend(
        (
            "decision_tree_missing_left_threshold",
            "decision_tree_missing_left_flag",
            "decision_tree_missing_left_checksum",
            "decision_tree_missing_right_threshold",
            "decision_tree_missing_right_flag",
            "decision_tree_missing_right_checksum",
            "decision_tree_missing_regression_threshold",
            "decision_tree_missing_regression_flag",
            "decision_tree_missing_regression_checksum",
            "decision_tree_missing_fallback_left_flag",
            "decision_tree_missing_fallback_left_prediction",
            "decision_tree_missing_fallback_right_flag",
            "decision_tree_missing_fallback_right_prediction",
            "decision_tree_missing_fallback_tie_flag",
            "decision_tree_missing_fallback_tie_prediction",
        )
    )
    parity = all(abs(koala[key] - reference[key]) <= 1e-10 for key in parity_keys)
    missing_quality = (
        koala["decision_tree_missing_accuracy"] + MISSING_ACCURACY_TOLERANCE
        >= reference["decision_tree_missing_accuracy"]
        and koala["decision_tree_missing_nodes"]
        <= reference["decision_tree_missing_nodes"] * MISSING_NODE_RATIO_LIMIT
    )
    forest_quality = (
        koala["random_forest_tree_count"] == reference["random_forest_tree_count"]
        and koala["random_forest_test_accuracy"] + FOREST_ACCURACY_TOLERANCE
        >= reference["random_forest_test_accuracy"]
        and koala["random_forest_oob_score"] + FOREST_OOB_TOLERANCE
        >= reference["random_forest_oob_score"]
    )
    forest_min_weight_quality = (
        koala["random_forest_min_weight_001_test_accuracy"]
        + FOREST_MIN_WEIGHT_ACCURACY_TOLERANCE
        >= reference["random_forest_min_weight_001_test_accuracy"]
        and koala["random_forest_min_weight_001_oob_score"]
        + FOREST_OOB_TOLERANCE
        >= reference["random_forest_min_weight_001_oob_score"]
        and koala["random_forest_min_weight_001_test_accuracy"]
        + FOREST_MIN_WEIGHT_QUALITY_DROP
        >= koala["random_forest_test_accuracy"]
        and koala["random_forest_min_weight_001_oob_score"]
        + FOREST_MIN_WEIGHT_QUALITY_DROP
        >= koala["random_forest_oob_score"]
        and koala["random_forest_train_ms"]
        >= (
            koala["random_forest_min_weight_001_train_ms"]
            * FOREST_MIN_WEIGHT_SPEEDUP_FLOOR
        )
    )
    forest_half_sample_quality = (
        koala["random_forest_half_sample_test_accuracy"]
        + FOREST_MAX_SAMPLES_ACCURACY_TOLERANCE
        >= reference["random_forest_half_sample_test_accuracy"]
        and koala["random_forest_half_sample_oob_score"]
        + FOREST_OOB_TOLERANCE
        >= reference["random_forest_half_sample_oob_score"]
        and koala["random_forest_half_sample_test_accuracy"]
        + FOREST_MAX_SAMPLES_QUALITY_DROP
        >= koala["random_forest_test_accuracy"]
        and koala["random_forest_half_sample_oob_score"]
        + FOREST_MAX_SAMPLES_QUALITY_DROP
        >= koala["random_forest_oob_score"]
    )
    forest_regression_quality = (
        koala["random_forest_regression_tree_count"]
        == reference["random_forest_regression_tree_count"]
        and koala["random_forest_regression_test_r2"]
        + FOREST_REGRESSION_R2_TOLERANCE
        >= reference["random_forest_regression_test_r2"]
        and koala["random_forest_regression_oob_r2"]
        + FOREST_REGRESSION_R2_TOLERANCE
        >= reference["random_forest_regression_oob_r2"]
    )
    train_ratio = reference["decision_tree_train_ms"] / koala["decision_tree_train_ms"]
    predict_ratio = (
        reference["decision_tree_predict_ms"] / koala["decision_tree_predict_ms"]
    )
    leaf_index_ratio = (
        reference["decision_tree_leaf_index_ms"]
        / koala["decision_tree_leaf_index_ms"]
    )
    missing_train_ratio = (
        reference["decision_tree_missing_train_ms"]
        / koala["decision_tree_missing_train_ms"]
    )
    missing_predict_ratio = (
        reference["decision_tree_missing_predict_ms"]
        / koala["decision_tree_missing_predict_ms"]
    )
    forest_train_ratio = (
        reference["random_forest_train_ms"] / koala["random_forest_train_ms"]
    )
    forest_predict_ratio = (
        reference["random_forest_predict_ms"]
        / koala["random_forest_predict_ms"]
    )
    forest_leaf_index_ratio = (
        reference["random_forest_leaf_index_ms"]
        / koala["random_forest_leaf_index_ms"]
    )
    koala_min_weight_speedup = (
        koala["random_forest_train_ms"]
        / koala["random_forest_min_weight_001_train_ms"]
    )
    koala_half_sample_speedup = (
        koala["random_forest_train_ms"]
        / koala["random_forest_half_sample_train_ms"]
    )
    forest_regression_train_ratio = (
        reference["random_forest_regression_train_ms"]
        / koala["random_forest_regression_train_ms"]
    )
    forest_regression_predict_ratio = (
        reference["random_forest_regression_predict_ms"]
        / koala["random_forest_regression_predict_ms"]
    )

    print(f"scikit_learn_version,{sklearn.__version__}")
    print("implementation,train_ms_2_fits,predict_ms_250_runs,nodes,accuracy,checksum,importance_checksum")
    for name, metrics in (("koala", koala), ("scikit-learn", reference)):
        print(
            f"{name},{metrics['decision_tree_train_ms']:.6g},"
            f"{metrics['decision_tree_predict_ms']:.6g},"
            f"{metrics['decision_tree_nodes']:.0f},"
            f"{metrics['decision_tree_accuracy']:.17g},"
            f"{metrics['decision_tree_checksum']:.0f},"
            f"{metrics['decision_tree_importance_checksum']:.17g}"
        )
    print(f"speed_ratio_sklearn_over_koala_train,{train_ratio:.6g}")
    print(f"speed_ratio_sklearn_over_koala_predict,{predict_ratio:.6g}")
    print(
        "leaf_indices_250_runs,koala_ms,sklearn_ms,"
        "koala_checksum,sklearn_checksum"
    )
    print(
        f"full,{koala['decision_tree_leaf_index_ms']:.6g},"
        f"{reference['decision_tree_leaf_index_ms']:.6g},"
        f"{koala['decision_tree_leaf_index_checksum']:.0f},"
        f"{reference['decision_tree_leaf_index_checksum']:.0f}"
    )
    print(
        "leaf_index_speed_ratio_sklearn_over_koala,"
        f"{leaf_index_ratio:.6g}"
    )
    print(
        "predict_proba_250_runs,koala_ms,sklearn_ms,"
        "koala_checksum,sklearn_checksum"
    )
    print(
        f"predict_proba,{koala['decision_tree_predict_proba_ms']:.6g},"
        f"{reference['decision_tree_predict_proba_ms']:.6g},"
        f"{koala['decision_tree_predict_proba_checksum']:.17g},"
        f"{reference['decision_tree_predict_proba_checksum']:.17g}"
    )
    print(
        "predict_proba_column_250_runs,koala_ms,sklearn_ms,"
        "koala_checksum,sklearn_checksum"
    )
    print(
        f"class_1,{koala['decision_tree_predict_proba_column_ms']:.6g},"
        f"{reference['decision_tree_predict_proba_column_ms']:.6g},"
        f"{koala['decision_tree_predict_proba_column_checksum']:.17g},"
        f"{reference['decision_tree_predict_proba_column_checksum']:.17g}"
    )
    print("entropy,train_ms_2_fits,nodes,accuracy,checksum")
    for name, metrics in (("koala", koala), ("scikit-learn", reference)):
        print(
            f"{name},{metrics['decision_tree_entropy_train_ms']:.6g},"
            f"{metrics['decision_tree_entropy_nodes']:.0f},"
            f"{metrics['decision_tree_entropy_accuracy']:.17g},"
            f"{metrics['decision_tree_entropy_checksum']:.0f}"
        )
    print("missing_7_7_percent,train_ms_2_fits,predict_ms_250_runs,nodes,accuracy,checksum")
    for name, metrics in (("koala", koala), ("scikit-learn", reference)):
        print(
            f"{name},{metrics['decision_tree_missing_train_ms']:.6g},"
            f"{metrics['decision_tree_missing_predict_ms']:.6g},"
            f"{metrics['decision_tree_missing_nodes']:.0f},"
            f"{metrics['decision_tree_missing_accuracy']:.17g},"
            f"{metrics['decision_tree_missing_checksum']:.0f}"
        )
    print(
        "missing_speed_ratio_sklearn_over_koala_train,"
        f"{missing_train_ratio:.6g}"
    )
    print(
        "missing_speed_ratio_sklearn_over_koala_predict,"
        f"{missing_predict_ratio:.6g}"
    )
    print("random_forest_50,train_ms_1_fit,predict_ms_10_runs,trees,nodes,train_accuracy,test_accuracy,checksum,oob_score")
    for name, metrics in (("koala", koala), ("scikit-learn", reference)):
        print(
            f"{name},{metrics['random_forest_train_ms']:.6g},"
            f"{metrics['random_forest_predict_ms']:.6g},"
            f"{metrics['random_forest_tree_count']:.0f},"
            f"{metrics['random_forest_nodes']:.0f},"
            f"{metrics['random_forest_accuracy']:.17g},"
            f"{metrics['random_forest_test_accuracy']:.17g},"
            f"{metrics['random_forest_checksum']:.0f},"
            f"{metrics['random_forest_oob_score']:.17g}"
        )
    print(f"forest_speed_ratio_sklearn_over_koala_train,{forest_train_ratio:.6g}")
    print(
        "forest_speed_ratio_sklearn_over_koala_predict,"
        f"{forest_predict_ratio:.6g}"
    )
    print(
        "random_forest_leaf_indices_10_runs,koala_ms,sklearn_ms,"
        "koala_checksum,sklearn_checksum"
    )
    print(
        f"full,{koala['random_forest_leaf_index_ms']:.6g},"
        f"{reference['random_forest_leaf_index_ms']:.6g},"
        f"{koala['random_forest_leaf_index_checksum']:.0f},"
        f"{reference['random_forest_leaf_index_checksum']:.0f}"
    )
    print(
        "forest_leaf_index_speed_ratio_sklearn_over_koala,"
        f"{forest_leaf_index_ratio:.6g}"
    )
    print(
        "random_forest_min_weight_fraction_leaf_001,train_ms_1_fit,nodes,"
        "train_accuracy,test_accuracy,checksum,oob_score"
    )
    for name, metrics in (("koala", koala), ("scikit-learn", reference)):
        print(
            f"{name},{metrics['random_forest_min_weight_001_train_ms']:.6g},"
            f"{metrics['random_forest_min_weight_001_nodes']:.0f},"
            f"{metrics['random_forest_min_weight_001_accuracy']:.17g},"
            f"{metrics['random_forest_min_weight_001_test_accuracy']:.17g},"
            f"{metrics['random_forest_min_weight_001_checksum']:.17g},"
            f"{metrics['random_forest_min_weight_001_oob_score']:.17g}"
        )
    print(
        "koala_min_weight_fraction_leaf_001_training_speedup,"
        f"{koala_min_weight_speedup:.6g}"
    )
    print(
        "random_forest_predict_proba_10_runs,koala_ms,sklearn_ms,"
        "koala_checksum,sklearn_checksum"
    )
    print(
        f"full,{koala['random_forest_predict_proba_ms']:.6g},"
        f"{reference['random_forest_predict_proba_ms']:.6g},"
        f"{koala['random_forest_predict_proba_checksum']:.17g},"
        f"{reference['random_forest_predict_proba_checksum']:.17g}"
    )
    print(
        "random_forest_predict_proba_column_10_runs,koala_ms,sklearn_ms,"
        "koala_checksum,sklearn_checksum"
    )
    print(
        f"class_1,{koala['random_forest_predict_proba_column_ms']:.6g},"
        f"{reference['random_forest_predict_proba_column_ms']:.6g},"
        f"{koala['random_forest_predict_proba_column_checksum']:.17g},"
        f"{reference['random_forest_predict_proba_column_checksum']:.17g}"
    )
    print(
        "random_forest_max_samples_600,train_ms_1_fit,nodes,"
        "train_accuracy,test_accuracy,checksum,oob_score"
    )
    for name, metrics in (("koala", koala), ("scikit-learn", reference)):
        print(
            f"{name},{metrics['random_forest_half_sample_train_ms']:.6g},"
            f"{metrics['random_forest_half_sample_nodes']:.0f},"
            f"{metrics['random_forest_half_sample_accuracy']:.17g},"
            f"{metrics['random_forest_half_sample_test_accuracy']:.17g},"
            f"{metrics['random_forest_half_sample_checksum']:.0f},"
            f"{metrics['random_forest_half_sample_oob_score']:.17g}"
        )
    print(
        "koala_max_samples_600_training_speedup,"
        f"{koala_half_sample_speedup:.6g}"
    )
    print(
        "forest_min_samples_split_200,koala_nodes,sklearn_nodes,"
        "koala_accuracy,sklearn_accuracy,koala_checksum,sklearn_checksum"
    )
    print(
        f"200,{koala['random_forest_min_split_nodes']:.0f},"
        f"{reference['random_forest_min_split_nodes']:.0f},"
        f"{koala['random_forest_min_split_accuracy']:.17g},"
        f"{reference['random_forest_min_split_accuracy']:.17g},"
        f"{koala['random_forest_min_split_checksum']:.17g},"
        f"{reference['random_forest_min_split_checksum']:.17g}"
    )
    print("random_forest_regression_50,train_ms_1_fit,predict_ms_10_runs,trees,nodes,train_r2,test_r2,checksum,oob_r2")
    for name, metrics in (("koala", koala), ("scikit-learn", reference)):
        print(
            f"{name},{metrics['random_forest_regression_train_ms']:.6g},"
            f"{metrics['random_forest_regression_predict_ms']:.6g},"
            f"{metrics['random_forest_regression_tree_count']:.0f},"
            f"{metrics['random_forest_regression_nodes']:.0f},"
            f"{metrics['random_forest_regression_r2']:.17g},"
            f"{metrics['random_forest_regression_test_r2']:.17g},"
            f"{metrics['random_forest_regression_checksum']:.17g},"
            f"{metrics['random_forest_regression_oob_r2']:.17g}"
        )
    print(
        "forest_regression_speed_ratio_sklearn_over_koala_train,"
        f"{forest_regression_train_ratio:.6g}"
    )
    print(
        "forest_regression_speed_ratio_sklearn_over_koala_predict,"
        f"{forest_regression_predict_ratio:.6g}"
    )
    print("ccp_alpha,koala_nodes,sklearn_nodes,koala_leaves,sklearn_leaves,koala_accuracy,sklearn_accuracy")
    for label, alpha in (("001", 0.001), ("005", 0.005), ("020", 0.02), ("100", 0.1)):
        prefix = f"decision_tree_ccp_{label}"
        print(
            f"{alpha:.3g},{koala[prefix + '_nodes']:.0f},"
            f"{reference[prefix + '_nodes']:.0f},"
            f"{koala[prefix + '_leaves']:.0f},"
            f"{reference[prefix + '_leaves']:.0f},"
            f"{koala[prefix + '_accuracy']:.17g},"
            f"{reference[prefix + '_accuracy']:.17g}"
        )
    print(
        "ccp_path,"
        f"{koala['decision_tree_ccp_path_size']:.0f},"
        f"{reference['decision_tree_ccp_path_size']:.0f},"
        f"{koala['decision_tree_ccp_path_first_nonzero']:.17g},"
        f"{reference['decision_tree_ccp_path_first_nonzero']:.17g},"
        f"{koala['decision_tree_ccp_path_final_alpha']:.17g},"
        f"{reference['decision_tree_ccp_path_final_alpha']:.17g},"
        f"{koala['decision_tree_ccp_path_final_impurity']:.17g},"
        f"{reference['decision_tree_ccp_path_final_impurity']:.17g}"
    )
    print(
        "ccp_path_100_koala_only_ms,"
        f"{koala['decision_tree_ccp_path_ms']:.6g}"
    )
    print(
        "min_weight_fraction_leaf_005,koala_ms_2_fits,sklearn_ms_2_fits,"
        "koala_nodes,sklearn_nodes,koala_leaves,sklearn_leaves,"
        "koala_accuracy,sklearn_accuracy"
    )
    print(
        f"0.05,{koala['decision_tree_min_weight_005_train_ms']:.6g},"
        f"{reference['decision_tree_min_weight_005_train_ms']:.6g},"
        f"{koala['decision_tree_min_weight_005_nodes']:.0f},"
        f"{reference['decision_tree_min_weight_005_nodes']:.0f},"
        f"{koala['decision_tree_min_weight_005_leaves']:.0f},"
        f"{reference['decision_tree_min_weight_005_leaves']:.0f},"
        f"{koala['decision_tree_min_weight_005_accuracy']:.17g},"
        f"{reference['decision_tree_min_weight_005_accuracy']:.17g}"
    )
    print(
        "min_weight_fraction_leaf_weighted,"
        "koala_clf_nodes,sklearn_clf_nodes,koala_clf_threshold,"
        "sklearn_clf_threshold,koala_clf_checksum,sklearn_clf_checksum,"
        "koala_reg_nodes,sklearn_reg_nodes,koala_reg_threshold,"
        "sklearn_reg_threshold,koala_reg_checksum,sklearn_reg_checksum"
    )
    print(
        f"0.3,{koala['decision_tree_min_weight_classifier_nodes']:.0f},"
        f"{reference['decision_tree_min_weight_classifier_nodes']:.0f},"
        f"{koala['decision_tree_min_weight_classifier_threshold']:.17g},"
        f"{reference['decision_tree_min_weight_classifier_threshold']:.17g},"
        f"{koala['decision_tree_min_weight_classifier_checksum']:.17g},"
        f"{reference['decision_tree_min_weight_classifier_checksum']:.17g},"
        f"{koala['decision_tree_min_weight_regression_nodes']:.0f},"
        f"{reference['decision_tree_min_weight_regression_nodes']:.0f},"
        f"{koala['decision_tree_min_weight_regression_threshold']:.17g},"
        f"{reference['decision_tree_min_weight_regression_threshold']:.17g},"
        f"{koala['decision_tree_min_weight_regression_checksum']:.17g},"
        f"{reference['decision_tree_min_weight_regression_checksum']:.17g}"
    )
    print(
        "min_weight_fraction_leaf_missing,"
        "koala_left_threshold,sklearn_left_threshold,koala_left_flag,"
        "sklearn_left_flag,koala_left_checksum,sklearn_left_checksum,"
        "koala_right_threshold,sklearn_right_threshold,koala_right_flag,"
        "sklearn_right_flag,koala_right_checksum,sklearn_right_checksum"
    )
    print(
        f"0.5,{koala['decision_tree_min_weight_missing_left_threshold']:.17g},"
        f"{reference['decision_tree_min_weight_missing_left_threshold']:.17g},"
        f"{koala['decision_tree_min_weight_missing_left_flag']:.0f},"
        f"{reference['decision_tree_min_weight_missing_left_flag']:.0f},"
        f"{koala['decision_tree_min_weight_missing_left_checksum']:.17g},"
        f"{reference['decision_tree_min_weight_missing_left_checksum']:.17g},"
        f"{koala['decision_tree_min_weight_missing_right_threshold']:.17g},"
        f"{reference['decision_tree_min_weight_missing_right_threshold']:.17g},"
        f"{koala['decision_tree_min_weight_missing_right_flag']:.0f},"
        f"{reference['decision_tree_min_weight_missing_right_flag']:.0f},"
        f"{koala['decision_tree_min_weight_missing_right_checksum']:.17g},"
        f"{reference['decision_tree_min_weight_missing_right_checksum']:.17g}"
    )
    print(
        "leaf_index_exact,koala_classifier_checksum,"
        "sklearn_classifier_checksum,koala_regression_checksum,"
        "sklearn_regression_checksum,koala_missing_checksum,"
        "sklearn_missing_checksum,koala_forest_checksum,"
        "sklearn_forest_checksum"
    )
    print(
        f"preorder,{koala['decision_tree_leaf_index_classifier_checksum']:.0f},"
        f"{reference['decision_tree_leaf_index_classifier_checksum']:.0f},"
        f"{koala['decision_tree_leaf_index_regression_checksum']:.0f},"
        f"{reference['decision_tree_leaf_index_regression_checksum']:.0f},"
        f"{koala['decision_tree_leaf_index_missing_checksum']:.0f},"
        f"{reference['decision_tree_leaf_index_missing_checksum']:.0f},"
        f"{koala['random_forest_leaf_index_exact_checksum']:.0f},"
        f"{reference['random_forest_leaf_index_exact_checksum']:.0f}"
    )
    print(
        "min_impurity_decrease,koala_nodes,sklearn_nodes,"
        "koala_leaves,sklearn_leaves,koala_accuracy,sklearn_accuracy"
    )
    for label, min_gain in (("001", 0.001), ("005", 0.005), ("020", 0.02)):
        prefix = f"decision_tree_min_gain_{label}"
        print(
            f"{min_gain:.3g},{koala[prefix + '_nodes']:.0f},"
            f"{reference[prefix + '_nodes']:.0f},"
            f"{koala[prefix + '_leaves']:.0f},"
            f"{reference[prefix + '_leaves']:.0f},"
            f"{koala[prefix + '_accuracy']:.17g},"
            f"{reference[prefix + '_accuracy']:.17g}"
        )
    print(
        "min_impurity_decrease_005_speed,koala_ms_2_fits,"
        "sklearn_ms_2_fits"
    )
    print(
        f"0.005,{koala['decision_tree_min_gain_005_train_ms']:.6g},"
        f"{reference['decision_tree_min_gain_005_train_ms']:.6g}"
    )
    print(
        "min_impurity_regression,koala_exact_nodes,sklearn_exact_nodes,"
        "koala_exact_checksum,sklearn_exact_checksum,koala_blocked_nodes,"
        "sklearn_blocked_nodes,koala_blocked_checksum,sklearn_blocked_checksum"
    )
    print(
        "4_vs_4.0001,"
        f"{koala['decision_tree_min_gain_regression_exact_nodes']:.0f},"
        f"{reference['decision_tree_min_gain_regression_exact_nodes']:.0f},"
        f"{koala['decision_tree_min_gain_regression_exact_checksum']:.17g},"
        f"{reference['decision_tree_min_gain_regression_exact_checksum']:.17g},"
        f"{koala['decision_tree_min_gain_regression_blocked_nodes']:.0f},"
        f"{reference['decision_tree_min_gain_regression_blocked_nodes']:.0f},"
        f"{koala['decision_tree_min_gain_regression_blocked_checksum']:.17g},"
        f"{reference['decision_tree_min_gain_regression_blocked_checksum']:.17g}"
    )
    print(
        "koala_prediction_breakdown,validation_ms_250_runs,"
        "projection_ms_250_runs,descent_ms_250_runs"
    )
    print(
        f"koala,{koala['decision_tree_validation_ms']:.6g},"
        f"{koala['decision_tree_projection_ms']:.6g},"
        f"{koala['decision_tree_descent_ms']:.6g}"
    )
    print("missing_case,koala_threshold,sklearn_threshold,koala_missing_left,sklearn_missing_left,koala_checksum,sklearn_checksum")
    for label in ("left", "right", "regression"):
        prefix = f"decision_tree_missing_{label}"
        print(
            f"{label},{koala[prefix + '_threshold']:.17g},"
            f"{reference[prefix + '_threshold']:.17g},"
            f"{koala[prefix + '_flag']:.0f},"
            f"{reference[prefix + '_flag']:.0f},"
            f"{koala[prefix + '_checksum']:.17g},"
            f"{reference[prefix + '_checksum']:.17g}"
        )
    print("missing_fallback,koala_missing_left,sklearn_missing_left,koala_prediction,sklearn_prediction")
    for label in ("left", "right", "tie"):
        prefix = f"decision_tree_missing_fallback_{label}"
        print(
            f"{label},{koala[prefix + '_flag']:.0f},"
            f"{reference[prefix + '_flag']:.0f},"
            f"{koala[prefix + '_prediction']:.17g},"
            f"{reference[prefix + '_prediction']:.17g}"
        )
    print(f"exact_parity_gate,{'PASS' if parity else 'FAIL'}")
    print(f"missing_quality_size_gate,{'PASS' if missing_quality else 'FAIL'}")
    print(f"forest_quality_gate,{'PASS' if forest_quality else 'FAIL'}")
    print(
        "forest_min_weight_tradeoff_gate,"
        f"{'PASS' if forest_min_weight_quality else 'FAIL'}"
    )
    print(
        "forest_max_samples_quality_gate,"
        f"{'PASS' if forest_half_sample_quality else 'FAIL'}"
    )
    print(
        "forest_regression_quality_gate,"
        f"{'PASS' if forest_regression_quality else 'FAIL'}"
    )
    if (
        not parity
        or not missing_quality
        or not forest_quality
        or not forest_min_weight_quality
        or not forest_half_sample_quality
        or not forest_regression_quality
    ):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
