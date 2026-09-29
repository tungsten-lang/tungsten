"""Shared helpers for the round-10 serve-feature regressions (an51, an52, ...)."""
import numpy as np


def cross(p, v, xh):
    """[t, y, z, vx, vy, vz] where the ball crosses the plane x = xh after its table bounce (the skill's model)."""
    px, py, pz = p
    vx, vy, vz = v
    disc = vz * vz + 2 * 9.81 * (pz - 0.805)
    tb = (vz + np.sqrt(disc)) / 9.81
    px += vx * tb
    py += vy * tb
    vz = -(vz - 9.81 * tb) * 0.99
    vx *= 0.996
    vy *= 0.996
    pz = 0.805
    th = (xh - px) / vx
    return th + tb, py + vy * th, pz + vz * th - 4.905 * th * th, vx, vy, vz - 9.81 * th


def features(r, xh=1.8):
    s = r["serve"]
    t, y, z, vx, vy, vz = cross(s[:3], s[3:], xh)
    return [1.0, t - 0.54, y, z - 1.27, vx - 5, vy, vz + 2.0]


def cv(X, y, k=5, lam=1e-2, reps=3):
    n = len(y)
    best = np.zeros(n)
    for rep in range(reps):
        idx = np.arange(n)
        np.random.default_rng(rep).shuffle(idx)
        pred = np.zeros(n)
        for f in range(k):
            te = idx[f::k]
            tr = np.setdiff1d(idx, te)
            A = X[tr]
            w = np.linalg.solve(A.T @ A + lam * np.eye(A.shape[1]), A.T @ y[tr])
            pred[te] = X[te] @ w
        best += pred / reps
    return best


def quad(X):
    F = X[:, 1:]
    cols = [X]
    n = F.shape[1]
    for i in range(n):
        for j in range(i, n):
            cols.append((F[:, i] * F[:, j])[:, None])
    return np.hstack(cols)
