"""convkf: the convolutional keyframe policy (P6 in SEARCH.md).

A keyframe movement is a linear convolutional decoder: the commanded
contraction u(t) = sum_i B0(t - t_i) c_i + B1(t - t_i) cdot_i + B2(t - t_i) cddot_i,
a sparse train of knot impulses (contraction, velocity and acceleration
vectors) through a transposed 1-D convolution whose kernel is the quintic
Hermite basis (Chunk#knot, easing.w's Quintic). On top, a residual causal
TCN (lib/robolab/tcn.w, ConvPolicy) reads ~0.2 s of proprioception and adds
a correction to the command every tick; its last layer starts at zero, so the
untrained policy is exactly the hand-authored controller. This module is the
training side: the TCN's numpy mirror (bit-exact streaming form and a
vectorised form), the parity test against the Tungsten controller, and
antithetic OpenAI-ES and sep-CMA-ES over the knots and the TCN weights.

    convkf.py norm   --out params/search/convkf_tcn_norm.txt     # input normalisation (champion rollouts)
    convkf.py init   --norm params/search/convkf_tcn_norm.txt --out params/search/convkf_tcn_init.txt
    convkf.py parity [--controller bin/robolab_search_jump_convkf]
    convkf.py train  --arm knots --method es --budget 3200 --seed 1
    convkf.py validate out/search/p6/<run>/final.txt ... [--seeds 6101-6132]
    convkf.py analyse out/search/p6/<run>

Arms (what the search moves; everything else stays at the arena champion's
values it started from, START): `champ` (the champion's own 126 tunables),
`knots` (the 88 keyframe contractions plus 66 knot velocities and 66 knot
accelerations), `knots_tcn` (knots + every TCN weight), `tcn` (the TCN
weights alone). Rollouts: tasks/search_jump_convkf.py, strict (legal)
scoring, starts perturbed by 0.003 rad (pitch 0.0015), training seeds from
100000 (ES) and 200000 (sep-CMA), learning-curve probes on seeds 6001-6016,
validation 6101-6132; none of them is an arena seed.
"""

import argparse
import json
import math
import multiprocessing as mp
import os
import sys
import time

for _v in ("OPENBLAS_NUM_THREADS", "OMP_NUM_THREADS", "MKL_NUM_THREADS", "VECLIB_MAXIMUM_THREADS"):
    os.environ.setdefault(_v, "1")

import numpy as np  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

from bridge import Sim  # noqa: E402
from practice import load_task, read_params  # noqa: E402
import search  # noqa: E402

TASK = "search_jump_convkf"
OUT = os.path.join(ROOT, "out", "search", "p6")
ATTRS = {"noise": 0.003, "pitch_noise": 0.0015, "strict": True}
PROBE_SEEDS = list(range(6001, 6017))
VALID_SEEDS = list(range(6101, 6133))
KF_CHUNKS = ["crouch", "extend", "flight", "land"]
KNOT_CHUNKS = ["crouch", "extend", "flight"]
HIDDEN_SCALE = 10.0


# The arena champion P6 started from (search_jump_legal and
# search_jump_robust_legal, seeded 2026-09-27 09:22), pinned: the trials'
# champions have moved on since (to P6's own winner).
START = os.path.join(HERE, "arena", "params", "search_jump_legal-20260927-092234.txt")


def champion_params():
    return read_params(START)


def write_params(path, params, header=""):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w") as f:
        for line in header.splitlines():
            f.write(f"# {line}\n")
        for k in sorted(params):
            if not k.startswith("__"):
                f.write(f"{k} {float(params[k])!r}\n")


# ---------------------------------------------------------------------------
# the TCN: layout, bit-exact streaming mirror, vectorised mirror


class Arch:
    """ConvPolicy's architecture as its params declare it (the same keys and
    defaults as lib/robolab/tcn.w)."""

    def __init__(self, params, nin, nout):
        self.nin, self.nout = nin, nout
        self.hidden = int(params.get("tcn_hidden", 8.0))
        self.kernel = int(params.get("tcn_kernel", 3.0))
        self.layers = int(params.get("tcn_layers", 3.0))
        self.max = float(params.get("tcn_max", 0.3))
        self.dils = []
        dil = 2
        for l in range(self.layers):
            self.dils.append(int(params.get(f"tcn_dil{l + 1}", dil * 1.0)))
            dil *= 3
        self.shapes = []
        n = nin
        for d in self.dils:
            self.shapes.append((n, self.hidden, self.kernel, d))
            n = self.hidden
        self.shapes.append((self.hidden, nout, 1, 1))

    def count(self):
        return sum(o * i * k + o for i, o, k, _ in self.shapes)

    def window(self):
        return 1 + sum((k - 1) * d for _, _, k, d in self.shapes)

    def unpack(self, w):
        """Flat weights -> [(W[out, in, tap], b[out], dilation)]."""
        w = np.asarray(w, float)
        out, at = [], 0
        for i, o, k, d in self.shapes:
            W = w[at:at + o * i * k].reshape(o, i, k)
            at += o * i * k
            out.append((W, w[at:at + o], d))
            at += o
        return out

    def names(self):
        return [f"tcn_w{k}" for k in range(self.count())]


