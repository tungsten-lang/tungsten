"""Faithful Python port of MuJoCo 3.6.0's wrap_circle / length_circle (engine_util_misc.c) with the intermediate values exposed,
plus a Decimal (60-digit) evaluation of the same formulas, to show where the NaN of a cylinder-wrapped tendon comes from.

    python wrapdiag.py DIR [n_substeps]     # replays capture DIR's failing control step n substeps and analyses tendon 239's wrap
"""
import math
import sys
from decimal import Decimal, getcontext

import numpy as np

MINVAL = 1e-15  # mjMINVAL


def mu_normalize(v):
    n = math.sqrt(sum(x * x for x in v))
    if n < MINVAL:
        return [1.0] + [0.0] * (len(v) - 1), n
    s = 1.0 / n
    return [x * s for x in v], n


def is_intersect(p1, p2, p3, p4):
    det = (p4[1] - p3[1]) * (p2[0] - p1[0]) - (p4[0] - p3[0]) * (p2[1] - p1[1])
    if abs(det) < MINVAL:
        return 0
    a = ((p4[0] - p3[0]) * (p1[1] - p3[1]) - (p4[1] - p3[1]) * (p1[0] - p3[0])) / det
    b = ((p2[0] - p1[0]) * (p1[1] - p3[1]) - (p2[1] - p1[1]) * (p1[0] - p3[0])) / det
    return 1 if (a >= 0 and a <= 1 and b >= 0 and b <= 1) else 0


def length_circle(p0, p1, ind, radius, info=None):
    p0n, _ = mu_normalize([p0[0], p0[1]])
    p1n, _ = mu_normalize([p1[0], p1[1]])
    dot = p0n[0] * p1n[0] + p0n[1] * p1n[1]
    if info is not None:
        info["dot"] = dot
    try:
        angle = math.acos(dot)
    except ValueError:
        angle = float("nan")  # C acos(x>1) = NaN
    cross = p0[1] * p1[0] - p0[0] * p1[1]
    if (cross > 0 and ind) or (cross < 0 and not ind):
        angle = 2 * math.pi - angle
    return radius * angle


def wrap_circle(end, side, radius):
    """returns (wlen or -1, info dict)"""
    info = {}
    sqlen0 = end[0] * end[0] + end[1] * end[1]
    sqlen1 = end[2] * end[2] + end[3] * end[3]
    sqrad = radius * radius
    info.update(sqlen0=sqlen0, sqlen1=sqlen1, sqrad=sqrad)
    if sqlen0 < sqrad or sqlen1 < sqrad or radius < MINVAL:
        info["exit"] = "endpoint inside circle"
        return -1, info
    dif = [end[2] - end[0], end[3] - end[1]]
    dd = dif[0] * dif[0] + dif[1] * dif[1]
    if dd < MINVAL:
        info["exit"] = "points too close"
        return -1, info
    a = -(dif[0] * end[0] + dif[1] * end[1]) / dd
    a = 0.0 if a < 0 else (1.0 if a > 1 else a)
    tmp = [a * dif[0] + end[0], a * dif[1] + end[1]]
    info.update(a=a, tmp=tmp, tmp2=tmp[0] * tmp[0] + tmp[1] * tmp[1], sidedot=(None if side is None else side[0] * tmp[0] + side[1] * tmp[1]))
    if tmp[0] * tmp[0] + tmp[1] * tmp[1] > sqrad and (side is None or side[0] * tmp[0] + side[1] * tmp[1] >= 0):
        info["exit"] = "line misses circle (or wrong side): no wrap"
        return -1, info
    sqrt0 = math.sqrt(sqlen0 - sqrad)
    sqrt1 = math.sqrt(sqlen1 - sqrad)
    sol = [[[0, 0], [0, 0]], [[0, 0], [0, 0]]]
    good = [0.0, 0.0]
    for i in range(2):
        sgn = 1 if i == 0 else -1
        sol[i][0][0] = (end[0] * sqrad + sgn * radius * end[1] * sqrt0) / sqlen0
        sol[i][0][1] = (end[1] * sqrad - sgn * radius * end[0] * sqrt0) / sqlen0
        sol[i][1][0] = (end[2] * sqrad - sgn * radius * end[3] * sqrt1) / sqlen1
        sol[i][1][1] = (end[3] * sqrad + sgn * radius * end[2] * sqrt1) / sqlen1
        if side is not None:
            t = [sol[i][0][0] + sol[i][1][0], sol[i][0][1] + sol[i][1][1]]
            t, _ = mu_normalize(t)
            good[i] = t[0] * side[0] + t[1] * side[1]
        else:
            t = [sol[i][0][0] - sol[i][1][0], sol[i][0][1] - sol[i][1][1]]
            good[i] = -(t[0] * t[0] + t[1] * t[1])
        if is_intersect(end[0:2], sol[i][0], end[2:4], sol[i][1]):
            good[i] = -10000
    i = 0 if good[0] > good[1] else 1
    pnt = [sol[i][0][0], sol[i][0][1], sol[i][1][0], sol[i][1][1]]
    info.update(sol=sol, good=good, chosen=i, pnt=pnt)
    if is_intersect(end[0:2], pnt[0:2], end[2:4], pnt[2:4]):
        info["exit"] = "chosen solution intersects: no wrap"
        return -1, info
    linfo = {}
    wlen = length_circle(sol[i][0], sol[i][1], i, radius, linfo)
    info.update(linfo)
    info["exit"] = "wrap"
    return wlen, info


