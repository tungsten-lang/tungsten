"""Scikit-learn differential for reference_koala.w.

Run both from the repository root with:

  python bits/tungsten-koala/benchmarks/compare_reference.py

The solvers are configured deterministically and the fixtures are identical.
This compares outcomes and held-out scores, not implementation internals or
wall-clock performance.
"""

import numpy as np
from sklearn.cluster import KMeans
from sklearn.calibration import CalibratedClassifierCV
from sklearn.datasets import load_iris
from sklearn.ensemble import GradientBoostingClassifier, GradientBoostingRegressor
from sklearn.inspection import permutation_importance
from sklearn.linear_model import LinearRegression, LogisticRegression
from sklearn.metrics import brier_score_loss, log_loss, silhouette_score
from sklearn.model_selection import KFold, StratifiedKFold, cross_val_score
from sklearn.naive_bayes import GaussianNB
from sklearn.neighbors import KNeighborsClassifier, KNeighborsRegressor
from sklearn.pipeline import Pipeline
from sklearn.compose import ColumnTransformer
from sklearn.preprocessing import OneHotEncoder, PolynomialFeatures, StandardScaler
from sklearn.tree import DecisionTreeClassifier, DecisionTreeRegressor


def emit(name: str, value: float) -> None:
    print(f"{name},{value:.15g}")


xor_x = np.array([[0, 0], [0, 1], [1, 0], [1, 1]], dtype=float)
xor_y = np.array([0, 1, 1, 0])
raw = LogisticRegression(C=1e6, solver="lbfgs").fit(xor_x, xor_y)
poly = Pipeline(
    [
        ("poly", PolynomialFeatures(2, include_bias=False)),
        ("model", LogisticRegression(C=1e6, solver="lbfgs")),
    ]
).fit(xor_x, xor_y)
emit("xor_raw_accuracy", raw.score(xor_x, xor_y))
emit("xor_poly_accuracy", poly.score(xor_x, xor_y))
xor_boost = GradientBoostingClassifier(
    n_estimators=20,
    learning_rate=0.1,
    max_depth=2,
    random_state=0,
).fit(xor_x, xor_y)
emit("xor_boost_accuracy", xor_boost.score(xor_x, xor_y))
emit("xor_boost_log_loss", log_loss(xor_y, xor_boost.predict_proba(xor_x)))

quad_x = np.arange(-7, 8, dtype=float).reshape(-1, 1)
quad_y = 3 * quad_x[:, 0] ** 2 + 2 * quad_x[:, 0] + 1
quad = Pipeline(
    [
        ("poly", PolynomialFeatures(2, include_bias=False)),
        ("model", LinearRegression()),
    ]
)
emit(
    "quadratic_cv_mean",
    cross_val_score(quad, quad_x, quad_y, cv=KFold(3, shuffle=False)).mean(),
)
quadratic_stump = DecisionTreeRegressor(max_depth=1, random_state=0).fit(
    quad_x, quad_y
)
quadratic_boost = GradientBoostingRegressor(
    n_estimators=60,
    learning_rate=0.1,
    max_depth=2,
    random_state=0,
).fit(quad_x, quad_y)
emit("quadratic_stump_r2", quadratic_stump.score(quad_x, quad_y))
emit("quadratic_boost_r2", quadratic_boost.score(quad_x, quad_y))

class_x = np.array(
    [
        [0, 0],
        [0, 1],
        [1, 0],
        [10, 10],
        [10, 11],
        [11, 10],
        [20, 0],
        [20, 1],
        [21, 0],
    ],
    dtype=float,
)
class_y = np.array(["a", "a", "a", "b", "b", "b", "c", "c", "c"])
emit(
    "multiclass_nb_cv_mean",
    cross_val_score(
        GaussianNB(),
        class_x,
        class_y,
        cv=StratifiedKFold(3, shuffle=False),
    ).mean(),
)
emit(
    "multiclass_boost_cv_mean",
    cross_val_score(
        GradientBoostingClassifier(
            n_estimators=20,
            learning_rate=0.1,
            max_depth=2,
            random_state=0,
        ),
        class_x,
        class_y,
        cv=StratifiedKFold(3, shuffle=False),
    ).mean(),
)
class_boost = GradientBoostingClassifier(
    n_estimators=20,
    learning_rate=0.1,
    max_depth=2,
    random_state=0,
).fit(class_x, class_y)
emit(
    "multiclass_boost_log_loss",
    log_loss(class_y, class_boost.predict_proba(class_x)),
)