def init_weights(arch, seed=0):
    """Hidden layers N(0, 1 / fan_in) (fan_in = channels x taps), biases zero,
    the head zero: the untrained policy adds exactly nothing."""
    rng = np.random.default_rng(seed)
    parts = []
    for li, (i, o, k, _) in enumerate(arch.shapes):
        head = li == len(arch.shapes) - 1
        W = np.zeros((o, i, k)) if head else rng.normal(0.0, 1.0 / math.sqrt(i * k), (o, i, k))
        parts += [W.ravel(), np.zeros(o)]
    return np.concatenate(parts)


class Layout:
    """Where each input lives in a sensor frame (the S line), for one body."""

    def __init__(self, sim):
        n = sim.n
        self.n = n
        joints, pos = [], {}
        for i, mu in enumerate(sim.muscles):
            if mu.sign > 0 and mu.joint not in pos:
                pos[mu.joint] = i
                joints.append(mu.joint)
        self.joints = joints
        self.pos = [pos[j] for j in joints]
        at = 1 + 3 * n
        self.off = {}
        for name, vals in sim.sensor_blocks():
            self.off[name] = at
            at += len(vals)
        self.width = at
        self.nin = 2 * len(joints) + 7

    def features(self, v):
        """Raw (unnormalised) inputs from one frame's values, in ConvPolicy's order."""
        n, o = self.n, self.off
        x = [v[1 + p] for p in self.pos] + [v[1 + n + p] for p in self.pos]
        x += [v[o["l_foot_contact"]], v[o["r_foot_contact"]], v[o["com_pos"] + 2], v[o["com_vel"]],
              v[o["com_vel"] + 2], math.atan2(v[o["torso_up"]], v[o["torso_up"] + 2]), v[o["torso_angvel"] + 1]]
        return x


def wtanh(x):
    """Tungsten's Math.tanh (core/math.w: the sign-split exp form, not libm's
    tanh, which differs in the last bit on about half of all inputs)."""
    if x >= 0.0:
        d = math.exp(-2.0 * x)
        return (1.0 - d) / (1.0 + d)
    d = math.exp(2.0 * x)
    return (d - 1.0) / (d + 1.0)


class ExactTCN:
    """The streaming forward pass in the controller's exact order of float
    operations (Python floats, libm exp, Tungsten's tanh): it agrees bit for
    bit."""

    def __init__(self, params, nin, nout):
        self.arch = Arch(params, nin, nout)
        self.mu = [params.get(f"tcn_mu{i}", 0.0) for i in range(nin)]
        self.sd = [params.get(f"tcn_sd{i}", 1.0) for i in range(nin)]
        w = [params.get(f"tcn_w{k}", 0.0) for k in range(self.arch.count())]
        self.layers, at = [], 0
        for i, o, k, d in self.arch.shapes:
            W = w[at:at + o * i * k]
            at += o * i * k
            b = w[at:at + o]
            at += o
            self.layers.append({"nin": i, "nout": o, "k": k, "d": d, "w": W, "b": b,
                                "len": (k - 1) * d + 1, "hist": [0.0] * (((k - 1) * d + 1) * i), "pos": 0,
                                "primed": False})

    def normalise(self, x):
        return [(x[i] - self.mu[i]) / self.sd[i] for i in range(len(x))]

    @staticmethod
    def conv(L, x):
        nin, k, d, n = L["nin"], L["k"], L["d"], L["len"]
        h = L["hist"]
        if not L["primed"]:
            for s in range(n):
                for i in range(nin):
                    h[s * nin + i] = x[i]
            L["primed"] = True
        L["pos"] = (L["pos"] + 1) % n
        p = L["pos"]
        for i in range(nin):
            h[p * nin + i] = x[i]
        y = []
        w = L["w"]
        for o in range(L["nout"]):
            acc = L["b"][o]
            for i in range(nin):
                for j in range(k):
                    slot = (p - (k - 1 - j) * d + n) % n
                    acc = acc + w[(o * nin + i) * k + j] * h[slot * nin + i]
            y.append(acc)
        return y

    def step(self, x):
        h = [wtanh(z) for z in self.conv(self.layers[0], x)]
        for L in self.layers[1:-1]:
            z = self.conv(L, h)
            h = [h[i] + wtanh(z[i]) for i in range(len(h))]
        y = self.conv(self.layers[-1], h)
        m = self.arch.max
        return [m if v > m else (-m if v < -m else v) for v in y]


def forward_np(arch, w, X, mu=None, sd=None):
    """Vectorised forward over a whole recorded window: X (T x nin, raw
    inputs) -> offsets (T x nout) and the hidden activations. Same maths as
    the streaming form (history padded with the first input), numpy order of
    summation."""
    X = np.asarray(X, float)
    if mu is not None:
        X = (X - mu) / sd
    T = len(X)
    H, hidden = X, []
    layers = arch.unpack(w)
    for li, (W, b, d) in enumerate(layers):
        k = W.shape[2]
        pad = (k - 1) * d
        Hp = np.concatenate([np.repeat(H[:1], pad, axis=0), H], axis=0)
        Z = b + sum(Hp[j * d:j * d + T] @ W[:, :, j].T for j in range(k))
        if li == len(layers) - 1:
            return np.clip(Z, -arch.max, arch.max), hidden
        H = np.tanh(Z) if li == 0 else H + np.tanh(Z)
        hidden.append(H)


def tcn_params(params):
    """The tcn_* entries of a params dict."""
    return {k: v for k, v in params.items() if k.startswith("tcn")}


# ---------------------------------------------------------------------------
# recording rollouts (the S lines the controller received, its tcn tokens)


