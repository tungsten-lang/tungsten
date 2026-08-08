#!/usr/bin/env python3
"""Independent standard-library references for paper-derived Statistics.

Run directly with `python3 spec/core/statistics_paper_reference.py`.  These pin
arithmetic and rank conventions; they are not coverage simulations or proofs.
"""

from __future__ import annotations

import math
import statistics


def check_close(name: str, actual: float, expected: float, tol: float = 1e-12) -> None:
    if not math.isclose(actual, expected, rel_tol=tol, abs_tol=tol):
        raise AssertionError(f"{name}: expected {expected}, got {actual}")
    print(f"PASS reference.{name}")


def all_purpose_mean(values: list[float], delta: float) -> tuple[float, float]:
    groups = math.ceil(-math.log(delta))
    group_means: list[float] = []
    for group in range(groups):
        start = math.floor(group * len(values) / groups)
        stop = math.floor((group + 1) * len(values) / groups)
        group_means.append(math.fsum(values[start:stop]) / (stop - start))
    initial = statistics.median(group_means)
    deviations = [value - initial for value in values]
    scale = max(abs(value) for value in deviations)
    ratios = [abs(value) / scale for value in deviations]
    target = -math.log(delta) / 3.0

    def equation(beta: float) -> float:
        return math.fsum(min(beta * ratio * ratio, 1.0) for ratio in ratios)

    lower, upper = 0.0, 1.0
    while equation(upper) < target:
        upper *= 2.0
    for _ in range(100):
        middle = (lower + upper) / 2.0
        if equation(middle) < target:
            lower = middle
        else:
            upper = middle
    beta = (lower + upper) / 2.0
    estimate = initial + math.fsum(
        deviation * (1.0 - min(beta * ratio * ratio, 1.0))
        for deviation, ratio in zip(deviations, ratios, strict=True)
    ) / len(values)
    return estimate, beta


def half_mass_candidate(
    sample: list[tuple[float, ...]], candidate: tuple[float, ...]
) -> tuple[float, float]:
    points = [*sample, candidate]
    rank = math.floor(len(sample) / 2) + 1
    scores: list[float] = []
    for index, point in enumerate(points):
        distances = sorted(
            math.dist(point, other)
            for other_index, other in enumerate(points)
            if other_index != index
        )
        scores.append(distances[rank - 1])
    candidate_score = scores[-1]
    return candidate_score, sum(score >= candidate_score for score in scores) / len(scores)


def empirical_bernstein_alternating(
    count: int, alpha: float = 0.05, kappa: float = 0.25
) -> tuple[int, float, float]:
    kappa_z = kappa * math.erf(1.0 / (kappa * math.sqrt(2.0)))
    log_boundary = math.log(kappa_z) + 0.5 * math.log(2.0 * math.pi) - math.log(alpha)
    total = 0.0
    variance = 0.0
    active_from: int | None = None
    for time in range(1, count + 1):
        value = float((time - 1) % 2)
        predictor = (0.5 + total) / time
        deviation = abs(value - predictor)
        variance += -math.log1p(-deviation) - deviation
        total += value
        u_value = 1.0 / (2.0 * kappa * kappa) + variance
        quarter = u_value / 4.0
        log_left = (
            0.5 * (math.log(math.pi) - math.log(u_value))
            + quarter
            + math.log1p(-0.5 * math.exp(-quarter))
        )
        if active_from is None and log_left >= log_boundary:
            active_from = time
    assert active_from is not None
    u_value = 1.0 / (2.0 * kappa * kappa) + variance
    denominator = -math.expm1(-u_value / 4.0)
    ell = math.log(kappa_z / alpha) - math.log(denominator)
    width = 2.0 / count * math.sqrt(
        u_value * (ell + 0.5 * math.log(2.0 * u_value))
    )
    return active_from, variance, width


contaminated = [float(value) for value in range(11)] + [100.0]
estimate, beta = all_purpose_mean(contaminated, 0.05)
check_close("robust_mean.estimate", estimate, 5.1524479066495275)
check_close("robust_mean.scaled_influence", beta, 0.9861269540309456)

replicates = [9.0, 11.0, 10.5, 9.5]
deviation = math.sqrt(math.fsum((value - 10.0) ** 2 for value in replicates) / 4)
check_close("cheap_subsampling.deviation", deviation, 0.7905694150420949)
critical_t4 = 2.7764451051977987
check_close("cheap_subsampling.lower", 10.0 - critical_t4 * deviation, 7.805027417287288)
check_close("cheap_subsampling.upper", 10.0 + critical_t4 * deviation, 12.194972582712712)

score, p_value = half_mass_candidate([(0.0,), (1.0,), (2.0,)], (10.0,))
check_close("half_mass.score", score, 9.0)
check_close("half_mass.p_value", p_value, 0.25)

active_from, variance, width = empirical_bernstein_alternating(200)
if active_from != 21:
    raise AssertionError(f"empirical_bernstein.active_from: expected 21, got {active_from}")
print("PASS reference.empirical_bernstein.active_from")
check_close("empirical_bernstein.variance", variance, 40.208791763289696)
check_close("empirical_bernstein.width", width, 0.13700794243779177)

threshold = math.sqrt(math.log(20.0) / 6.0)
check_close("relative_fit.threshold", threshold, 0.7066036458008114)

print("statistics_paper_reference: all checks passed")
