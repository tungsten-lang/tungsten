#!/usr/bin/env python3
"""Minimal OpenSim 4.x (.osim) kinematics + muscle-path-length engine (numpy only).

Scope (what this engine implements, and what it approximates -- see also moment_arms.py header):
  * bodies / PhysicalOffsetFrames / CustomJoint (SpatialTransform: LinearFunction, Constant,
    SimmSpline = natural cubic spline, PolynomialFunction) / PinJoint / WeldJoint
  * CoordinateCouplerConstraint (dependent coordinate = scale * f(independent))  -> patella coupling
  * PathPoint, ConditionalPathPoint (active iff range[0] <= q <= range[1]), MovingPathPoint
  * WrapCylinder with the OpenSim wrapLine decision logic (quadrant / mandatory / potential wrap,
    tangent-point selection, apex-plane axial slide, spiral length) ported from
    opensim-core WrapCylinder.cpp, GeometryPath::applyWrapObjects (path ranges, 'best' wrap segment,
    multi-wrap iteration)
  NOT implemented: WrapSphere/Ellipsoid/Torus (none used by gait2392 or Rajagopal2016),
  the _adjust_tangent_point tangency iteration used by OpenSim only when a path has >1 PathWrap,
  and the cylinder 'length' beyond the both-tangent-points-outside test.
"""
import math
import xml.etree.ElementTree as ET
import numpy as np

DEG = math.pi / 180.0
NOWRAP, INSIDE, WRAPPED, MANDATORY = 0, -1, 1, 2


def floats(s):
    return [float(t) for t in s.split()]


# --------------------------------------------------------------------------------------- functions
class Spline:
    """Natural cubic spline (SimmSpline in OpenSim 4 = interpolating natural cubic spline);
    linear extrapolation with the end slopes outside the knot range."""

    def __init__(self, x, y):
        x = np.array(x, float)
        y = np.array(y, float)
        n = len(x)
        h = np.diff(x)
        if n == 2:
            M = np.zeros(2)
        else:
            A = np.zeros((n, n))
            r = np.zeros(n)
            A[0, 0] = 1.0
            A[-1, -1] = 1.0
            for i in range(1, n - 1):
                A[i, i - 1] = h[i - 1]
                A[i, i] = 2 * (h[i - 1] + h[i])
                A[i, i + 1] = h[i]
                r[i] = 6 * ((y[i + 1] - y[i]) / h[i] - (y[i] - y[i - 1]) / h[i - 1])
            M = np.linalg.solve(A, r)
        self.x, self.y, self.M, self.h = x, y, M, h

    def __call__(self, q):
        x, y, M, h = self.x, self.y, self.M, self.h
        if q <= x[0]:
            s = (y[1] - y[0]) / h[0] - h[0] * (2 * M[0] + M[1]) / 6.0
            return float(y[0] + s * (q - x[0]))
        if q >= x[-1]:
            s = (y[-1] - y[-2]) / h[-1] + h[-1] * (M[-2] + 2 * M[-1]) / 6.0
            return float(y[-1] + s * (q - x[-1]))
        i = int(np.searchsorted(x, q, side="right")) - 1
        i = min(max(i, 0), len(h) - 1)
        a = (x[i + 1] - q) / h[i]
        b = (q - x[i]) / h[i]
        return float(a * y[i] + b * y[i + 1] + ((a ** 3 - a) * M[i] + (b ** 3 - b) * M[i + 1]) * h[i] ** 2 / 6.0)


def parse_function(el):
    """el = the function element (SimmSpline / LinearFunction / Constant / PolynomialFunction /
    MultiplierFunction). Returns a python callable f(q)."""
    tag = el.tag
    if tag == "SimmSpline":
        return Spline(floats(el.find("x").text), floats(el.find("y").text))
    if tag == "LinearFunction":
        c = floats(el.find("coefficients").text)
        return lambda q, c=c: c[0] * q + c[1]
    if tag == "Constant":
        v = float(el.find("value").text)
        return lambda q, v=v: v
    if tag == "PolynomialFunction":
        c = floats(el.find("coefficients").text)
        return lambda q, c=c: float(np.polyval(c, q))
    if tag == "MultiplierFunction":
        inner = None
        for ch in el:
            if ch.tag not in ("scale",):
                inner = parse_function(ch) if ch.tag in ("SimmSpline", "LinearFunction", "Constant",
                                                          "PolynomialFunction", "MultiplierFunction") else inner
        sc = float(el.find("scale").text)
        return lambda q, f=inner, s=sc: s * f(q)
    raise ValueError("unsupported function type " + tag)