class _Tap:
    def __init__(self, f, sink):
        self.f, self.sink = f, sink

    def write(self, s):
        if s.startswith("S "):
            self.sink.append(s)
        return self.f.write(s)

    def flush(self):
        return self.f.flush()

    def close(self):
        return self.f.close()


class TraceSim(Sim):
    """A Sim that keeps every sensor line it sends and every command token
    the controller emits (per tick)."""

    def start_controller(self):
        super().start_controller()
        self.s_lines = []
        self.tokens = []
        self.proc.stdin = _Tap(self.proc.stdin, self.s_lines)
        self.task.on_command = lambda m, d, cmd: self.tokens.append((len(self.s_lines) - 1, cmd))


def record(params, seed, controller=None, attrs=ATTRS):
    task = load_task(TASK)
    for k, v in attrs.items():
        setattr(task, k, v)
    task.seed = seed
    sim = TraceSim(task, params=params, controller=controller)
    m = sim.run()
    frames = [[float(t) for t in line.split()[1:]] for line in sim.s_lines]
    return sim, m, frames


def _norm_job(seed):
    sim, m, frames = record(champion_params(), seed)
    lay = Layout(sim)
    return [lay.features(v) for v in frames]


def cmd_norm(args):
    """Input normalisation: mean and sd of every input over the champion's
    rollouts from 8 training starts (seeds 100001-100008)."""
    with mp.get_context("spawn").Pool(args.workers) as pool:
        rows = pool.map(_norm_job, list(range(100001, 100009)))
    X = np.array([x for r in rows for x in r])
    mu, sd = X.mean(0), np.maximum(X.std(0), 1e-3)
    p = {}
    for i in range(X.shape[1]):
        p[f"tcn_mu{i}"] = float(f"{mu[i]:.6g}")
        p[f"tcn_sd{i}"] = float(f"{sd[i]:.6g}")
    write_params(args.out, p, f"convkf input normalisation: champion rollouts, seeds 100001-100008, {len(X)} ticks")
    print(f"wrote {args.out}: {X.shape[1]} inputs over {len(X)} ticks")


def cmd_init(args):
    p = read_params(args.norm)
    arch = {"tcn": 1.0, "tcn_hidden": 8.0, "tcn_kernel": 3.0, "tcn_layers": 3.0, "tcn_max": 0.3}
    p.update(arch)
    nin = sum(1 for k in p if k.startswith("tcn_mu"))
    a = Arch(p, nin, 22)
    w = init_weights(a, args.seed)
    p.update({f"tcn_w{k}": float(v) for k, v in enumerate(w)})
    write_params(args.out, p, f"convkf TCN: {nin} inputs, dilations {a.dils}, {a.count()} weights "
                              f"(head zero), window {a.window()} ticks; init seed {args.seed}")
    print(f"wrote {args.out}: {a.count()} weights, window {a.window()} ticks")


def cmd_parity(args):
    """Record a rollout with a nonzero TCN (the controller emits its inputs and
    offsets every tick) and recompute both from the recorded sensor lines."""
    base = champion_params()
    init = read_params(args.init)
    nin = sum(1 for k in init if k.startswith("tcn_mu"))
    a = Arch(init, nin, 22)
    w = np.array([init[f"tcn_w{k}"] for k in range(a.count())])
    rng = np.random.default_rng(args.seed)
    nh = a.hidden * 22 + 22
    w[-nh:] = rng.normal(0.0, args.head, nh)  # a random head: nonzero, partly clamped offsets
    p = dict(base)
    p.update(init)
    p.update({f"tcn_w{k}": float(v) for k, v in enumerate(w)})
    p["tcn_trace"] = 2.0
    ctl = os.path.abspath(args.controller) if args.controller else None
    report = {}
    for seed in args.seeds:
        sim, m, frames = record(p, seed, ctl)
        lay = Layout(sim)
        xs = {}
        ys = {}
        for tick, tok in sim.tokens:
            if tok.startswith("tcnx:"):
                xs[tick] = [float(t) for t in tok[5:].split(",")]
            elif tok.startswith("tcn:"):
                ys[tick] = [float(t) for t in tok[4:].split(",")]
        mirror = ExactTCN(p, lay.nin, 22)
        fx = fy = 0
        dx = dy = 0.0
        X, Y = [], []
        for tick, v in enumerate(frames):
            x = mirror.normalise(lay.features(v))
            y = mirror.step(x)
            X.append(lay.features(v))
            Y.append(ys[tick])
            fx += sum(1 for u, w_ in zip(x, xs[tick]) if u != w_)
            fy += sum(1 for u, w_ in zip(y, ys[tick]) if u != w_)
            dx = max(dx, max(abs(u - w_) for u, w_ in zip(x, xs[tick])))
            dy = max(dy, max(abs(u - w_) for u, w_ in zip(y, ys[tick])))
        mu = np.array(mirror.mu)
        sd = np.array(mirror.sd)
        Yv, _ = forward_np(a, w, np.array(X), mu, sd)
        dv = float(np.max(np.abs(Yv - np.array(Y))))
        clamped = float(np.mean(np.abs(np.array(Y)) >= a.max))
        report[seed] = {"ticks": len(frames), "inputs_differing": fx, "outputs_differing": fy,
                        "max_input_diff": dx, "max_output_diff": dy, "vectorised_max_diff": dv,
                        "clamped_fraction": round(clamped, 3), "mark": m.get("mark"), "fallen": m.get("fallen")}
        print(f"seed {seed}: {len(frames)} ticks, {len(frames) * nin} inputs / {len(frames) * 22} outputs; "
              f"differing {fx} / {fy} (max {dx:.3g} / {dy:.3g}); vectorised mirror max diff {dv:.3g}; "
              f"{100 * clamped:.0f}% of offsets at the clamp")
    ok = all(r["inputs_differing"] == 0 and r["outputs_differing"] == 0 for r in report.values())
    print("PARITY", "OK (bit-exact)" if ok else "FAILED")
    if args.out:
        os.makedirs(os.path.dirname(args.out), exist_ok=True)
        json.dump({"ok": ok, "weights": a.count(), "seeds": report}, open(args.out, "w"), indent=1)
    return ok