def decimal_circle(end, side, radius, prec=60):
    """the same formulas in 60-digit Decimal arithmetic: the TRUE value of dot(p0n, p1n) etc. for the given double inputs"""
    getcontext().prec = prec
    D = Decimal
    e = [D(x) for x in end]
    r = D(radius)
    sqlen0 = e[0] * e[0] + e[1] * e[1]
    sqlen1 = e[2] * e[2] + e[3] * e[3]
    sqrad = r * r
    dif = [e[2] - e[0], e[3] - e[1]]
    dd = dif[0] * dif[0] + dif[1] * dif[1]
    a = -(dif[0] * e[0] + dif[1] * e[1]) / dd
    a = min(max(a, D(0)), D(1))
    tmp = [a * dif[0] + e[0], a * dif[1] + e[1]]
    out = {"tmp2": tmp[0] * tmp[0] + tmp[1] * tmp[1], "sqrad": sqrad}
    sqrt0 = (sqlen0 - sqrad).sqrt()
    sqrt1 = (sqlen1 - sqrad).sqrt()
    for i in range(2):
        sgn = 1 if i == 0 else -1
        s00 = (e[0] * sqrad + sgn * r * e[1] * sqrt0) / sqlen0
        s01 = (e[1] * sqrad - sgn * r * e[0] * sqrt0) / sqlen0
        s10 = (e[2] * sqrad - sgn * r * e[3] * sqrt1) / sqlen1
        s11 = (e[3] * sqrad + sgn * r * e[2] * sqrt1) / sqlen1
        n0 = (s00 * s00 + s01 * s01).sqrt()
        n1 = (s10 * s10 + s11 * s11).sqrt()
        dot = (s00 * s10 + s01 * s11) / (n0 * n1)
        out[f"dot{i}"] = dot
        out[f"one_minus_dot{i}"] = 1 - dot
    return out


def analyse(d_end, side, radius):
    w, info = wrap_circle(d_end, side, radius)
    print("  wrap_circle:", info.get("exit"), "wlen", w)
    for k in ("sqlen0", "sqlen1", "sqrad", "a", "tmp", "tmp2", "sidedot", "chosen", "good", "pnt", "dot"):
        if k in info:
            print(f"    {k:8s} {info[k]!r}")
    if "dot" in info:
        print("    dot - 1 =", info["dot"] - 1.0, "(>0 means acos() returns NaN)")
    return w, info