softmax_x = np.repeat(np.eye(3), 6, axis=0)
softmax_y = np.repeat(np.array(["a", "b", "c"]), 6)
softmax_model = LogisticRegression(C=1e6, solver="lbfgs").fit(
    softmax_x, softmax_y
)
emit(
    "multiclass_logreg_cv_mean",
    cross_val_score(
        LogisticRegression(C=1e6, solver="lbfgs"),
        softmax_x,
        softmax_y,
        cv=StratifiedKFold(3, shuffle=False),
    ).mean(),
)
center_probabilities = softmax_model.predict_proba(np.zeros((3, 3)))
emit(
    "multiclass_center_log_loss",
    log_loss(
        np.array(["a", "b", "c"]),
        center_probabilities,
        labels=softmax_model.classes_,
    ),
)

iris = load_iris()
iris_indices = list(range(20)) + list(range(50, 70)) + list(range(100, 120))
iris_x = (iris.data[iris_indices] * 10).astype(int)
iris_y = iris.target[iris_indices]
iris_cv = StratifiedKFold(5, shuffle=False)
emit(
    "iris_logreg_cv_mean",
    cross_val_score(
        Pipeline(
            [
                ("scale", StandardScaler()),
                (
                    "model",
                    LogisticRegression(solver="lbfgs", max_iter=5000),
                ),
            ]
        ),
        iris_x,
        iris_y,
        cv=iris_cv,
    ).mean(),
)
emit(
    "iris_gaussian_nb_cv_mean",
    cross_val_score(GaussianNB(), iris_x, iris_y, cv=iris_cv).mean(),
)
emit(
    "iris_knn_cv_mean",
    cross_val_score(
        Pipeline(
            [
                ("scale", StandardScaler()),
                ("model", KNeighborsClassifier(3)),
            ]
        ),
        iris_x,
        iris_y,
        cv=iris_cv,
    ).mean(),
)

# Mixed numeric/categorical classification. The numeric feature repeats for
# every category, so the one-hot branch supplies all useful class signal.
mixed_x = np.array(
    [[age, city] for age in range(1, 7) for city in ("red", "blue", "green")],
    dtype=object,
)
mixed_y = np.array(
    [1 if city == "blue" else 0 for _age, city in mixed_x],
)
mixed_cv = StratifiedKFold(3, shuffle=False)
numeric_only = Pipeline(
    [
        (
            "prep",
            ColumnTransformer([("num", StandardScaler(), [0])]),
        ),
        ("model", LogisticRegression(C=1e6, solver="lbfgs", max_iter=5000)),
    ]
)
mixed_columns = Pipeline(
    [
        (
            "prep",
            ColumnTransformer(
                [
                    ("num", StandardScaler(), [0]),
                    (
                        "cat",
                        OneHotEncoder(handle_unknown="ignore"),
                        [1],
                    ),
                ]
            ),
        ),
        ("model", LogisticRegression(C=1e6, solver="lbfgs", max_iter=5000)),
    ]
)
emit(
    "mixed_numeric_only_cv_mean",
    cross_val_score(numeric_only, mixed_x, mixed_y, cv=mixed_cv).mean(),
)
emit(
    "mixed_column_transform_cv_mean",
    cross_val_score(mixed_columns, mixed_x, mixed_y, cv=mixed_cv).mean(),
)
mixed_columns.fit(mixed_x, mixed_y)
mixed_importance = permutation_importance(
    mixed_columns,
    mixed_x,
    mixed_y,
    n_repeats=20,
    random_state=42,
    scoring="accuracy",
)
emit("mixed_permutation_age", mixed_importance.importances_mean[0])
emit("mixed_permutation_city", mixed_importance.importances_mean[1])