# ---------------------------------------------------------------------------
# representations: theta (search coordinates) -> params


class Rep:
    """A search vector theta, starting at 0 (the champion / the untrained
    policy): value = x0 + scale * theta, clipped to the tunable's box where it
    has one. Scales make one unit of theta move the command about as much in
    every group: a keyframe contraction by its box width (1.2), a knot
    velocity by 1.2 / (0.19 T) and an acceleration by 1.2 / (0.0173 T^2) (T
    the keyframe chunk's duration; 0.19 and 0.0173 are the peak magnitudes of
    the quintic basis functions they multiply), a TCN head weight by 1 and a
    hidden-layer weight by HIDDEN_SCALE (a hidden weight only matters through
    the head, which starts at zero, so it can take ten times the step)."""

    def __init__(self, arm, base_path=None):
        self.arm = arm
        base = read_params(base_path) if base_path else champion_params()
        self.base = dict(base)
        names, x0, scale, lo, hi, group = [], [], [], [], [], []

        def add(n, v, s, l, h, g):
            names.append(n)
            x0.append(v)
            scale.append(s)
            lo.append(l)
            hi.append(h)
            group.append(g)

        if arm in ("knots", "knots_tcn", "champ"):
            fixed = {k: base[k] for k in base if k.startswith("fb_") or k == "rep"}
            if arm != "champ":
                fixed["kf_knots"] = 1.0
                self.base["kf_knots"] = 1.0
            tun = search.describe(TASK, fixed)
            for n, d, l, h in tun:
                if arm == "champ":
                    add(n, base.get(n, d), h - l, l, h, "champ")
                elif any(n.startswith(c + "_c_") for c in KF_CHUNKS):
                    add(n, base[n], h - l, l, h, "kf_c")
                elif any(n.startswith(c + "_v_") for c in KNOT_CHUNKS):
                    t = base[n.split("_v_")[0] + "_t"]
                    add(n, 0.0, 1.2 / (0.19 * t), l, h, "kf_v")
                elif any(n.startswith(c + "_a_") for c in KNOT_CHUNKS):
                    t = base[n.split("_a_")[0] + "_t"]
                    add(n, 0.0, 1.2 / (0.0173 * t * t), l, h, "kf_a")
        if arm in ("knots_tcn", "tcn"):
            init = read_params(os.path.join(ROOT, "params", "search", "convkf_tcn_init.txt"))
            self.base.update(init)
            nin = sum(1 for k in init if k.startswith("tcn_mu"))
            self.arch = Arch(init, nin, 22)
            head = self.arch.count() - (self.arch.hidden * 22 + 22)
            for k in range(self.arch.count()):
                add(f"tcn_w{k}", init[f"tcn_w{k}"], 1.0 if k >= head else HIDDEN_SCALE, -math.inf, math.inf, "tcn")
        self.names = names
        self.x0 = np.array(x0)
        self.scale = np.array(scale)
        self.lo = np.array(lo)
        self.hi = np.array(hi)
        self.group = np.array(group)
        self.n = len(names)

    def values(self, theta):
        return np.clip(self.x0 + self.scale * np.asarray(theta, float), self.lo, self.hi)

    def decode(self, theta):
        p = dict(self.base)
        p.update({n: float(v) for n, v in zip(self.names, self.values(theta))})
        return p

    def counts(self):
        return {g: int(np.sum(self.group == g)) for g in dict.fromkeys(self.group)}


# ---------------------------------------------------------------------------
# optimizers in theta space (maximising)