def find_function(parent):
    for ch in parent:
        if ch.tag in ("SimmSpline", "LinearFunction", "Constant", "PolynomialFunction", "MultiplierFunction"):
            return parse_function(ch)
    raise ValueError("no function under " + parent.tag)


# --------------------------------------------------------------------------------------- transforms
def rx(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]], float)


def ry(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]], float)


def rz(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]], float)


def axis_angle(axis, ang):
    a = np.array(axis, float)
    n = np.linalg.norm(a)
    if n == 0:
        return np.eye(3)
    a = a / n
    K = np.array([[0, -a[2], a[1]], [a[2], 0, -a[0]], [-a[1], a[0], 0]])
    return np.eye(3) + math.sin(ang) * K + (1 - math.cos(ang)) * (K @ K)


def body_fixed_xyz(v):
    """SimTK::Rotation::setRotationToBodyFixedXYZ: R = Rx(a) Ry(b) Rz(c)."""
    return rx(v[0]) @ ry(v[1]) @ rz(v[2])


def T_of(R, p):
    T = np.eye(4)
    T[:3, :3] = R
    T[:3, 3] = p
    return T


def T_inv(T):
    R = T[:3, :3]
    p = T[:3, 3]
    return T_of(R.T, -R.T @ p)


def txt(el, tag, default=None):
    e = el.find(tag)
    return e.text.strip() if e is not None and e.text else default


def last(path):
    return path.strip().split("/")[-1]


# --------------------------------------------------------------------------------------- cylinder wrap
def _S(x):
    return -1 if x < 0.0 else 1  # DSIGN


def _unit(v):
    n = np.linalg.norm(v)
    return (v / n if n > 0 else v * 0.0), n


def _closest_on_line(pt, line_pt, line_dir):
    """WrapMath::GetClosestPointOnLineToPoint(pt, linePt, line(direction), closest, t)"""
    v1 = pt - line_pt
    v1u, mag = _unit(v1)
    v2u, mag2 = _unit(np.array(line_dir, float))
    t = float(v1u @ v2u) * mag
    return line_pt + t * v2u


def _intersect_lines(p1, p2, p3, p4):
    vec1, mag1 = _unit(p2 - p1)
    vec2, mag2 = _unit(p4 - p3)
    cp = np.cross(vec1, vec2)
    denom = float(cp @ cp)
    if abs(denom) < 1e-7:
        nan = np.full(3, np.nan)
        return nan, float("nan"), nan, float("nan")
    m1 = np.array([p3 - p1, vec1, cp])
    t = np.linalg.det(m1) / denom
    pint2 = p3 + t * vec2
    m2 = np.array([p3 - p1, vec2, cp])
    s = np.linalg.det(m2) / denom
    pint1 = p1 + s * vec1
    return pint1, s / mag1, pint2, t / mag2


def _seg_plane(pt1, pt2, n, d):
    vec = pt2 - pt1
    dp = float(vec @ n)
    if abs(dp) < 1e-6:
        return None
    t = (-d - float(n @ pt1)) / dp
    if t < -1e-6 or t > 1.0 + 1e-6:
        return None
    return pt1 + t * vec


