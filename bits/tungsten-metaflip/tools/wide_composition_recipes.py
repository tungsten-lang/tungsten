#!/usr/bin/env python3
"""Witness-backed block/Kronecker parents for the bounded cold loop.

Planning is not verification. Every used leaf and materialized result must
pass the independent tensor gates; catalogue/rank-only entries are not leaves.
"""
import base64
from functools import lru_cache
import gzip
import hashlib
import itertools
import math
from pathlib import Path
import re
import tempfile

import screen_top_two_projection_children as top
from search_wide_projection_walks import verify_file
from verify_composition_targets import block, naive

ROOT = Path(__file__).resolve().parents[3]
PAIR_SOURCE = ("bits/tungsten-metaflip/lib/metaflip/seeds/gf2/"
               "matmul_2x3x5_rank26_peterson_2026_block15_11_gf2.txt")


def check(condition, message):
    if not condition:
        raise ValueError(message)


def dimensions(shape, maximum=32):
    check(len(shape) == 3 and all(type(d) is int and 1 <= d <= maximum for d in shape),
          "invalid composition shape")
    return tuple(shape)


def read_leaf(path):
    raw = path.read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    body = raw
    if path.name.endswith(".mfw.gz.b64"):
        body = gzip.decompress(base64.b64decode(raw.replace(b"\n", b""), validate=True))
    if body.startswith(b"MFW1 "):
        shape, terms = top.read_blob(body)
    else:
        match = re.match(r"matmul_(\d+x\d+(?:x\d+)?)_rank", path.name)
        check(match is not None, "missing composition leaf shape")
        shape = tuple(map(int, match[1].split("x")))
        if len(shape) == 2:
            check(shape[0] == shape[1], "invalid square leaf name")
            shape += shape[:1]
        lines = [line.strip() for line in body.decode("ascii").splitlines()
                 if line.strip() and not line.lstrip().startswith("#")]
        rank = int(lines[0]) if lines[0].isdigit() else len(lines)
        terms = top.parse_terms(body, rank)
    return dimensions(shape, maximum=1024), sorted(terms), digest


def recipe_dependencies(recipe):
    """All campaign-state dependencies, not only the triggering parent."""
    kind = recipe["kind"]
    if kind == "seed":
        return {recipe["state"]} if "state" in recipe else set()
    if kind == "naive":
        return set()
    if kind == "projection":
        return recipe_dependencies(recipe["parent"])
    check(kind in ("split", "product"), "unknown composition recipe")
    return recipe_dependencies(recipe["left"]) | recipe_dependencies(recipe["right"])


def replay_recipe(recipe, root=ROOT, states=None, leaves=None):
    """Reconstruct a recipe; reject mutated shapes, ranks, references or cuts."""
    states = {} if states is None else states
    leaves = {} if leaves is None else leaves
    target = dimensions(recipe["shape"])
    canonical = tuple(sorted(target))
    kind, rank = recipe["kind"], recipe["rank"]
    check(type(rank) is int and 1 <= rank <= 16384, "invalid composition rank")
    if kind == "seed":
        if "state" in recipe:
            check("source" not in recipe and recipe["state"] in states,
                  "missing composition state")
            shape, terms = states[recipe["state"]]
        else:
            source = Path(recipe["source"])
            check(not source.is_absolute() and ".." not in source.parts,
                  "unsafe composition source")
            path = (root / source).resolve()
            check(path.is_relative_to(root.resolve()), "composition source outside root")
            pin = (str(path), recipe["source_sha256"])
            if pin not in leaves:
                shape, terms, digest = read_leaf(path)
                check(digest == recipe["source_sha256"], "composition source hash mismatch")
                top.exact(shape, terms)
                with tempfile.TemporaryDirectory() as temp:
                    witness = Path(temp) / "leaf.mfw"
                    witness.write_bytes(top.blob(shape, terms))
                    check(verify_file(witness)[:2] == (shape, terms),
                          "independent composition leaf mismatch")
                leaves[pin] = shape, terms
            shape, terms = leaves[pin]
        check(list(shape) == recipe["source_shape"] and tuple(sorted(shape)) == canonical
              and len(terms) == rank, "composition leaf metadata mismatch")
        terms = top.orient(shape, terms, canonical)
    elif kind == "projection":
        parent = recipe["parent"]
        source_shape = dimensions(parent["shape"])
        check(math.prod(source_shape) > math.prod(canonical),
              "non-decreasing projection dependency")
        steps = recipe["deletions"]
        check(isinstance(steps, list) and 1 <= len(steps) <= 93,
              "invalid composition projection")
        terms = replay_recipe(parent, root, states, leaves)
        for step in steps:
            source_shape, terms = top.project(source_shape, terms,
                                             step["axis"], step["coordinate"])
        check(source_shape == canonical, "composition projection shape mismatch")
    elif kind == "naive":
        check(rank == math.prod(canonical), "naive composition rank mismatch")
        terms = naive(canonical)
    else:
        check(kind in ("split", "product"), "unknown composition recipe")
        left = recipe["left"]
        right = recipe["right"]
        a, b = dimensions(left["shape"]), dimensions(right["shape"])
        # Strictly smaller children keep replay finite, even for mutated plans.
        check(math.prod(a) < math.prod(canonical) and math.prod(b) < math.prod(canonical),
              "non-decreasing composition dependency")
        if kind == "split":
            axis = recipe["axis"]
            check(type(axis) is int and axis in range(3) and
                  all(a[i] + b[i] == canonical[i] if i == axis else
                      a[i] == b[i] == canonical[i] for i in range(3)) and
                  rank == left["rank"] + right["rank"], "composition split mismatch")
        else:
            check(tuple(x * y for x, y in zip(a, b)) == canonical and
                  rank == left["rank"] * right["rank"], "composition product mismatch")
        lterms = replay_recipe(left, root, states, leaves)
        rterms = replay_recipe(right, root, states, leaves)
        if kind == "split":
            offsets = [a[i] if i == axis else 0 for i in range(3)]
            terms = block(a, lterms, canonical, [0, 0, 0]) + block(b, rterms, canonical, offsets)
        else:
            terms = top.kronecker(a, lterms, b, rterms)
    terms = top.orient(canonical, terms, target)
    check(len(terms) == rank, "materialized composition rank mismatch")
    return sorted(terms)