class ES:
    """Antithetic OpenAI-ES (Salimans et al. 2017): m mirrored pairs theta +-
    sigma eps, each pair rolled out from the same start (common random
    numbers), centred-rank fitness over all 2m rollouts, gradient sum (u+ -
    u-) eps / (2 m sigma), Adam ascent. The noise of each pair comes from its
    own seed (the "shared noise seeds" of the distributed version)."""

    def __init__(self, n, seed, sigma=0.003, lr=0.0006, pairs=16, shaping="ranks", k=1):
        self.n, self.seed, self.sigma, self.lr, self.m = n, seed, sigma, lr, pairs
        self.shaping = shaping
        self.k = k
        self.theta = np.zeros(n)
        self.mo, self.v, self.t = np.zeros(n), np.zeros(n), 0
        self.gen = 0

    def ask(self):
        self.eps = np.array([np.random.default_rng([self.seed, self.gen, i]).standard_normal(self.n)
                             for i in range(self.m)])
        X = np.vstack([self.theta + self.sigma * self.eps, self.theta - self.sigma * self.eps])
        starts = [[100000 + (self.gen * self.m + i) * self.k + j for j in range(self.k)] for i in range(self.m)] * 2
        return X, starts

    def tell(self, f):
        f = np.asarray(f, float)
        if self.shaping == "raw":
            # the pairs' score differences themselves, scaled by their spread:
            # a fall (about 1.45 below a landing) outweighs centimetres, as it
            # does in the expected score
            d = f[:self.m] - f[self.m:]
            w = d / (np.std(f) + 1e-9)
        elif self.shaping == "signed":
            # paired signed ranks: each pair's difference f+ - f- (its start's
            # difficulty cancels), ranked by size, keeping its sign
            d = f[:self.m] - f[self.m:]
            r = np.empty(self.m)
            r[np.argsort(np.abs(d), kind="stable")] = np.arange(1, self.m + 1)
            w = np.sign(d) * r / self.m
        else:
            ranks = np.empty(len(f))
            ranks[np.argsort(f, kind="stable")] = np.arange(len(f))
            u = ranks / (len(f) - 1) - 0.5
            w = u[:self.m] - u[self.m:]
        g = (w @ self.eps) / (2 * self.m * self.sigma)
        self.t += 1
        b1, b2 = 0.9, 0.999
        self.mo = b1 * self.mo + (1 - b1) * g
        self.v = b2 * self.v + (1 - b2) * g * g
        mh, vh = self.mo / (1 - b1 ** self.t), self.v / (1 - b2 ** self.t)
        self.theta = self.theta + self.lr * mh / (np.sqrt(vh) + 1e-8)
        self.gen += 1

    def centre(self):
        return self.theta


class SepCMA:
    """Separable CMA-ES (search.SepCMA's update, unbounded: theta has no box;
    bounded tunables are clipped when decoded). Every candidate of a
    generation is rolled out from the same `k` fresh starts (common random
    numbers) and scored by their mean."""

    def __init__(self, n, seed, sigma=0.003, k=4):
        self.k = k
        self.rng = np.random.default_rng(seed)
        self.n = n
        self.lam = 4 + int(3 * math.log(n))
        self.mu = self.lam // 2
        w = np.log(self.mu + 0.5) - np.log(np.arange(1, self.mu + 1))
        self.w = w / w.sum()
        self.mueff = 1.0 / np.sum(self.w ** 2)
        self.cc = (4 + self.mueff / n) / (n + 4 + 2 * self.mueff / n)
        self.cs = (self.mueff + 2) / (n + self.mueff + 5)
        c1 = 2 / ((n + 1.3) ** 2 + self.mueff)
        cmu = min(1 - c1, 2 * (self.mueff - 2 + 1 / self.mueff) / ((n + 2) ** 2 + self.mueff))
        scale = (n + 2) / 3.0
        self.c1 = min(1.0, c1 * scale)
        self.cmu = min(1.0 - self.c1, cmu * scale)
        self.damps = 1 + 2 * max(0, math.sqrt((self.mueff - 1) / (n + 1)) - 1) + self.cs
        self.chin = math.sqrt(n) * (1 - 1 / (4 * n) + 1 / (21 * n * n))
        self.mean = np.zeros(n)
        self.sigma = sigma
        self.C = np.ones(n)
        self.pc = np.zeros(n)
        self.ps = np.zeros(n)
        self.gen = 0

    def ask(self):
        self.X = self.mean + self.sigma * self.rng.standard_normal((self.lam, self.n)) * np.sqrt(self.C)
        starts = [200000 + self.gen * self.k + j for j in range(self.k)]
        return self.X, [starts] * self.lam

    def tell(self, f):
        f = np.asarray(f, float)
        X = self.X[np.argsort(-f, kind="stable")]
        old = self.mean.copy()
        ys = (X[:self.mu] - old) / self.sigma
        yw = self.w @ ys
        self.mean = old + self.sigma * yw
        self.ps = (1 - self.cs) * self.ps + math.sqrt(self.cs * (2 - self.cs) * self.mueff) * yw / np.sqrt(self.C)
        hs = (np.linalg.norm(self.ps) / math.sqrt(1 - (1 - self.cs) ** (2 * (self.gen + 1)))
              < (1.4 + 2 / (self.n + 1)) * self.chin)
        self.pc = (1 - self.cc) * self.pc + hs * math.sqrt(self.cc * (2 - self.cc) * self.mueff) * yw
        self.C = ((1 - self.c1 - self.cmu) * self.C + self.c1 * (self.pc ** 2 + (1 - hs) * self.cc * (2 - self.cc) * self.C)
                  + self.cmu * (self.w @ (ys ** 2)))
        self.C = np.maximum(self.C, 1e-20)
        self.sigma *= math.exp((self.cs / self.damps) * (np.linalg.norm(self.ps) / self.chin - 1))
        self.gen += 1

    def centre(self):
        return self.mean


# ---------------------------------------------------------------------------
# training


def _jobs(params, seeds):
    return [(TASK, params, s, 0.0, ATTRS) for s in seeds]


def summarise(scores, metrics):
    sc = np.array(scores)
    legal = [m.get("mark", 0.0) for s, m in zip(scores, metrics) if s > 0.0]
    return {"mean": float(sc.mean()), "falls": int(np.sum(sc < 0.0)), "n": len(sc),
            "legal_mark": float(np.mean(legal)) if legal else None}


