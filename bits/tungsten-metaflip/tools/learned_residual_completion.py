#!/usr/bin/env python3
"""Bounded offline learned residual completion over GF(2).

This is an experiment, NOT a production fleet lane or a rank oracle. Training
labels are known decomposition lengths (upper bounds), never optimal ranks.
Only exact flattening ranks prune; the model orders the remaining beam. Both
policies receive the same complete rank-one alphabet and XOR-work limit.
Artifacts stay in the caller's output directory, outside the runtime seeds.
"""
from __future__ import annotations

import argparse
from collections import Counter
from functools import lru_cache
import hashlib
import itertools
import json
import math
import os
from pathlib import Path
import random
import shutil
import time

for variable in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS",
                 "VECLIB_MAXIMUM_THREADS", "NUMEXPR_NUM_THREADS"):
    os.environ[variable] = "1"
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
SCHEMA = "metaflip-learned-residual-v1"
FEATURES = [f"mode_{a}_{f}" for a in range(3)
            for f in ("rank", "slice_rank0", "slice_rank1", "slice_rank2", "slice_rank3", "slice_rank4")]


def bits(value):
    while value:
        low = value & -value
        yield low.bit_length() - 1
        value ^= low


def xor(values):
    result = 0
    for value in values:
        result ^= value
    return result


def canonical(terms):
    return sorted(t for t, n in Counter(map(tuple, terms)).items() if n % 2 and all(t))


def outer(term, dims):
    u, v, w = term
    return xor(w << ((a * dims[1] + b) * dims[2]) for a in bits(u) for b in bits(v))


def tensor(terms, dims):
    return xor(outer(t, dims) for t in terms)


def basis(vectors):
    """Return original independent vectors and a coordinate elimination map."""
    pivots, originals = {}, []
    for original in vectors:
        value, code = original, 1 << len(originals)
        while value:
            p = value.bit_length() - 1
            if p not in pivots:
                pivots[p] = (value, code)
                originals.append(original)
                break
            value ^= pivots[p][0]
            code ^= pivots[p][1]
    return originals, pivots


def coordinates(value, pivots):
    code = 0
    while value:
        p = value.bit_length() - 1
        if p not in pivots:
            raise ValueError("vector outside residual mode space")
        value ^= pivots[p][0]
        code ^= pivots[p][1]
    return code