class CompositionLibrary:
    def __init__(self, root=ROOT):
        self.root = root
        self.seeds = {}
        self.states = {}
        self.leaves = {}
        self._reset()

    def _reset(self):
        self.plan = lru_cache(None)(self._plan)

    def _add(self, shape, terms, reference):
        canonical = tuple(sorted(dimensions(shape)))
        candidate = dict(kind="seed", rank=len(terms), source_shape=list(shape), **reference)
        old = self.seeds.get(canonical)
        if old is None or candidate["rank"] < old["rank"]:
            self.seeds[canonical] = candidate
            self._reset()

    @classmethod
    def from_repository(cls, root=ROOT):
        library = cls(root)
        base = root / "bits/tungsten-metaflip"
        files = sorted((*(base / "lib/metaflip/seeds/gf2").glob("matmul_*_gf2.txt"),
                        *(base / "tools/certificates").rglob("*.mfw"),
                        *(base / "tools/certificates").rglob("*.mfw.gz.b64")))
        for path in files:
            shape, terms, digest = read_leaf(path)
            if max(shape) <= 32 and len(terms) <= 8000:
                library._add(shape, terms, dict(source=str(path.relative_to(root)),
                                              source_sha256=digest))
        # The native pair arm already uses this exact projected rank-15 leaf.
        # Make its actual body available to arbitrary closure recipes too.
        pair = root / PAIR_SOURCE
        if pair.is_file():
            shape, terms, digest = read_leaf(pair)
            parent = dict(kind="seed", shape=list(shape), source_shape=list(shape),
                          rank=len(terms), source=PAIR_SOURCE, source_sha256=digest)
            for coordinate in (4, 3):
                shape, terms = top.project(shape, terms, 2, coordinate)
            check(shape == (2, 3, 3) and len(terms) == 15, "projected pair leaf mismatch")
            if library.seeds.get(shape, {"rank": 16})["rank"] > 15:
                library.seeds[shape] = dict(kind="projection", rank=15, parent=parent,
                    deletions=[dict(axis=2, coordinate=4), dict(axis=2, coordinate=3)])
                library._reset()
        return library

    def add_state(self, state):
        sha = state["sha256"]
        self.states[sha] = state["shape"], state["terms"]
        if max(state["shape"]) <= 32:
            self._add(state["shape"], state["terms"], dict(state=sha))

    def _plan(self, key):
        best = dict(kind="naive", rank=math.prod(key))
        seed = self.seeds.get(key)
        if seed is not None and seed["rank"] <= best["rank"]:
            best = seed
        if 1 not in key:
            for axis, extent in enumerate(key):
                for cut in range(1, extent // 2 + 1):
                    left, right = list(key), list(key)
                    left[axis], right[axis] = cut, extent - cut
                    a = self.recipe(tuple(left))
                    b = self.recipe(tuple(right))
                    rank = a["rank"] + b["rank"]
                    if rank < best["rank"]:
                        best = dict(kind="split", rank=rank, axis=axis, left=a, right=b)
            divisors = [[d for d in range(1, n + 1) if n % d == 0] for n in key]
            for left in itertools.product(*divisors):
                right = tuple(n // d for n, d in zip(key, left))
                if left == (1, 1, 1) or right == (1, 1, 1) or left > right:
                    continue
                a, b = self.recipe(left), self.recipe(right)
                rank = a["rank"] * b["rank"]
                if rank < best["rank"]:
                    best = dict(kind="product", rank=rank, left=a, right=b)
        return best

    def recipe(self, shape):
        shape = dimensions(shape)
        return dict(self.plan(tuple(sorted(shape))), shape=list(shape))

    def materialize(self, shape):
        recipe = self.recipe(shape)
        terms = replay_recipe(recipe, self.root, self.states, self.leaves)
        top.exact(shape, terms)
        return terms, recipe


def cheaper_parent(library, rows, current_price, max_rank):
    """At most one witness-backed replacement for a weaker projection beam."""
    candidates = []
    for row in rows:
        shape = tuple(row["shape"])
        if max(shape) > 32:
            continue
        recipe = library.recipe(shape)
        rank = recipe["rank"]
        if min(shape) >= 2 and rank < row["rank"] and rank <= max_rank:
            candidates.append((rank - current_price(tuple(sorted(shape))),
                               rank - row["rank"], rank, shape))
    if not candidates:
        return None
    _, _, _, shape = min(candidates)
    terms, recipe = library.materialize(shape)
    raw = top.blob(shape, terms)
    return dict(kind="closure-composition", shape=shape, rank=len(terms), raw=raw,
                sha256=hashlib.sha256(raw).hexdigest(), recipe=recipe)