def cmd_train(args):
    rep = Rep(args.arm, args.base)
    name = args.name or f"{args.arm}_{args.method}_s{args.seed}"
    out = os.path.join(OUT, name)
    os.makedirs(out, exist_ok=True)
    opt = (ES(rep.n, args.seed, args.sigma, args.lr, args.pairs, args.shaping, args.es_k) if args.method == "es"
           else SepCMA(rep.n, args.seed, args.sigma, args.k))
    if args.resume:
        # continue a finished run from its final centre (fresh optimizer
        # state, new noise and starts: generations are counted on)
        prev = json.load(open(os.path.join(args.resume, "summary.json")))
        th = np.load(os.path.join(args.resume, "final_theta.npy"))
        if args.method == "es":
            opt.theta = th.copy()
            opt.gen = prev["used"] // (2 * args.pairs * args.es_k)
        else:
            opt.mean = th.copy()
            opt.gen = prev["used"] // (opt.lam * opt.k)
    meta = {"arm": args.arm, "method": args.method, "seed": args.seed, "budget": args.budget, "n": rep.n,
            "groups": rep.counts(), "sigma": args.sigma, "attrs": ATTRS, "probe_seeds": PROBE_SEEDS,
            "base": args.base, "resume": args.resume}
    if args.method == "es":
        meta.update(lr=args.lr, pairs=args.pairs, shaping=args.shaping, starts_per_pair=args.es_k)
    else:
        meta.update(lam=opt.lam, k=opt.k)
    json.dump(meta, open(os.path.join(out, "meta.json"), "w"), indent=1)
    log = open(os.path.join(out, "log.jsonl"), "w")
    print(f"{name}: {rep.n} dims {rep.counts()}", flush=True)
    used, next_probe, best = 0, 0, None
    if args.resume:  # rollouts count on from the run continued (--budget is the total)
        used = next_probe = json.load(open(os.path.join(args.resume, "summary.json")))["used"]
    t0 = time.time()
    with mp.get_context("spawn").Pool(args.workers) as pool:
        def probe(tag):
            nonlocal best
            th = opt.centre().copy()
            res = pool.map(search.rollout, _jobs(rep.decode(th), PROBE_SEEDS), chunksize=1)
            s = summarise([r[0] for r in res], [r[1] for r in res])
            rec = {"probe": s, "rollouts": used, "gen": opt.gen, "tag": tag, "wall": round(time.time() - t0, 1)}
            log.write(json.dumps(rec) + "\n")
            log.flush()
            if best is None or s["mean"] > best[0]:
                best = (s["mean"], th, used)
                np.save(os.path.join(out, "best_probe_theta.npy"), th)
            print(f"  probe @{used}: mean {s['mean']:.4f}, falls {s['falls']}/{s['n']}, legal mark "
                  f"{s['legal_mark']}", flush=True)

        while True:
            if used >= next_probe:
                probe("periodic")
                next_probe += args.probe_every
            X, starts = opt.ask()
            per = sum(len(s) for s in starts)
            if used + per > args.budget:
                break
            jobs = [j for x, s in zip(X, starts) for j in _jobs(rep.decode(x), s)]
            res = pool.map(search.rollout, jobs, chunksize=1)
            f, at, falls = [], 0, 0
            for s in starts:
                sc = [r[0] for r in res[at:at + len(s)]]
                falls += sum(1 for v in sc if v < 0.0)
                f.append(float(np.mean(sc)))
                at += len(s)
            opt.tell(f)
            used += per
            th = opt.centre()
            rec = {"gen": opt.gen, "rollouts": used, "f_mean": float(np.mean(f)), "f_max": float(np.max(f)),
                   "falls": falls, "wall": round(time.time() - t0, 1),
                   "step": {g: float(np.linalg.norm(th[rep.group == g])) for g in rep.counts()}}
            if args.method == "sep_cma":
                rec["sigma"] = float(opt.sigma)
            log.write(json.dumps(rec) + "\n")
            log.flush()
            if opt.gen % 10 == 0:
                print(f"  gen {opt.gen} @{used}: f mean {rec['f_mean']:.4f} max {rec['f_max']:.4f}, falls "
                      f"{falls}/{per}, |theta| {rec['step']} ({rec['wall']:.0f}s)", flush=True)
        probe("final")
    np.save(os.path.join(out, "final_theta.npy"), opt.centre())
    write_params(os.path.join(out, "final.txt"), rep.decode(opt.centre()), f"convkf {name}: final centre after {used} rollouts")
    write_params(os.path.join(out, "best_probe.txt"), rep.decode(best[1]),
                 f"convkf {name}: best probe centre ({best[0]:.4f}) at {best[2]} rollouts")
    json.dump({**meta, "used": used, "best_probe": best[0], "best_probe_at": best[2], "wall": time.time() - t0},
              open(os.path.join(out, "summary.json"), "w"), indent=1)
    print(f"{name}: done, {used} rollouts, best probe {best[0]:.4f} at {best[2]}", flush=True)


def parse_seeds(s):
    out = []
    for part in s.split(","):
        if "-" in part:
            a, b = part.split("-")
            out += list(range(int(a), int(b) + 1))
        else:
            out.append(int(part))
    return out