def cylinder_wrapline(P1, P2, R, L, axis, sign, debug=False):
    """Port of WrapCylinder::wrapLine (single-wrap branch, i.e. without _adjust_tangent_point).
    P1, P2 in the wrap-object frame (cylinder axis = +z, centred on z=0).
    Returns (code, r1, r2, wrap_path_length, info)."""
    dn = np.array([0.0, 0.0, 1.0])
    r_sq = R * R
    if P1[0] ** 2 + P1[1] ** 2 < r_sq or P2[0] ** 2 + P2[1] ** 2 < r_sq:
        return INSIDE, None, None, 0.0, "inside"
    cyl_start = np.array([0.0, 0.0, -0.5 * L])
    cyl_end = np.array([0.0, 0.0, 0.5 * L])
    near12, t12, near00, t00 = _intersect_lines(P1, P2, cyl_start, cyl_end)
    d2 = float((near12 - near00) @ (near12 - near00)) if not np.isnan(t12) else float("nan")
    mand = (d2 < r_sq) and (0.0 < t12 < 1.0)
    constrained = sign != 0
    code = WRAPPED
    if not constrained:
        if mand:
            code = MANDATORY
        else:
            return NOWRAP, None, None, 0.0, "unconstrained-miss"

    p11 = np.array([0.0, 0.0, P1[2]])
    p22 = np.array([0.0, 0.0, P2[2]])
    vv, p11_dist = _unit(P1 - p11)
    sin_theta = R / p11_dist
    dist = R * sin_theta
    pp = p11 + dist * vv
    dist = math.sqrt(r_sq - dist * dist)
    uu = np.cross(dn, vv)
    r1a = pp + dist * uu
    r1b = pp - dist * uu
    vv, p22_dist = _unit(P2 - p22)
    sin_theta = R / p22_dist
    dist = R * sin_theta
    pp = p22 + dist * vv
    dist = math.sqrt(r_sq - dist * dist)
    uu = np.cross(dn, vv)
    r2a = pp + dist * uu
    r2b = pp - dist * uu

    far_side_wrap = False
    long_wrap = False
    if constrained:
        if _S(P1[axis]) == sign or _S(P2[axis]) == sign:
            if mand:
                code = MANDATORY
            else:
                nsign = _S(near12[axis]) if not np.isnan(near12[axis]) else 1
                if _S(P1[axis]) != _S(P2[axis]) and nsign != sign:
                    code = WRAPPED
                else:
                    return NOWRAP, None, None, 0.0, "constrained-noWrap"
        r1am, r1bm, r2am, r2bm = r1a - p11, r1b - p11, r2a - p22, r2b - p22

        def _acos(a, b):
            c = float(a @ b) / (np.linalg.norm(a) * np.linalg.norm(b))
            return math.acos(max(-1.0, min(1.0, c)))

        alpha = _acos(r1am, r2bm)
        beta = _acos(r1bm, r2am)
        s1a, s1b, s2a, s2b = (_S(r1a[axis]) == sign, _S(r1b[axis]) == sign,
                              _S(r2a[axis]) == sign, _S(r2b[axis]) == sign)
        if s1a and s1b:
            if s2a:
                r1, r2 = r1b, r2a
                far_side_wrap = not (alpha > beta)
            else:
                r1, r2 = r1a, r2b
                far_side_wrap = (alpha > beta)
        elif s1a and not s1b:
            r1, r2 = r1a, r2b
            far_side_wrap = (alpha > beta)
        elif (not s1a) and s1b:
            r1, r2 = r1b, r2a
            far_side_wrap = not (alpha > beta)
        else:
            if s2a:
                r1, r2 = r1b, r2a
                far_side_wrap = not (alpha > beta)
            elif s2b:
                r1, r2 = r1a, r2b
                far_side_wrap = (alpha > beta)
            else:
                if alpha > beta:
                    r1, r2 = r1a, r2b
                else:
                    r1, r2 = r1b, r2a
                far_side_wrap = True
        sum_musc = (r1 - P1) + (r2 - P2)
        sum_r = (r1 - p11) + (r2 - p22)
        if float(sum_r @ sum_musc) < 0.0:
            long_wrap = True
    else:
        a1, b1, a2, b2 = [_unit(v)[0] for v in (r1a - p11, r1b - p11, r2a - p22, r2b - p22)]
        dots = [float(a1 @ a2), float(a1 @ b2), float(b1 @ a2), float(b1 @ b2)]
        if dots[0] > dots[1] and dots[0] > dots[2] and dots[0] > dots[3]:
            r1, r2 = r1a, r2a
        elif dots[1] > dots[2] and dots[1] > dots[3]:
            r1, r2 = r1a, r2b
        elif dots[2] > dots[3]:
            r1, r2 = r1b, r2a
        else:
            r1, r2 = r1b, r2b

    # apex / plane axial slide of the tangent points
    uu = r1 - p11
    vv = r2 - p22
    vv, _ = _unit(uu + vv)
    t = p11_dist / (p11_dist + p22_dist)
    mpt = P1 + t * (P2 - P1)
    axispt = np.array([0.0, 0.0, mpt[2]])
    l1, _ = _unit(P1 - axispt)
    l2, _ = _unit(P2 - axispt)
    plane_normal, _ = _unit(np.cross(l1, l2))
    vert1, _ = _unit(np.cross(dn, plane_normal))
    vert2, _ = _unit(np.cross(plane_normal, dn))
    apex1 = axispt + R * vert1
    apex2 = axispt + R * vert2
    dist1 = float((mpt - apex1) @ (mpt - apex1))
    dist2 = float((mpt - apex2) @ (mpt - apex2))
    if far_side_wrap:
        apex = apex2 if dist1 < dist2 else apex1
    else:
        apex = apex1 if dist1 < dist2 else apex2
    uu, _ = _unit(P1 - apex)
    vv, _ = _unit(P2 - apex)
    plane_normal, _ = _unit(np.cross(uu, vv))
    d = -float(P1 @ plane_normal)
    r1p = _seg_plane(r1 - 10.0 * dn, r1 + 10.0 * dn, plane_normal, d)
    r2p = _seg_plane(r2 - 10.0 * dn, r2 + 10.0 * dn, plane_normal, d)
    r1 = r1.copy()
    r2 = r2.copy()
    if r1p is not None:
        r1a_ = _closest_on_line(r1p, p11, p22)
        if float((r1a_ - p22) @ (r1a_ - p22)) < float((p11 - p22) @ (p11 - p22)):
            r1 = r1p
    if r2p is not None:
        r2a_ = _closest_on_line(r2p, p11, p22)
        if float((r2a_ - p11) @ (r2a_ - p11)) < float((p22 - p11) @ (p22 - p11)):
            r2 = r2p
    halfL = L / 2.0
    if (r1[2] < -halfL or r1[2] > halfL) and (r2[2] < -halfL or r2[2] > halfL):
        return NOWRAP, None, None, 0.0, "beyond-cylinder-length"

    # spiral path length (_make_spiral_path), using the unsigned arc for the long wrap
    r1ax = np.array([0.0, 0.0, r1[2]])
    r2ax = np.array([0.0, 0.0, r2[2]])
    axial = float((r2ax - r1ax) @ dn)
    u = r1 - r1ax
    v = r2 - r2ax
    theta = math.atan2(float(np.cross(u, v) @ dn), float(u @ v))
    th = abs(theta)
    if long_wrap:
        th = 2.0 * math.pi - th
    wl = math.sqrt((R * th) ** 2 + axial ** 2)
    info = dict(long=long_wrap, far=far_side_wrap, theta_deg=th / DEG, code=code)
    return code, r1, r2, wl, info


