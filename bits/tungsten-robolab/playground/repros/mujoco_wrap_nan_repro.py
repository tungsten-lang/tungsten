"""Minimal pure-MuJoCo reproduction: a spatial tendon that grazes a wrapping cylinder gets a NaN length.

No MyoSuite, no controller: one static cylinder, three sites, one tendon [p0, cylinder, p1] with a sidesite, the geometry of MyoSuite's
recfem_r_tendon / KnExt_at_fem_r_wrap (radius 0.025 m, p0 0.44 m up the thigh, p1 at the patella, the sidesite on the +x side), reduced to the
2D plane in which mju_wrap works. p1.x is swept through the tangent of the tendon line to the cylinder in steps of 1e-13 m; every point calls
mj_kinematics + mj_tendon and reports ten_length. Where the line cuts the cylinder by less than ~1e-9 m the two tangent points are < ~2e-8 rad
apart, dot(p0n, p1n) in length_circle (engine_util_misc.c) rounds above 1.0, acos() returns NaN, and mju_wrap's `wlen < 0` test lets it through.

usage: python mujoco_wrap_nan_repro.py [cylinder|sphere]   (the sphere uses the same wrap_circle/length_circle after projecting to its 2D plane)

Expected output (identical on mujoco 3.2.7, 3.3.0, 3.6.0 and 3.14.0 wheels, macOS arm64): 859 NaN of 8001 points for the cylinder, 651 for the sphere,
all on the wrapping side of the tangent (or at it), none where the line misses the geom. Report: mujoco_wrap_nan.md in this directory.
One-line fix (src/engine/engine_util_misc.c, length_circle): `mjtNum angle = mju_acos(mju_clip(mju_dot(p0n, p1n, 2), -1, 1));`
"""
import math
import sys

import numpy as np
import mujoco

kind = sys.argv[1] if len(sys.argv) > 1 else "cylinder"
geom = ('<geom name="wrap" type="cylinder" size="0.025 0.05" contype="0" conaffinity="0"/>' if kind == "cylinder" else
        '<geom name="wrap" type="sphere" size="0.025" contype="0" conaffinity="0"/>')
xml = f"""
<mujoco>
  <worldbody>
    <body name="b">
      {geom}
      <site name="p0" pos="0.0205 0.4443 0.0"/>
      <site name="p1" pos="0.0254 -0.0362 0.0"/>
      <site name="side" pos="0.03 -0.015 0.0"/>
    </body>
  </worldbody>
  <tendon>
    <spatial name="t">
      <site site="p0"/>
      <geom geom="wrap" sidesite="side"/>
      <site site="p1"/>
    </spatial>
  </tendon>
</mujoco>
"""
m = mujoco.MjModel.from_xml_string(xml)
d = mujoco.MjData(m)
p1 = m.site("p1").id
p0 = m.site_pos[m.site("p0").id].copy()
y1 = float(m.site_pos[p1][1])
r = 0.025


def line_distance(x):
    """distance from the cylinder axis to the line p0 -> (x, y1) in the xy plane (exact, Python floats)"""
    dx, dy = x - p0[0], y1 - p0[1]
    return abs(p0[0] * dy - p0[1] * dx) / math.hypot(dx, dy)


# the tangent: p1.x with line_distance == r (bisection in Python floats; the line cuts the circle for smaller x)
lo, hi = 0.0240, 0.0260
for _ in range(200):
    mid = 0.5 * (lo + hi)
    if line_distance(mid) < r:
        lo = mid
    else:
        hi = mid
xt = 0.5 * (lo + hi)
print(f"mujoco {mujoco.__version__} ({kind}): the tendon line touches the cylinder at p1.x = {xt!r} (distance to axis {line_distance(xt)!r} vs r {r})")

STEP = 1e-13
nan_k, fin_wrap, fin_nowrap = [], 0, 0
for k in range(-4000, 4001):
    m.site_pos[p1][0] = xt - k * STEP  # k > 0: the line cuts the circle by ~k * 1e-13 m (wrapping side)
    mujoco.mj_kinematics(m, d)
    mujoco.mj_tendon(m, d)
    L = d.ten_length[0]
    if not np.isfinite(L):
        nan_k.append(k)
    elif k > 0:
        fin_wrap += 1
    else:
        fin_nowrap += 1
print(f"{8001} points (p1.x step {STEP:g} m across the tangent): NaN {len(nan_k)}, finite on the wrapping side {fin_wrap}, finite on the non-wrapping side {fin_nowrap}")
print(f"NaN offsets k (k > 0: wrapping side; the cut depth is ~k*{STEP:g} m):", nan_k[:30], "..." if len(nan_k) > 30 else "")
if nan_k:
    k = nan_k[0]
    m.site_pos[p1][0] = xt - k * STEP
    mujoco.mj_kinematics(m, d)
    mujoco.mj_tendon(m, d)
    print("example k = %d: ten_length = %r, tendon Jacobian finite: %s, wrap points: %s" %
          (k, d.ten_length[0], bool(np.isfinite(d.ten_J).all()), np.round(d.wrap_xpos.ravel()[:9], 4)))
    print("=> a tendon whose line grazes a wrapping geom returns NaN (not 'no wrap') for a thin sliver of positions")
