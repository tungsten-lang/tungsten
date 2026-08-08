#!/usr/bin/env python3
"""Independent NumPy references for focused Core Probability invariants.

This intentionally covers deterministic linear algebra and finite-state
probability only. Sampling streams have Tungsten cross-engine golden vectors;
they are not expected to match NumPy's unrelated RNG algorithms.
"""

import math

import numpy as np


mean = np.array([1.0, -2.0])
covariance = np.array([[4.0, 1.0], [1.0, 9.0]])
point = np.array([3.0, -1.0])

cholesky = np.linalg.cholesky(covariance)
sign, log_determinant = np.linalg.slogdet(covariance)
assert sign == 1.0
center_log_density = -0.5 * (
    2.0 * math.log(2.0 * math.pi) + log_determinant
)
difference = point - mean
mahalanobis = float(difference @ np.linalg.solve(covariance, difference))

np.testing.assert_allclose(
    cholesky,
    np.array([[2.0, 0.0], [0.5, 2.958039891549808]]),
    rtol=2e-15,
    atol=2e-15,
)
np.testing.assert_allclose(log_determinant, math.log(35.0), rtol=2e-15)
np.testing.assert_allclose(center_log_density, -3.615551097154052, rtol=2e-15)
np.testing.assert_allclose(mahalanobis, 1.0285714285714285, rtol=2e-15)

# Conditional coordinate 1 given coordinate 0 == 3.
conditional_mean = mean[1] + covariance[1, 0] / covariance[0, 0] * (
    3.0 - mean[0]
)
conditional_variance = covariance[1, 1] - (
    covariance[1, 0] * covariance[0, 1] / covariance[0, 0]
)
np.testing.assert_allclose(conditional_mean, -1.5, rtol=0.0, atol=0.0)
np.testing.assert_allclose(conditional_variance, 8.75, rtol=0.0, atol=0.0)

# Affine image [1, 2] X + 3.
transform = np.array([[1.0, 2.0]])
image_mean = transform @ mean + np.array([3.0])
image_covariance = transform @ covariance @ transform.T
np.testing.assert_allclose(image_mean, np.array([0.0]), rtol=0.0, atol=0.0)
np.testing.assert_allclose(image_covariance, np.array([[44.0]]), rtol=0.0, atol=0.0)

# Two-state HMM reference for observations [0, 0, 1, 1].
initial = np.array([0.5, 0.5])
transition = np.array([[0.9, 0.1], [0.1, 0.9]])
success = np.array([0.1, 0.9])
observations = [0, 0, 1, 1]
alpha = initial * np.where(observations[0] == 1, success, 1.0 - success)
for observation in observations[1:]:
    emission = success if observation == 1 else 1.0 - success
    alpha = (alpha @ transition) * emission
hmm_log_probability = math.log(float(alpha.sum()))
np.testing.assert_allclose(hmm_log_probability, -3.2389764965752033, rtol=2e-15)

# At latent z=(0,0), Gaussian-copula log density is -0.5 log(det R).
correlation = np.array([[1.0, 0.5], [0.5, 1.0]])
copula_center = -0.5 * np.linalg.slogdet(correlation)[1]
np.testing.assert_allclose(copula_center, 0.14384103622589045, rtol=2e-15)

# Dense row-generator CTMC reference.  This deliberately uses a spectral
# matrix exponential rather than the Core uniformization recurrence.
generator = np.array(
    [[-3.0, 1.0, 2.0], [0.5, -1.0, 0.5], [0.25, 0.75, -1.0]]
)
eigenvalues, eigenvectors = np.linalg.eig(generator)
transition = (
    eigenvectors
    @ np.diag(np.exp(0.8 * eigenvalues))
    @ np.linalg.inv(eigenvectors)
).real
ctmc_probabilities = np.array([0.2, 0.3, 0.5]) @ transition
np.testing.assert_allclose(
    ctmc_probabilities,
    np.array(
        [0.11374376590160953, 0.41089706875887866, 0.47535916533951184]
    ),
    rtol=2e-15,
    atol=2e-15,
)
np.testing.assert_allclose(transition.sum(axis=1), np.ones(3), atol=2e-15)

print(f"PROBABILITY_NUMPY_REFERENCE_OK numpy={np.__version__}")