# Uniform versus inverse-Euclidean-distance KNN on the same hand-computable
# classification and regression fixture as Koala.
knn_train_x = np.array([[0.0], [4.0], [5.0]])
knn_class_y = np.array(["a", "b", "b"])
knn_test_x = np.array([[1.0], [4.5]])
knn_test_y = np.array(["a", "b"])
knn_uniform = KNeighborsClassifier(3, weights="uniform").fit(
    knn_train_x, knn_class_y
)
knn_distance = KNeighborsClassifier(3, weights="distance").fit(
    knn_train_x, knn_class_y
)
emit("knn_uniform_accuracy", knn_uniform.score(knn_test_x, knn_test_y))
emit("knn_distance_accuracy", knn_distance.score(knn_test_x, knn_test_y))
class_a = list(knn_distance.classes_).index("a")
emit(
    "knn_distance_class_a_probability",
    knn_distance.predict_proba([[1.0]])[0, class_a],
)
knn_regression = KNeighborsRegressor(3, weights="distance").fit(
    knn_train_x, np.array([0.0, 4.0, 5.0])
)
emit(
    "knn_regressor_distance_prediction",
    knn_regression.predict([[1.0]])[0],
)
knn_duplicate = KNeighborsRegressor(3, weights="distance").fit(
    np.array([[0.0], [0.0], [10.0]]),
    np.array([2.0, 4.0, 10.0]),
)
emit(
    "knn_regressor_duplicate_prediction",
    knn_duplicate.predict([[0.0]])[0],
)

# The same held-out Versicolor/Virginica calibration problem as Koala:
# first 20 rows per class for training, next 20 for testing.
cal_train_idx = list(range(50, 70)) + list(range(100, 120))
cal_test_idx = list(range(70, 90)) + list(range(120, 140))
cal_train_x = (iris.data[cal_train_idx] * 10).astype(int)
cal_train_y = iris.target[cal_train_idx]
cal_test_x = (iris.data[cal_test_idx] * 10).astype(int)
cal_test_y = iris.target[cal_test_idx]
raw_tree = DecisionTreeClassifier(random_state=0).fit(cal_train_x, cal_train_y)
sigmoid_tree = CalibratedClassifierCV(
    DecisionTreeClassifier(random_state=0),
    method="sigmoid",
    cv=5,
    ensemble=True,
).fit(cal_train_x, cal_train_y)
isotonic_tree = CalibratedClassifierCV(
    DecisionTreeClassifier(random_state=0),
    method="isotonic",
    cv=5,
    ensemble=True,
).fit(cal_train_x, cal_train_y)
raw_tree_scores = raw_tree.predict_proba(cal_test_x)[:, 1]
sigmoid_tree_scores = sigmoid_tree.predict_proba(cal_test_x)[:, 1]
isotonic_tree_scores = isotonic_tree.predict_proba(cal_test_x)[:, 1]
emit("iris_tree_raw_log_loss", log_loss(cal_test_y, raw_tree_scores))
emit("iris_tree_sigmoid_log_loss", log_loss(cal_test_y, sigmoid_tree_scores))
emit("iris_tree_isotonic_log_loss", log_loss(cal_test_y, isotonic_tree_scores))
emit(
    "iris_tree_raw_brier",
    brier_score_loss(cal_test_y, raw_tree_scores, pos_label=2),
)
emit(
    "iris_tree_isotonic_brier",
    brier_score_loss(cal_test_y, isotonic_tree_scores, pos_label=2),
)

cluster_x = np.array(
    [
        [0, 0],
        [0, 1],
        [1, 0],
        [1, 1],
        [10, 10],
        [10, 11],
        [11, 10],
        [11, 11],
    ],
    dtype=float,
)
km = KMeans(
    n_clusters=2,
    init=cluster_x[:2],
    n_init=1,
    random_state=0,
).fit(cluster_x)
emit("two_box_silhouette", silhouette_score(cluster_x, km.labels_))