def slices(target, dims, axis):
    other = [i for i in range(3) if i != axis]
    rows = [0] * dims[axis]
    for bit in bits(target):
        xyz = (bit // (dims[1] * dims[2]), bit // dims[2] % dims[1], bit % dims[2])
        rows[xyz[axis]] ^= 1 << (xyz[other[0]] * dims[other[1]] + xyz[other[1]])
    return rows


def lift(terms, bases):
    return [tuple(xor(bases[a][i] for i in bits(t[a])) for a in range(3)) for t in terms]


def compress_residual(target, dims):
    """Lossless multilinear compression from the tensor ONLY, not its recipe."""
    if not target:
        return 0, (0, 0, 0), [[], [], []]
    current, shape, bases = target, list(dims), []
    for axis in range(3):
        rows = slices(current, shape, axis)
        other_size = math.prod(shape[a] for a in range(3) if a != axis)
        fibers = [sum(((row >> j) & 1) << i for i, row in enumerate(rows))
                  for j in range(other_size)]
        vectors, pivots = basis(fibers)
        bases.append(vectors)
        old = shape[:]
        shape[axis] = len(vectors)
        other = [a for a in range(3) if a != axis]
        updated = 0
        for j, fiber in enumerate(fibers):
            xyz = [0, 0, 0]
            xyz[other[0]], xyz[other[1]] = divmod(j, old[other[1]])
            for c in bits(coordinates(fiber, pivots)):
                xyz[axis] = c
                updated ^= 1 << ((xyz[0] * shape[1] + xyz[1]) * shape[2] + xyz[2])
        current = updated
    return current, tuple(shape), bases


@lru_cache(maxsize=65536)
def matrix_rank(value, columns):
    mask = (1 << columns) - 1
    rows = []
    while value:
        rows.append(value & mask)
        value >>= columns
    return len(basis(rows)[0])


def flatten_ranks(target, dims):
    return tuple(len(basis(slices(target, dims, a))[0]) for a in range(3))


def features(target, dims):
    """All slice-combination rank histograms: invariant to invertible bases.

    Zero rows are counted with multiplicity, so a change of basis permutes the
    same 2^dim-1 combinations. Sorting mode descriptors also removes mode order.
    Factor density and the removed factor list are deliberately absent.
    """
    if any(not 1 <= d <= 4 for d in dims):
        raise ValueError("feature model supports mode dimensions 1..4")
    descriptors = []
    for a in range(3):
        rows = slices(target, dims, a)
        columns = dims[[i for i in range(3) if i != a][1]]
        combos, hist = [0], [0] * 5
        for row in rows:
            combos += [v ^ row for v in combos]
        for value in combos[1:]:
            hist[matrix_rank(value, columns)] += 1
        descriptors.append((len(basis(rows)[0]), *(n / (len(combos) - 1) for n in hist)))
    return tuple(v for desc in sorted(descriptors) for v in desc)


def dot(a, b):
    return np.einsum("ij,jk->ik", a, b, optimize=False)


class ValueModel:
    """Small local MLP predicting known completion length, not certified rank."""
    def __init__(self, mean, scale, w1, b1, w2, b2):
        self.mean, self.scale = np.asarray(mean), np.asarray(scale)
        self.w1, self.b1 = np.asarray(w1), np.asarray(b1)
        self.w2, self.b2 = np.asarray(w2), np.asarray(b2)
        if (self.mean.shape != (18,) or self.scale.shape != (18,) or
                self.w1.shape != (18, 24) or self.b1.shape != (24,) or
                self.w2.shape != (24, 1) or self.b2.shape != (1,) or
                not all(np.isfinite(v).all() for v in self.arrays().values()) or
                np.any(self.scale <= 0)):
            raise ValueError("invalid value-model arrays")

    def arrays(self):
        return {k: getattr(self, k) for k in ("mean", "scale", "w1", "b1", "w2", "b2")}

    def predict(self, values):
        x = (np.asarray(values, dtype=float) - self.mean) / self.scale
        return (dot(np.maximum(0, dot(x, self.w1) + self.b1), self.w2) + self.b2)[:, 0]

    def save(self, path, metadata):
        path.write_text(json.dumps(dict(schema=SCHEMA, features=FEATURES, metadata=metadata,
                                       arrays={k: v.tolist() for k, v in self.arrays().items()}), indent=2) + "\n")

    @classmethod
    def load(cls, path):
        data = json.loads(path.read_text())
        if data.get("schema") != SCHEMA or data.get("features") != FEATURES:
            raise ValueError("value-model feature schema mismatch")
        return cls(**data["arrays"])


def synthetic_dataset(count, seed):
    """One row per exact residual identity, smallest observed recipe as label."""
    rng, records = random.Random(seed), {}
    for _ in range(count):
        dims = tuple(rng.randrange(2, 5) for _ in range(3))
        terms = canonical(tuple(rng.randrange(1, 1 << d) for d in dims)
                          for _ in range(rng.randrange(1, 7)))
        target = tensor(terms, dims)
        if not target:
            continue
        core, cdims, _ = compress_residual(target, dims)
        key = (cdims, core)
        label = len(terms)
        if key not in records or label < records[key]["label"]:
            identity = hashlib.sha256(repr(key).encode()).hexdigest()
            records[key] = dict(id=identity, dims=cdims, target=str(core), label=label,
                                recipe=terms, original_dims=dims, features=features(core, cdims))
    return list(records.values())


def train_model(rows, epochs, seed):
    # Group by the ENTIRE basis/mode-invariant feature descriptor before
    # splitting. Thus even feature-identical synthetic tensors cannot leak.
    groups = {}
    for i, row in enumerate(rows):
        signature = hashlib.sha256(repr(row["features"]).encode()).hexdigest()
        groups.setdefault(signature, []).append(i)
    train, validation, test = [], [], []
    for key, indices in sorted(groups.items()):
        bucket = int(hashlib.sha256((str(seed) + key).encode()).hexdigest(), 16) % 10
        (test if bucket == 0 else validation if bucket == 1 else train).extend(indices)
    if min(len(train), len(validation), len(test)) < 10:
        raise ValueError("need more independent synthetic feature groups")
    x = np.asarray([r["features"] for r in rows], dtype=float)
    y = np.asarray([r["label"] for r in rows], dtype=float)[:, None]
    mean, scale = x[train].mean(0), np.maximum(x[train].std(0), 0.1)
    x = (x - mean) / scale
    rng = np.random.default_rng(seed)
    weights = dict(w1=rng.normal(0, 0.2, (18, 24)), b1=np.zeros(24),
                   w2=rng.normal(0, 0.2, (24, 1)), b2=np.zeros(1))
    moment = {k: np.zeros_like(v) for k, v in weights.items()}
    variance = {k: np.zeros_like(v) for k, v in weights.items()}
    best, best_loss, best_epoch = None, float("inf"), 0
    xt, yt = x[train], y[train]
    for epoch in range(1, epochs + 1):
        hidden = np.maximum(0, dot(xt, weights["w1"]) + weights["b1"])
        prediction = dot(hidden, weights["w2"]) + weights["b2"]
        dy = 2 * (prediction - yt) / len(xt)
        dh = dot(dy, weights["w2"].T) * (hidden > 0)
        gradients = dict(w2=dot(hidden.T, dy), b2=dy.sum(0), w1=dot(xt.T, dh), b1=dh.sum(0))
        for k, g in gradients.items():
            g = np.clip(g, -10, 10) + 0.0001 * weights[k]
            moment[k] = 0.9 * moment[k] + 0.1 * g
            variance[k] = 0.999 * variance[k] + 0.001 * g * g
            weights[k] -= 0.01 * (moment[k] / (1 - 0.9 ** epoch)) / (np.sqrt(variance[k] / (1 - 0.999 ** epoch)) + 1e-8)
        hv = np.maximum(0, dot(x[validation], weights["w1"]) + weights["b1"])
        loss = float(np.mean((dot(hv, weights["w2"]) + weights["b2"] - y[validation]) ** 2))
        if math.isfinite(loss) and loss < best_loss:
            best, best_loss, best_epoch = {k: v.copy() for k, v in weights.items()}, loss, epoch
    if best is None:
        raise ValueError("non-finite training")
    model = ValueModel(mean, scale, **best)
    prediction = model.predict([rows[i]["features"] for i in test])
    metadata = dict(seed=seed, epochs=epochs, selected_epoch=best_epoch,
                    training=len(train), validation=len(validation), test=len(test),
                    validation_mse=best_loss, test_mse=float(np.mean((prediction-y[test, 0]) ** 2)),
                    label="smallest observed synthetic decomposition length, NOT optimal rank",
                    split="grouped by full basis-invariant features; real seed groups never train",
                    test_ids=[rows[i]["id"] for i in test])
    return model, metadata, test


class ResidualCompletionArm:
    """Budgeted proposer; sees residual+dims only and can never certify failure."""
    def __init__(self, policy="learned", model=None, beam=4, budget=12000, seconds=5):
        if policy not in ("learned", "popcount", "random") or (policy == "learned" and model is None):
            raise ValueError("invalid policy/model")
        if not 1 <= beam <= 64 or not 1 <= budget <= 1000000 or not 0 < seconds <= 600:
            raise ValueError("invalid bounded search limits")
        self.policy, self.model, self.beam, self.budget, self.seconds = policy, model, beam, budget, seconds

    def complete(self, target, dims, max_terms, seed):
        start, rng = time.monotonic(), random.Random(seed)
        stats = dict(policy=self.policy, xor_checks=0, pruned=0, transpositions=0,
                     feature_evaluations=0, model_batches=0, status="beam_exhausted")
        def finish(answer, status):
            if answer is not None and (len(answer) > max_terms or tensor(answer, dims) != target):
                raise ValueError("completion failed exact gate")
            stats.update(status=status, elapsed_seconds=time.monotonic()-start)
            return answer, stats
        if (len(dims) != 3 or any(type(d) is not int or not 0 <= d <= 64 for d in dims) or
                (0 in dims and dims != (0, 0, 0)) or math.prod(dims) > 16384 or
                type(target) is not int or type(max_terms) is not int or
                not 0 <= target < 1 << math.prod(dims) or not 0 <= max_terms <= 6):
            raise ValueError("invalid residual/rank limit")
        if not target:
            return finish([], "exact")
        if max(flatten_ranks(target, dims)) > max_terms:
            return finish(None, "flattening_lower_bound")
        if any(not 1 <= d <= 4 for d in dims):
            return finish(None, "unsupported_mode_dimension")
        alphabet = list(itertools.product(*(range(1, 1 << d) for d in dims)))
        rng.shuffle(alphabet)
        columns = [(outer(t, dims), t) for t in alphabet]
        direct = dict(columns)
        stats["alphabet_size"] = len(columns)
        beam, visited, cache = [(target, ())], {target: 0}, {}
        for depth in range(max_terms):
            children = {}
            remaining = max_terms - depth - 1
            for residual, path in beam:
                # Exact rank-one tail completion is shared by ALL policies.
                if residual in direct:
                    return finish(canonical(path + (direct[residual],)), "exact")
                for column, term in columns:
                    if stats["xor_checks"] >= self.budget:
                        return finish(None, "work_budget")
                    if time.monotonic() - start >= self.seconds:
                        return finish(None, "time_budget")
                    stats["xor_checks"] += 1
                    child = residual ^ column
                    if child == 0:
                        return finish(canonical(path + (term,)), "exact")
                    if child in visited and visited[child] <= depth + 1:
                        stats["transpositions"] += 1
                        continue
                    visited[child] = depth + 1
                    if max(flatten_ranks(child, dims)) > remaining:
                        stats["pruned"] += 1
                        continue
                    if remaining >= 1 and child in direct:
                        return finish(canonical(path + (term, direct[child])), "exact")
                    if remaining:
                        children[child] = path + (term,)
            if not children:
                break
            states = list(children)
            if self.policy == "learned":
                # Bound both cache/work and inference memory; check the wall
                # deadline while extracting features, not just during XORs.
                for state in states:
                    if time.monotonic() - start >= self.seconds:
                        return finish(None, "time_budget")
                    if state not in cache:
                        cache[state] = features(state, dims)
                        stats["feature_evaluations"] += 1
                scores = self.model.predict([cache[s] for s in states])
                stats["model_batches"] += 1
                if not np.isfinite(scores).all():
                    raise ValueError("non-finite model predictions")
            elif self.policy == "popcount":
                scores = [s.bit_count() for s in states]
            else:
                scores = [rng.random() for _ in states]
            chosen = sorted(range(len(states)), key=lambda i: (scores[i], states[i]))[:self.beam]
            beam = [(states[i], children[states[i]]) for i in chosen]
        return finish(None, "beam_exhausted")


def read_seed(path, shape):
    lines = [line.strip() for line in path.read_text().splitlines() if line.strip() and not line.startswith("#")]
    header = lines.pop(0).split()
    if len(header) == 5 and header[0] == "MFW1":
        if tuple(map(int, header[1:4])) != tuple(shape):
            raise ValueError("seed shape mismatch")
        count, base = int(header[4]), 16
    elif len(header) == 1:
        count, base = int(header[0]), 10
    elif len(header) == 4 and header[0] == "R":
        lines.insert(0, " ".join(header))
        if any(not line.startswith("R ") for line in lines):
            raise ValueError("inconsistent R-prefixed seed")
        lines = [line[2:] for line in lines]
        count, base = len(lines), 10
    else:
        raise ValueError("rank or MFW1 header required")
    terms = [tuple(int(v, base) for v in line.split()) for line in lines]
    if len(terms) != count or any(len(t) != 3 for t in terms):
        raise ValueError("invalid seed term count")
    verify_full(terms, shape)
    return terms


def verify_full(terms, shape):
    n, m, p = shape
    widths = (n*m, m*p, n*p)
    rows = [0] * (widths[0]*widths[1])
    for term in terms:
        if len(term) != 3 or any(type(v) is not int or not 0 < v < 1 << d for v, d in zip(term, widths)):
            raise ValueError("invalid tensor factors")
        u, v, w = term
        for a in bits(u):
            for b in bits(v):
                rows[a*widths[1]+b] ^= w
    for a in range(widths[0]):
        for b in range(widths[1]):
            want = 1 << ((a//m)*p+b%p) if a % m == b//p else 0
            if rows[a*widths[1]+b] != want:
                raise ValueError("full GF(2) tensor identity failed")


def splice(parent, selected, replacement, shape):
    if len(set(selected)) != len(selected) or any(not 0 <= i < len(parent) for i in selected):
        raise ValueError("invalid selected term positions")
    n, m, p = shape
    dims = (n*m, m*p, n*p)
    if tensor([parent[i] for i in selected], dims) != tensor(replacement, dims):
        raise ValueError("replacement residual mismatch")
    result = canonical([t for i, t in enumerate(parent) if i not in selected] + list(replacement))
    verify_full(result, shape)
    return result


def real_cases(count, seed):
    seeds = [((2, 2, 2), "matmul_2x2_rank7_strassen_gf2.txt"),
             ((3, 3, 3), "matmul_3x3_rank23_d139_gf2.txt"),
             ((2, 4, 5), "matmul_2x4x5_rank33_catalog_gf2.txt"),
             ((4, 4, 5), "matmul_4x4x5_rank60_d919_gf2.txt"),
             ((5, 5, 5), "matmul_5x5_rank93_d1155_gf2.txt")]
    rng, output = random.Random(seed), []
    for shape, name in seeds:
        path = ROOT / "lib/metaflip/seeds/gf2" / name
        if not path.is_file():
            raise ValueError(f"missing declared seed: {path}")
        parent = read_seed(path, shape)
        widths = (shape[0]*shape[1], shape[1]*shape[2], shape[0]*shape[2])
        for i in range(count):
            k = 3 + i % 4
            # Half random, half shared-factor neighborhoods; same frozen
            # windows for all policies, chosen without looking at outcomes.
            anchor = rng.randrange(len(parent))
            positions = list(range(len(parent)))
            rng.shuffle(positions)
            if i % 2:
                positions.sort(key=lambda j: -sum(parent[j][a] == parent[anchor][a] for a in range(3)))
            chosen = sorted(positions[:k])
            target = tensor([parent[j] for j in chosen], widths)
            core, dims, bases = compress_residual(target, widths)
            output.append(dict(id=f"{shape}-{i}", shape=shape, source=str(path),
                               source_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                               parent=parent, selected=chosen, target=core, dims=dims, bases=bases,
                               group_size=k, window="shared" if i % 2 else "random"))
    return output


def run(args):
    out = args.output.resolve()
    repository = ROOT.parents[1]
    if out == repository or repository in out.parents:
        raise ValueError("keep model/dataset/candidates outside the source repository")
    out.mkdir(parents=True, exist_ok=False)
    shutil.copyfile(__file__, out / "source.py")
    started = time.monotonic()
    data = synthetic_dataset(args.samples, args.seed)
    model, metadata, test_indices = train_model(data, args.epochs, args.seed)
    with (out / "training.jsonl").open("w") as stream:
        for row in data:
            stream.write(json.dumps(row) + "\n")
    metadata["dataset_sha256"] = hashlib.sha256((out / "training.jsonl").read_bytes()).hexdigest()
    metadata["source_sha256"] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    model.save(out / "model.json", metadata)
    model = ValueModel.load(out / "model.json")
    print(json.dumps(dict(event="trained", **{k: v for k, v in metadata.items() if k != "test_ids"})), flush=True)
    real = real_cases(args.windows, args.seed + 1)
    with (out / "cases.jsonl").open("w") as stream:
        for case in real:
            stream.write(json.dumps(case) + "\n")
    tasks = [("real", c, c["group_size"]-drop) for c in real for drop in (1, 0)]
    tasks += [("synthetic_test", dict(id=data[i]["id"], target=int(data[i]["target"]),
                                     dims=data[i]["dims"]), data[i]["label"])
              for i in test_indices[:args.holdout]]
    totals, identities = {}, set()
    with (out / "results.jsonl").open("w") as stream:
        for index, (kind, case, cap) in enumerate(tasks):
            # Rotate order and clear the shared rank cache to avoid rewarding
            # a systematically warm-cache policy in wall-time comparisons.
            policies = ["learned", "popcount", "random"]
            policies = policies[index % 3:] + policies[:index % 3]
            for policy in policies:
                matrix_rank.cache_clear()
                arm = ResidualCompletionArm(policy, model, args.beam, args.budget, args.seconds)
                answer, stats = arm.complete(case["target"], tuple(case["dims"]), cap, args.seed+index)
                row = dict(kind=kind, case=case["id"], max_terms=cap, **stats)
                if answer is not None:
                    row["completion"] = answer
                if kind == "real":
                    row.update(group_size=case["group_size"], shape=case["shape"], window=case["window"])
                    if answer is not None:
                        replacement = lift(answer, case["bases"])
                        candidate = splice(case["parent"], case["selected"], replacement, case["shape"])
                        text = str(len(candidate)) + "\n" + "".join(" ".join(map(str, t))+"\n" for t in candidate)
                        identity = hashlib.sha256(text.encode()).hexdigest()
                        row.update(exact_full=True, rank=len(candidate), rank_drop=len(case["parent"])-len(candidate),
                                   distinct_from_parent=candidate != canonical(case["parent"]), candidate_sha256=identity)
                        if row["distinct_from_parent"] and identity not in identities:
                            identities.add(identity)
                            (out / f"candidate-{identity}.txt").write_text(text)
                        row["candidate_path"] = str(out / f"candidate-{identity}.txt") if row["distinct_from_parent"] else None
                stream.write(json.dumps(row) + "\n")
                stream.flush()
                key = f"{kind}/{policy}/" + ("drop" if kind == "real" and cap < case["group_size"] else "recover")
                total = totals.setdefault(key, dict(cases=0, exact=0, rank_drops=0, distinct=0, xor_checks=0,
                                                   seconds=0, statuses={}))
                total["cases"] += 1
                total["exact"] += int(answer is not None)
                total["rank_drops"] += int(row.get("rank_drop", 0) > 0)
                total["distinct"] += int(row.get("distinct_from_parent", False))
                total["xor_checks"] += stats["xor_checks"]
                total["seconds"] += stats["elapsed_seconds"]
                total["statuses"][stats["status"]] = total["statuses"].get(stats["status"], 0)+1
            if index % 10 == 0:
                print(json.dumps(dict(event="progress", tasks=index+1, total=len(tasks))), flush=True)
    report = dict(schema=SCHEMA, record_claim=False, production_enabled=False,
                  config={**vars(args), "output": str(out)}, training=metadata, totals=totals,
                  distinct_candidates=len(identities), elapsed_seconds=time.monotonic()-started)
    (out / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(dict(event="complete", totals=totals, distinct_candidates=len(identities),
                          elapsed_seconds=report["elapsed_seconds"], report=str(out / "report.json"))), flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--samples", type=int, default=4000)
    parser.add_argument("--epochs", type=int, default=300)
    parser.add_argument("--windows", type=int, default=12, help="3..6-term windows per real shape")
    parser.add_argument("--holdout", type=int, default=24)
    parser.add_argument("--beam", type=int, default=4)
    parser.add_argument("--budget", type=int, default=12000, help="maximum rank-one XOR evaluations per case/policy")
    parser.add_argument("--seconds", type=float, default=5)
    parser.add_argument("--seed", type=int, default=20260914)
    args = parser.parse_args()
    if not 100 <= args.samples <= 100000 or not 1 <= args.epochs <= 10000 or not 1 <= args.windows <= 1000 or not 0 <= args.holdout <= 1000:
        parser.error("training/case limits out of bounds")
    run(args)