def cmd_validate(args):
    seeds = parse_seeds(args.seeds)
    attrs = dict(ATTRS)
    attrs["noise"] = args.noise
    attrs["pitch_noise"] = args.noise / 2
    with mp.get_context("spawn").Pool(args.workers) as pool:
        for path in args.params:
            p = read_params(path)
            res = pool.map(search.rollout, [(TASK, p, s, 0.0, attrs) for s in seeds], chunksize=1)
            s = summarise([r[0] for r in res], [r[1] for r in res])
            out = {"params": path, "seeds": args.seeds, "noise": args.noise, **s,
                   "scores": [r[0] for r in res]}
            print(json.dumps({k: v for k, v in out.items() if k != "scores"}), flush=True)
            if args.out:
                with open(args.out, "a") as f:
                    f.write(json.dumps(out) + "\n")


def cmd_scan(args):
    """Step-size scan: random perturbations of one group of the search vector
    at several sigmas (each direction rolled out from its own start, seeds
    6201-), the fraction that fall and the mean score. Picks sigma per group."""
    rows = []
    with mp.get_context("spawn").Pool(args.workers) as pool:
        for arm, group in [("champ", "champ"), ("knots", "kf_c"), ("knots", "kf_v"), ("knots", "kf_a"),
                           ("tcn", "head"), ("tcn", "tcn")]:
            rep = Rep(arm)
            mask = rep.group == group
            if group == "head":
                mask = np.zeros(rep.n, bool)
                mask[-(rep.arch.hidden * 22 + 22):] = True
            for sigma in args.sigmas:
                jobs = []
                for i in range(args.dirs):
                    th = np.zeros(rep.n)
                    th[mask] = sigma * np.random.default_rng([args.seed, i]).standard_normal(int(mask.sum()))
                    jobs += _jobs(rep.decode(th), [6201 + i])
                res = pool.map(search.rollout, jobs, chunksize=1)
                s = summarise([r[0] for r in res], [r[1] for r in res])
                row = {"group": group, "dims": int(mask.sum()), "sigma": sigma, **s}
                rows.append(row)
                print(json.dumps(row), flush=True)
    if args.out:
        json.dump(rows, open(args.out, "w"), indent=1)


def _analyse_job(job):
    params, seed = job
    sim, m, frames = record(params, seed)
    lay = Layout(sim)
    labels = [row[1] for row in sim.log]
    targets = np.array([row[4] for row in sim.log])
    return [lay.features(v) for v in frames], labels, targets, m, lay.joints, [mu.name for mu in sim.muscles]