# --------------------------------------------------------------------------------------- model
class Model:
    def __init__(self, fn, root_body="pelvis"):
        self.fn = fn
        tree = ET.parse(fn).getroot()
        self.root_body = root_body
        self.coord_default = {}
        self.coord_range = {}
        self.coord_joint = {}
        self.joints = {}       # child body -> dict
        self.wraps = {}        # name -> dict
        self.couplers = {}     # dependent coord -> (func, [indep], scale)
        self.muscles = {}

        # wrap objects
        for body in tree.iter("Body"):
            bname = body.get("name")
            ws = body.find("WrapObjectSet")
            if ws is None:
                continue
            objs = ws.find("objects")
            if objs is None:
                continue
            for o in objs:
                if o.tag != "WrapCylinder":
                    self.wraps[o.get("name")] = dict(kind=o.tag, body=bname, unsupported=True)
                    continue
                rot = floats(txt(o, "xyz_body_rotation", "0 0 0"))
                tr = floats(txt(o, "translation", "0 0 0"))
                quad = txt(o, "quadrant", "all")
                axis, sign = {"-x": (0, -1), "x": (0, 1), "+x": (0, 1), "-y": (1, -1), "y": (1, 1), "+y": (1, 1),
                              "-z": (2, -1), "z": (2, 1), "+z": (2, 1)}.get(quad.lower(), (0, 0))
                self.wraps[o.get("name")] = dict(
                    kind="WrapCylinder", body=bname, T_BW=T_of(body_fixed_xyz(rot), tr),
                    radius=float(txt(o, "radius")), length=float(txt(o, "length")),
                    axis=axis, sign=sign, quadrant=quad, active=(txt(o, "active", "true") == "true"),
                    rot=rot, trans=tr)

        # joints
        for j in tree.iter():
            if not j.tag.endswith("Joint") or j.find("socket_parent_frame") is None:
                continue
            frames = {}
            fr = j.find("frames")
            if fr is not None:
                for f in fr:
                    frames[f.get("name")] = dict(
                        body=last(txt(f, "socket_parent")),
                        T=T_of(body_fixed_xyz(floats(txt(f, "orientation", "0 0 0"))), floats(txt(f, "translation", "0 0 0"))))
            pf = txt(j, "socket_parent_frame")
            cf = txt(j, "socket_child_frame")
            if pf not in frames or cf not in frames:
                # frame attached directly to a body
                for nm in (pf, cf):
                    if nm not in frames:
                        frames[nm] = dict(body=last(nm), T=np.eye(4))
            coords = []
            cs = j.find("coordinates")
            if cs is not None:
                for c in cs.findall("Coordinate"):
                    nm = c.get("name")
                    coords.append(nm)
                    self.coord_default[nm] = float(txt(c, "default_value", "0"))
                    self.coord_range[nm] = floats(txt(c, "range", "0 0"))
                    self.coord_joint[nm] = j.get("name")
            spat = []
            st = j.find("SpatialTransform")
            if st is not None:
                for ta in st.findall("TransformAxis"):
                    cn = (txt(ta, "coordinates", "") or "").split()
                    if txt(ta, "coordinates") is None:
                        cn = []
                    spat.append(dict(coords=cn, axis=floats(txt(ta, "axis")), fn=find_function(ta)))
            self.joints[frames[cf]["body"]] = dict(
                name=j.get("name"), type=j.tag, parent=frames[pf]["body"], child=frames[cf]["body"],
                T_PF=frames[pf]["T"], T_CM=frames[cf]["T"], coords=coords, spatial=spat)

        # couplers
        for c in tree.iter("CoordinateCouplerConstraint"):
            dep = txt(c, "dependent_coordinate_name")
            indep = txt(c, "independent_coordinate_names").split()
            fnode = c.find("coupled_coordinates_function")
            func = find_function(fnode)
            self.couplers[dep] = (func, indep, float(txt(c, "scale_factor", "1")))

        # muscles
        for el in tree.iter():
            if el.tag not in ("Thelen2003Muscle", "Millard2012EquilibriumMuscle", "Millard2012AccelerationMuscle"):
                continue
            gp = el.find("GeometryPath")
            pts = []
            for p in gp.find("PathPointSet").find("objects"):
                d = dict(name=p.get("name"), type=p.tag, body=last(txt(p, "socket_parent_frame")))
                if p.tag in ("PathPoint", "ConditionalPathPoint"):
                    d["loc"] = np.array(floats(txt(p, "location")))
                if p.tag == "ConditionalPathPoint":
                    d["coord"] = last(txt(p, "socket_coordinate"))
                    d["range"] = floats(txt(p, "range"))
                if p.tag == "MovingPathPoint":
                    d["cx"], d["cy"], d["cz"] = (last(txt(p, "socket_x_coordinate")), last(txt(p, "socket_y_coordinate")),
                                                  last(txt(p, "socket_z_coordinate")))
                    d["fx"] = find_function(p.find("x_location"))
                    d["fy"] = find_function(p.find("y_location"))
                    d["fz"] = find_function(p.find("z_location"))
                pts.append(d)
            pw = []
            pws = gp.find("PathWrapSet")
            if pws is not None and pws.find("objects") is not None:
                for w in pws.find("objects"):
                    rng = floats(txt(w, "range", "-1 -1"))
                    pw.append(dict(wrap=txt(w, "wrap_object"), start=int(rng[0]), end=int(rng[1])))
            g = lambda t: float(txt(el, t))
            self.muscles[el.get("name")] = dict(
                name=el.get("name"), type=el.tag, F=g("max_isometric_force"), lopt=g("optimal_fiber_length"),
                lts=g("tendon_slack_length"), pen=g("pennation_angle_at_optimal"), points=pts, wraps=pw)

    # ---- kinematics
    def coords(self, q=None):
        c = dict(self.coord_default)
        if q:
            c.update(q)
        for dep, (func, indep, scale) in self.couplers.items():
            if dep in c and not (q and dep in q):
                c[dep] = scale * func(c[indep[0]])
        return c

    def body_T(self, c):
        """4x4 transform of every body frame expressed in the root (pelvis) frame."""
        T = {self.root_body: np.eye(4)}
        changed = True
        while changed:
            changed = False
            for child, j in self.joints.items():
                if child in T or j["parent"] not in T:
                    continue
                R = np.eye(3)
                p = np.zeros(3)
                if j["type"] == "PinJoint":
                    R = rz(c[j["coords"][0]])
                elif j["spatial"]:
                    sp = j["spatial"]
                    for k in range(3):
                        ang = sp[k]["fn"](c[sp[k]["coords"][0]]) if sp[k]["coords"] else sp[k]["fn"](0.0)
                        R = R @ axis_angle(sp[k]["axis"], ang)
                    for k in range(3, 6):
                        val = sp[k]["fn"](c[sp[k]["coords"][0]]) if sp[k]["coords"] else sp[k]["fn"](0.0)
                        p = p + val * np.array(sp[k]["axis"])
                T[child] = T[j["parent"]] @ j["T_PF"] @ T_of(R, p) @ T_inv(j["T_CM"])
                changed = True
        return T

    # ---- path
    def path_nodes(self, m, c, T):
        nodes = []
        for i, p in enumerate(m["points"]):
            if p["type"] == "ConditionalPathPoint":
                v = c[p["coord"]]
                if not (p["range"][0] <= v <= p["range"][1]):
                    continue
            if p["type"] == "MovingPathPoint":
                loc = np.array([p["fx"](c[p["cx"]]), p["fy"](c[p["cy"]]), p["fz"](c[p["cz"]])])
            else:
                loc = p["loc"]
            pos = (T[p["body"]] @ np.append(loc, 1.0))[:3]
            nodes.append(dict(pos=pos, orig=i, wo=None, wl=0.0, ws=None))
        return nodes

    def _wrap_segment(self, n1, n2, w, T):
        Tw = T[w["body"]] @ w["T_BW"]
        Ti = T_inv(Tw)
        P1 = (Ti @ np.append(n1["pos"], 1.0))[:3]
        P2 = (Ti @ np.append(n2["pos"], 1.0))[:3]
        code, r1, r2, wl, info = cylinder_wrapline(P1, P2, w["radius"], w["length"], w["axis"], w["sign"])
        if code <= 0 or r1 is None:
            return NOWRAP, None
        r1w = (Tw @ np.append(r1, 1.0))[:3]
        r2w = (Tw @ np.append(r2, 1.0))[:3]
        change = (np.linalg.norm(n1["pos"] - r1w) + wl + np.linalg.norm(r2w - n2["pos"])) - np.linalg.norm(n1["pos"] - n2["pos"])
        return code, dict(r1=r1w, r2=r2w, wl=wl, change=change, info=info)

    @staticmethod
    def _length(path):
        L = 0.0
        for a, b in zip(path[:-1], path[1:]):
            if a["wo"] is not None and a["wo"] == b["wo"] and a["ws"] == b["ws"] and b.get("is_w2"):
                L += b["wl"]
            else:
                L += float(np.linalg.norm(a["pos"] - b["pos"]))
        return L

    def length(self, mname, q=None, want_info=False):
        m = self.muscles[mname]
        c = self.coords(q)
        T = self.body_T(c)
        path = self.path_nodes(m, c, T)
        wraps = m["wraps"]
        infos = []
        if wraps:
            nws = len(wraps)
            maxit = 1 if nws < 2 else 8
            last_len = float("inf")
            for kk in range(maxit):
                for i, ws in enumerate(wraps):
                    path = [p for p in path if p["ws"] != i]
                    w = self.wraps[ws["wrap"]]
                    if w.get("unsupported"):
                        raise NotImplementedError("wrap type " + w["kind"])
                    if not w["active"]:
                        continue
                    n_pts = len(m["points"])
                    wstart = 0 if ws["start"] < 1 else ws["start"] - 1
                    wend = n_pts - 1 if ws["end"] < 1 else ws["end"] - 1
                    idxs = [k for k, p in enumerate(path) if p["orig"] is not None and wstart <= p["orig"] <= wend]
                    if not idxs:
                        continue
                    start, end = idxs[0], idxs[-1]
                    best = None
                    best_pair = None
                    min_change = float("inf")
                    for k1 in range(start, end):
                        k2 = k1 + 1
                        a, b = path[k1], path[k2]
                        if a["wo"] is None or b["wo"] is None or a["wo"] != b["wo"]:
                            code, res = self._wrap_segment(a, b, w, T)
                            if code == MANDATORY:
                                best, best_pair = res, (k1, k2)
                                break
                            elif code == WRAPPED:
                                if res["change"] < min_change:
                                    best, best_pair, min_change = res, (k1, k2), res["change"]
                    if best is not None:
                        k1, k2 = best_pair
                        w1 = dict(pos=best["r1"], orig=None, wo=ws["wrap"], wl=0.0, ws=i)
                        w2 = dict(pos=best["r2"], orig=None, wo=ws["wrap"], wl=best["wl"], ws=i, is_w2=True)
                        path = path[:k2] + [w1, w2] + path[k2:]
                        infos.append(dict(wrap=ws["wrap"], info=best["info"]))
                Lnow = self._length(path)
                if abs(Lnow - last_len) < 0.0005:
                    break
                last_len = Lnow
        L = self._length(path)
        if want_info:
            return L, infos, path
        return L