def cmd_analyse(args):
    """What a trained run learned: how far the keyframes and knots moved, the
    TCN's corrections per phase and muscle, and which inputs it reads (the
    mean change of its output when one input moves by half a standard
    deviation, from the vectorised mirror on recorded validation rollouts)."""
    run = args.run
    meta = json.load(open(os.path.join(run, "meta.json")))
    rep = Rep(meta["arm"], meta.get("base"))
    which = args.which
    th = np.load(os.path.join(run, f"{which}_theta.npy"))
    vals = rep.values(th)
    out = {"run": run, "which": which, "arm": meta["arm"], "method": meta["method"]}
    # keyframes and knots
    for g in ("kf_c", "kf_v", "kf_a", "champ"):
        m = rep.group == g
        if not m.any():
            continue
        d = vals[m] - rep.x0[m]
        names = np.array(rep.names)[m]
        top = np.argsort(-np.abs(d))[:6]
        out[g] = {"n": int(m.sum()), "rms_change": float(np.sqrt(np.mean(d ** 2))), "max_change": float(np.max(np.abs(d))),
                  "theta_norm": float(np.linalg.norm(th[m])), "top": [[names[i], round(float(d[i]), 4)] for i in top]}
    # rollouts of the trained controller and of the champion on the same starts
    seeds = VALID_SEEDS[:args.starts]
    trained = rep.decode(th)
    champ = rep.decode(np.zeros(rep.n))
    with mp.get_context("spawn").Pool(args.workers) as pool:
        tr = pool.map(_analyse_job, [(trained, s) for s in seeds])
        ch = pool.map(_analyse_job, [(champ, s) for s in seeds])
    muscles = tr[0][5]
    phases = ["set", "crouch", "extend", "flight", "land"]
    # command change against the champion, per phase (both runs' own phases)
    dcmd = {}
    for (_, lt, tt, _, _, _), (_, lc, tc, _, _, _) in zip(tr, ch):
        n = min(len(tt), len(tc))
        for ph in phases:
            idx = [i for i in range(n) if lt[i].endswith(":" + ph)]
            if idx:
                dcmd.setdefault(ph, []).append(np.abs(tt[idx] - tc[idx]).mean(0))
    out["command_change"] = {ph: {"mean": float(np.mean(v)), "top": [[muscles[i], round(float(x), 4)] for i, x in
                                  sorted(enumerate(np.mean(v, 0)), key=lambda t: -t[1])[:4]]}
                             for ph, v in dcmd.items()}
    out["marks"] = {"trained": [r[3].get("mark") for r in tr], "champion": [r[3].get("mark") for r in ch],
                    "trained_fallen": [bool(r[3].get("fallen")) for r in tr]}
    if meta["arm"] in ("tcn", "knots_tcn"):
        p = trained
        nin = rep.arch.nin
        w = np.array([p[f"tcn_w{k}"] for k in range(rep.arch.count())])
        w0 = rep.x0[rep.group == "tcn"]
        mu = np.array([p[f"tcn_mu{i}"] for i in range(nin)])
        sd = np.array([p[f"tcn_sd{i}"] for i in range(nin)])
        joints = tr[0][4]
        chans = ([f"c {j}" for j in joints] + [f"cdot {j}" for j in joints]
                 + ["l_foot_contact", "r_foot_contact", "com z", "com vx", "com vz", "torso pitch", "torso pitch rate"])
        sens = np.zeros(nin)
        per_phase = {}
        for X, labels, _, _, _, _ in tr:
            X = np.array(X)
            Y, _ = forward_np(rep.arch, w, X, mu, sd)
            for ph in phases:
                idx = [i for i, l in enumerate(labels[:len(Y)]) if l.endswith(":" + ph)]
                if idx:
                    per_phase.setdefault(ph, []).append(np.abs(Y[idx]).mean(0))
            for i in range(nin):
                Xp = X.copy()
                Xp[:, i] += 0.5 * sd[i]
                Yp, _ = forward_np(rep.arch, w, Xp, mu, sd)
                sens[i] += float(np.mean(np.abs(Yp - Y))) / 0.5 / len(tr)
        W1 = rep.arch.unpack(w)[0][0]
        W10 = rep.arch.unpack(w0)[0][0]
        dW1 = np.linalg.norm((W1 - W10).reshape(W1.shape[0], nin, -1), axis=(0, 2))
        order = np.argsort(-sens)
        head = rep.arch.unpack(w)[-1][0][:, :, 0]
        out["tcn"] = {
            "weights": rep.arch.count(), "head_norm": float(np.linalg.norm(head)),
            "hidden_change_norm": float(np.linalg.norm((w - w0)[:-(head.size + head.shape[0])])),
            "sensitivity": [[chans[i], round(float(sens[i]), 5)] for i in order],
            "first_layer_change": [[chans[i], round(float(dW1[i]), 4)] for i in np.argsort(-dW1)[:8]],
            "offset_by_phase": {ph: {"mean": float(np.mean(v)), "top": [[muscles[i], round(float(x), 4)] for i, x in
                                     sorted(enumerate(np.mean(v, 0)), key=lambda t: -t[1])[:4]]}
                                for ph, v in per_phase.items()}}
    path = os.path.join(run, f"analysis_{which}.json")
    json.dump(out, open(path, "w"), indent=1)
    print(json.dumps(out, indent=1)[:6000])


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("norm")
    a.add_argument("--out", default=os.path.join(ROOT, "params", "search", "convkf_tcn_norm.txt"))
    a.add_argument("--workers", type=int, default=3)
    a = sub.add_parser("init")
    a.add_argument("--norm", default=os.path.join(ROOT, "params", "search", "convkf_tcn_norm.txt"))
    a.add_argument("--out", default=os.path.join(ROOT, "params", "search", "convkf_tcn_init.txt"))
    a.add_argument("--seed", type=int, default=0)
    a = sub.add_parser("parity")
    a.add_argument("--init", default=os.path.join(ROOT, "params", "search", "convkf_tcn_init.txt"))
    a.add_argument("--controller")
    a.add_argument("--seeds", type=int, nargs="*", default=[0, 6001])
    a.add_argument("--seed", type=int, default=7)
    a.add_argument("--head", type=float, default=0.1)
    a.add_argument("--out")
    a = sub.add_parser("train")
    a.add_argument("--arm", choices=["champ", "knots", "knots_tcn", "tcn"], required=True)
    a.add_argument("--method", choices=["es", "sep_cma"], required=True)
    a.add_argument("--budget", type=int, default=3200)
    a.add_argument("--seed", type=int, default=1)
    a.add_argument("--sigma", type=float, default=0.003)
    a.add_argument("--lr", type=float, default=0.0006)
    a.add_argument("--pairs", type=int, default=16)
    a.add_argument("--shaping", choices=["ranks", "signed", "raw"], default="ranks")
    a.add_argument("--k", type=int, default=4, help="sep-CMA: starts per generation (shared)")
    a.add_argument("--es-k", type=int, default=1, help="ES: starts per antithetic pair (shared by the pair)")
    a.add_argument("--probe-every", type=int, default=400)
    a.add_argument("--base", help="params the search starts from (default: START, the jump champion P6 started from)")
    a.add_argument("--resume", help="a finished run's directory to continue from (its final centre)")
    a.add_argument("--workers", type=int, default=3)
    a.add_argument("--name")
    a = sub.add_parser("validate")
    a.add_argument("params", nargs="+")
    a.add_argument("--seeds", default="6101-6132")
    a.add_argument("--noise", type=float, default=0.003)
    a.add_argument("--workers", type=int, default=3)
    a.add_argument("--out")
    a = sub.add_parser("analyse")
    a.add_argument("run")
    a.add_argument("--which", choices=["final", "best_probe"], default="final")
    a.add_argument("--starts", type=int, default=6)
    a.add_argument("--workers", type=int, default=3)
    a = sub.add_parser("scan")
    a.add_argument("--sigmas", type=float, nargs="*", default=[0.001, 0.002, 0.005, 0.01, 0.02])
    a.add_argument("--dirs", type=int, default=12)
    a.add_argument("--seed", type=int, default=11)
    a.add_argument("--workers", type=int, default=3)
    a.add_argument("--out")
    args = ap.parse_args()
    {"analyse": cmd_analyse, "scan": cmd_scan, "norm": cmd_norm, "init": cmd_init, "parity": cmd_parity, "train": cmd_train,
     "validate": cmd_validate}[args.cmd](args)


if __name__ == "__main__":
    main()
