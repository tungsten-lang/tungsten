#!/usr/bin/env python3
"""Replay matmulcatalog lineage recipes over GF(2) into explicit tensors.

matmulcatalog (https://github.com/solven-eu/matmulcatalog, arXiv:2606.13408) keeps many schemes
as recipes ("derived" files: Recombination, SerendipitousProduct, Kronecker products,
concatenations, projections) over atomic schemes with explicit coefficients. Its `fields`
label is inferred from recorded ranks and can over-claim: a recipe whose rank needs a leaf that
is valid only over Q or F3 is still stamped F2. Replaying with F2-valid leaves shows what each
recipe really reaches over GF(2); the result is checked against the complete matrix-multiplication
tensor by the caller (`mmc_gf2_seeds.py`).

Attribution: `Replayer.deps_file[path]` lists ("atom", catalogue path) for every atomic scheme a
result depends on, plus board leaves and ("nonf2", shape) markers; `Source.atom_info` returns the
catalogue's own source/year/URL fields for it.
"""
import json
import os
import re
import subprocess
import sys
import time
from fractions import Fraction
from pathlib import Path

sys.setrecursionlimit(20000)
HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import mmc_gf2_alg as G  # noqa: E402
from mmc_gf2_alg import Alg  # noqa: E402

LOG = []


def log(*a):
    msg = " ".join(str(x) for x in a)
    LOG.append(msg)
    if os.environ.get("MMC_VERBOSE"):
        print(msg, file=sys.stderr, flush=True)


# ------------------------------------------------------------------ catalogue source
class Source:
    """A matmulcatalog checkout pinned at one revision; a blob-less partial clone is enough
    (scheme files are fetched on demand and cached under `cache_dir/<revision>`)."""

    PREFIX = "src/main/resources/schemes/"
    FNAME = re.compile(r"^(\d+)x(\d+)x(\d+)-r(\d+)-(.*)-([0-9a-f]{7})\.json$")

    def __init__(self, clone, revision="HEAD", cache_dir="mmc-cache"):
        self.clone = str(clone)
        self.revision = self._git("rev-parse", revision).strip()
        root = Path(cache_dir) / self.revision[:12]
        self.json_cache = root / "json"
        self.mfw_cache = str(root / "mfw")
        os.makedirs(self.mfw_cache, exist_ok=True)
        names = self._git("ls-tree", "-r", "--name-only", self.revision, self.PREFIX).splitlines()
        self.tree = [n[len(self.PREFIX):] for n in names if n.startswith(self.PREFIX)]
        self.by_stem, self.by_h7, self.by_sorted = {}, {}, {}
        for f in self.tree:
            base = os.path.basename(f)
            stem = base[:-5] if base.endswith(".json") else base
            self.by_stem.setdefault(stem, []).append(f)
            m = self.FNAME.match(base)
            if m:
                n, mm, p, r = (int(m.group(i)) for i in range(1, 5))
                self.by_h7.setdefault(m.group(6), []).append(f)
                self.by_sorted.setdefault(tuple(sorted((n, mm, p))), []).append((r, f))
        for k in self.by_sorted:
            self.by_sorted[k].sort()
        self.catalog = json.loads(self._git("show", self.revision + ":docs/catalog.json"))["schemes"]
        self.by_file = {e["file"]: e for e in self.catalog}
        self.by_key = {}
        for e in self.catalog:
            if not e.get("complex"):
                self.by_key.setdefault(tuple(sorted(e["format"])), []).append(e)

    def _git(self, *args):
        return subprocess.check_output(["git", "-C", self.clone, *args], text=True)

    def raw(self, path):
        """Text of schemes/<path> at the pinned revision."""
        cp = self.json_cache / path
        if cp.exists():
            return cp.read_text()
        last = None
        for attempt in range(6):
            r = subprocess.run(["git", "-C", self.clone, "show", self.revision + ":" + self.PREFIX + path],
                               capture_output=True, text=True)
            if r.returncode == 0 and r.stdout:
                cp.parent.mkdir(parents=True, exist_ok=True)
                tmp = cp.with_name(cp.name + ".tmp%d" % os.getpid())
                tmp.write_text(r.stdout)
                os.replace(tmp, cp)
                return r.stdout
            last = r.stderr
            time.sleep(1 + attempt)
        raise RuntimeError("fetch failed %s: %s" % (path, last))

    def load(self, path):
        return json.loads(self.raw(path))

    def atom_info(self, path):
        """The catalogue's own attribution fields for one scheme file."""
        e = self.by_file.get(path, {})
        return dict(file=path, shape="x".join(map(str, e.get("format", []))), rank=e.get("rank"),
                    source=e.get("source"), year=e.get("year"), fields=e.get("fields"),
                    source_scheme_url=e.get("source_scheme_url"), source_paper_url=e.get("source_paper_url"))


def load_board_alg(path, key):
    """An exact local GF(2) witness (MFW1, .gz.b64 or decimal text) as an Alg."""
    import gf2_record_board as grb
    p = Path(path)
    shape, terms = grb.decode(p, grb.load(p))
    if tuple(sorted(shape)) != key:
        raise ReplayError("board witness shape mismatch %s" % path)
    return Alg(*shape, [tuple(t) for t in terms])


class ReplayError(Exception):
    pass


# ------------------------------------------------------------------ atom loading
def parity(v):
    if isinstance(v, bool):
        raise ReplayError("bool coefficient")
    if isinstance(v, int):
        return v & 1
    if isinstance(v, float):
        if v != int(v):
            f = Fraction(v).limit_denominator(10 ** 6)
            if abs(float(f) - v) > 1e-9:
                raise ReplayError("non-rational coefficient %r" % v)
        else:
            return int(v) & 1
    else:
        f = Fraction(str(v).strip())
    if f.denominator % 2 == 0:
        raise ReplayError("even denominator coefficient %r" % v)
    return f.numerator & 1


def _sparse_rows(node, rank):
    """-> list (len rank) of list of (pos, coef)."""
    out = []
    if isinstance(node, list):
        if len(node) != rank:
            raise ReplayError("sparse rows %d != rank %d" % (len(node), rank))
        for obj in node:
            out.append([(int(k), v) for k, v in obj.items()])
    elif isinstance(node, dict):
        for k in range(rank):
            row = node.get(str(k))
            if row is None:
                raise ReplayError("row-map missing %d" % k)
            if len(row["i"]) != len(row["c"]):
                raise ReplayError("row-map i/c mismatch")
            out.append(list(zip(row["i"], row["c"])))
    else:
        raise ReplayError("bad sparse node")
    return out


def load_atom_json(d):
    n1, n2, n3 = d["n"]
    rank = d["m"]
    dimU, dimV, dimW = n1 * n2, n2 * n3, n1 * n3

    def wpos(pd):  # dron col-major -> row-major
        i, j = pd % n1, pd // n1
        return i * n3 + j

    if "u_sparse" in d:
        U = _sparse_rows(d["u_sparse"], rank)
        V = _sparse_rows(d["v_sparse"], rank)
        W = _sparse_rows(d["w_sparse"], rank)
    elif "u" in d:
        u0 = d["u"][0] if d["u"] else []
        if u0 and isinstance(u0[0], dict):
            if any(k in d for k in ("u_fresh", "v_fresh", "w_fresh")):
                raise ReplayError("reduced format with fresh intermediates unsupported")
            U = [[(o["index"], o["value"]) for o in row] for row in d["u"]]
            V = [[(o["index"], o["value"]) for o in row] for row in d["v"]]
            # w: dim rows x sparse rank entries (col-major positions)
            W = [[] for _ in range(rank)]
            if len(d["w"]) != dimW:
                raise ReplayError("reduced w rows")
            for pd, row in enumerate(d["w"]):
                for o in row:
                    W[o["index"]].append((pd, o["value"]))
        else:
            for key, dim in (("u", dimU), ("v", dimV), ("w", dimW)):
                if len(d[key]) != rank or any(len(r) != dim for r in d[key]):
                    raise ReplayError("dense %s wrong size" % key)
            U = [[(i, v) for i, v in enumerate(r) if v not in (0, "0")] for r in d["u"]]
            V = [[(i, v) for i, v in enumerate(r) if v not in (0, "0")] for r in d["v"]]
            W = [[(i, v) for i, v in enumerate(r) if v not in (0, "0")] for r in d["w"]]
    else:
        raise ReplayError("no factor matrices")
    if len(U) != rank or len(V) != rank or len(W) != rank:
        raise ReplayError("rank mismatch")
    terms = []
    for k in range(rank):
        a = b = c = 0
        for pos, v in U[k]:
            if not 0 <= int(pos) < dimU:
                raise ReplayError("u pos range")
            if parity(v):
                a ^= 1 << int(pos)
        for pos, v in V[k]:
            if not 0 <= int(pos) < dimV:
                raise ReplayError("v pos range")
            if parity(v):
                b ^= 1 << int(pos)
        for pos, v in W[k]:
            if not 0 <= int(pos) < dimW:
                raise ReplayError("w pos range")
            if parity(v):
                c ^= 1 << wpos(int(pos))
        terms.append((a, b, c))
    return Alg(n1, n2, n3, terms)


def is_stub(d):
    return not any(k in d for k in ("u", "u_sparse"))


# ------------------------------------------------------------------ MFW1 cache
def write_mfw(path, a):
    tmp = path + ".tmp%d" % os.getpid()
    with open(tmp, "w") as fh:
        fh.write("MFW1 %d %d %d %d\n" % (a.n, a.m, a.p, a.r))
        for t in sorted(a.terms):
            fh.write("%x %x %x\n" % t)
    os.replace(tmp, path)


def read_mfw(path):
    with open(path) as fh:
        head, *lines = fh.read().splitlines()
    tag, n, m, p, r = head.split()
    terms = [tuple(int(x, 16) for x in l.split()) for l in lines]
    assert tag == "MFW1" and len(terms) == int(r)
    return Alg(int(n), int(m), int(p), terms)




# ------------------------------------------------------------------ replayer
class Replayer:
    def __init__(self, source, board=None, allow_nonf2=False, use_disk_cache=True):
        """`board`: {sorted shape: (rank, witness path)} of extra exact GF(2) leaves (optional).
        `allow_nonf2` also replays catalogue schemes that are not stamped F2 (diagnostics)."""
        self.src = source
        self.file_memo = {}      # path -> Alg (declared orientation) or ReplayError
        self.best_memo = {}      # sorted key -> Alg or None
        self.active = []
        self.disk = use_disk_cache
        self.board = dict(board or {})
        self.use_board = bool(self.board)
        self.allow_nonf2 = allow_nonf2
        self.cachedir = source.mfw_cache + ("_wide" if allow_nonf2 else "_board" if self.use_board else "")
        os.makedirs(self.cachedir, exist_ok=True)
        # Dependencies of a materialized file: board leaves (sorted shape), ("nonf2", *shape)
        # for a Q/F3-only leaf, and ("atom", path) for every atomic catalogue file used.
        self.deps_file = {}
        self.deps_best = {}
        self.dep_stack = [set()]

    def _note(self, deps):
        self.dep_stack[-1] |= deps

    # ---- files
    def materialize_file(self, path):
        if path in self.file_memo:
            v = self.file_memo[path]
            if isinstance(v, Exception):
                raise v
            self._note(self.deps_file.get(path, set()))
            return v
        if path in self.active:
            raise ReplayError("lineage cycle: " + " -> ".join(self.active + [path]))
        atomic = path.startswith("BOARD:") or not is_stub(self.src.load(path))
        cp = os.path.join(self.src.mfw_cache if atomic else self.cachedir, path.replace("/", "__") + ".mfw")
        depf = cp + ".deps.json"
        if self.disk and os.path.exists(cp) and (atomic or os.path.exists(depf)):
            a = read_mfw(cp)
            deps = set() if atomic else {tuple(x) for x in json.load(open(depf))}
            if path.startswith("BOARD:"):
                deps = {tuple(json.loads(path.split(":", 2)[1]))}
            elif atomic:
                deps = {("atom", path)}
            self.file_memo[path] = a
            self.deps_file[path] = deps
            self._note(deps)
            return a
        self.active.append(path)
        self.dep_stack.append(set())
        ok = False
        try:
            if path.startswith("BOARD:"):
                _, key, bpath = path.split(":", 2)
                key = tuple(json.loads(key))
                a = G.clean(load_board_alg(bpath, key))
                self.dep_stack[-1].add(key)
                d = {"m": self.board.get(key, (None,))[0]}
            elif is_stub(self.src.load(path)):
                d = self.src.load(path)
                if "lineage" not in d or d["lineage"] is None:
                    raise ReplayError("stub without lineage " + path)
                a = self.replay(d["lineage"])
                want = tuple(d["n"])
                if a.shape != want:
                    o = G.orient_as(a, want)
                    if o is None:
                        raise ReplayError("%s replayed to %r, declared %r" % (path, a.shape, want))
                    a = o
                a = G.clean(a)
            else:
                d = self.src.load(path)
                a = G.clean(load_atom_json(d))
                self.dep_stack[-1].add(("atom", path))
            if not G.check_exact(a):
                raise ReplayError("GF(2) verification failed for " + path)
            # The disk cache stores sorted terms and the constructions above index terms by position, so a
            # freshly computed scheme must carry the same order a cache hit would: otherwise a result depends
            # on which files an earlier replay in the same cache had already materialized.
            a = Alg(a.n, a.m, a.p, sorted(a.terms))
            log("materialized", path, a, "declared", d.get("m"))
            self.file_memo[path] = a
            deps = self.dep_stack[-1]
            self.deps_file[path] = set(deps)
            if self.disk:
                write_mfw(cp, a)
                if not atomic:
                    with open(depf + ".tmp", "w") as fh:
                        json.dump(sorted(deps, key=json.dumps), fh)
                    os.replace(depf + ".tmp", depf)
            ok = True
            return a
        except (ReplayError, ValueError, KeyError, TypeError, IndexError, AssertionError) as e:
            err = e if isinstance(e, ReplayError) else ReplayError("%s: %s: %r" % (path, type(e).__name__, e))
            self.file_memo[path] = err
            raise err
        finally:
            self.active.pop()
            deps = self.dep_stack.pop()
            if ok:
                self._note(deps)

    # ---- best at shape
    def candidates(self, key):
        c = [e for e in self.src.by_key.get(key, [])
             if "F2" in e["fields"] or (self.allow_nonf2 and not e.get("commutative") and e["fields"])]
        if self.use_board and key in self.board:
            r, p = self.board[key]
            c.append({"rank": r, "atom": True, "file": "BOARD:%s:%s" % (json.dumps(list(key)), p)})
        c.sort(key=lambda e: (e["rank"], e["file"].startswith("BOARD:"), not e["atom"], e["file"]))
        return c

    def best_rank(self, shape):
        key = tuple(sorted(shape))
        if key[0] == 0:
            return 0
        if key in self.best_memo:
            a = self.best_memo[key]
            return a.r if a is not None else None
        naive_r = key[0] * key[1] * key[2]
        if key[0] == 1:
            return naive_r
        c = self.candidates(key)
        return min([naive_r] + [e["rank"] for e in c])

    def best(self, shape):
        shape = tuple(shape)
        key = tuple(sorted(shape))
        if key in self.best_memo:
            a = self.best_memo[key]
            self._note(self.deps_best.get(key, set()))
            return None if a is None else G.orient_as(a, shape)
        naive_r = key[0] * key[1] * key[2]
        if key[0] == 1:
            a = G.naive(*key)
            self.best_memo[key] = a
            return G.orient_as(a, shape)
        cands = self.candidates(key)
        best = None
        best_deps = set()
        for idx, e in enumerate(cands):
            if best is not None and best.r <= e["rank"]:
                break
            if e["rank"] >= naive_r:
                break
            self.dep_stack.append(set())
            try:
                a = self.materialize_file(e["file"])
            except ReplayError as ex:
                log("best", key, "candidate failed", e["file"], str(ex)[:300])
                continue
            finally:
                deps = self.dep_stack.pop()
            if best is None or a.r < best.r:
                best, best_deps = a, deps
                if not e["file"].startswith("BOARD:") and "F2" not in e["fields"]:
                    best_deps = deps | {("nonf2",) + key}
        if best is None or best.r > naive_r:
            best, best_deps = G.naive(*key), set()
        self.best_memo[key] = best
        self.deps_best[key] = best_deps
        self._note(best_deps)
        return G.orient_as(best, shape)

    # ---- leaf refs
    SHAPE_REF = re.compile(r"(?:(naive|direct)-)?(\d+)x(\d+)x(\d+)(?:-(direct|naive))?")

    def file_by_basename(self, base):
        stem = base[:-5] if base.endswith(".json") else base
        fs = self.src.by_stem.get(stem)
        if not fs:
            raise ReplayError("no file for " + base)
        return fs[0]

    def resolve_leaf(self, ref):
        at = ref.find("@")
        if at > 0:
            shp, h = ref[:at], ref[at + 1:]
            m = self.SHAPE_REF.fullmatch(shp)
            if m:
                shape = tuple(int(m.group(i)) for i in (2, 3, 4))
                key = tuple(sorted(shape))
                cands = []
                for f in self.src.by_h7.get(h[:7], []):
                    mm = re.match(r".*/(\d+)x(\d+)x(\d+)-", f)
                    if tuple(sorted(int(x) for x in mm.groups())) == key:
                        cands.append(f)
                if not cands:
                    raise ReplayError("pinned ref %s does not resolve" % ref)
                a = self.materialize_file(cands[0])
                o = G.orient_as(a, shape)
                if o is None:
                    raise ReplayError("cannot orient " + ref)
                return o
        # named pool labels
        mext = re.fullmatch(r"ext\[([^\]]+)\](?: / <(\d+),(\d+),(\d+)>=(\d+))?(?: :: (\S+))?", ref)
        if mext:
            a = self.materialize_file(self.file_by_basename(mext.group(1)))
            if mext.group(2):
                want = tuple(int(mext.group(i)) for i in (2, 3, 4))
                for alg, perm in G.s3_orbit_with_perms(a):
                    if alg.shape == want:
                        a = alg
                        break
                else:
                    raise ReplayError("ext orient failed " + ref)
            mode = mext.group(6)
            if mode not in (None, "CANONICAL"):
                raise ReplayError("unsupported pool orbit mode " + ref)
            return a
        mnamed = re.fullmatch(r"(\w+)<(\d+),(\d+),(\d+)>=(\d+)(?: / <(\d+),(\d+),(\d+)>=(\d+))?(?: :: (\S+))?", ref)
        if mnamed:
            name = mnamed.group(1)
            shape = tuple(int(mnamed.group(i)) for i in (2, 3, 4))
            r = int(mnamed.group(5))
            mode = mnamed.group(10)
            if mode not in (None, "CANONICAL"):
                raise ReplayError("unsupported pool orbit mode " + ref)
            if name in ("AxisSplit", "Naive"):
                a = G.naive(*shape)
            else:
                token = {"AE": "alphaevolve", "AT": "alphatensor", "Strassen": "strassen",
                         "Winograd": "winograd", "Laderman": "laderman", "Smirnov": "smirnov",
                         "Sedoglavic": "perminov"}.get(name, name.lower())
                key = tuple(sorted(shape))
                files = [f for (rr, f) in self.src.by_sorted.get(key, []) if rr == r]
                files.sort(key=lambda f: (token not in os.path.basename(f).lower(), f))
                if not files:
                    raise ReplayError("named base not found " + ref)
                a = None
                for f in files:
                    try:
                        a = self.materialize_file(f)
                        break
                    except ReplayError:
                        continue
                if a is None:
                    raise ReplayError("named base unusable " + ref)
                a = G.orient_as(a, shape)
            if mnamed.group(6):
                want = tuple(int(mnamed.group(i)) for i in (6, 7, 8))
                for alg, perm in G.s3_orbit_with_perms(a):
                    if alg.shape == want:
                        a = alg
                        break
                else:
                    raise ReplayError("named orient failed " + ref)
            return a
        stem = ref[:-5] if ref.endswith(".json") else ref
        if stem in self.src.by_stem:
            return self.materialize_file(self.src.by_stem[stem][0])
        m = self.SHAPE_REF.fullmatch(ref)
        if m:
            shape = tuple(int(m.group(i)) for i in (2, 3, 4))
            if m.group(1) or m.group(5) == "naive" or 1 in shape:
                return G.naive(*shape)
            b = self.best(shape)
            if b is None:
                raise ReplayError("no scheme for " + ref)
            return b
        mp = re.fullmatch(r"(DIS09Lemma4|TA_lita|TA_sz)\(n=(\d+)\)", ref)
        if mp:
            raise ReplayError("parametric constructor leaf unsupported: " + ref)
        mx = re.search(r"(\d+)x(\d+)x(\d+)", ref) or re.search(r"<\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*>", ref)
        if mx:
            shape = tuple(int(x) for x in mx.groups())
            if 1 in shape:
                return G.naive(*shape)
            b = self.best(shape)
            if b is None:
                raise ReplayError("no scheme for " + ref)
            log("fallback shape resolution for ref", ref)
            return b
        raise ReplayError("cannot resolve leaf ref " + ref)

    # ---- lineage
    def replay(self, root):
        # parse ids in document order, like SchemeIO.parseLineageNode
        idmap = {}

        def reg(node):
            if isinstance(node, dict):
                if node.get("op") == "@ref":
                    tgt = idmap.get(node.get("id"))
                    if tgt is None:
                        raise ReplayError("dangling @ref " + str(node.get("id")))
                    return tgt
                out = {}
                for k, v in node.items():
                    out[k] = reg(v)
                if node.get("id"):
                    idmap[node["id"]] = out
                return out
            if isinstance(node, list):
                return [reg(v) for v in node]
            return node
        tree = reg(root)
        memo = {}
        return self._rep(tree, memo)

    def _rep(self, node, memo):
        k = id(node)
        if k in memo:
            return memo[k]
        out = self._rep_op(node, memo)
        memo[k] = out
        return out

    def _rep_op(self, nd, memo):
        op = nd.get("op")
        R = lambda x: self._rep(x, memo)
        if op in ("Atom", "Leaf"):
            return self.resolve_leaf(nd["ref"])
        if op == "KronProduct":
            return G.kron(R(nd["outer"]), R(nd["inner"]))
        if op == "KronChain":
            fs = nd["factors"]
            acc = R(fs[0])
            for f in fs[1:]:
                acc = G.kron(acc, R(f))
            return acc
        if op in ("ConcatCols", "ConcatRight"):
            return G.concat_cols(R(nd["left"]), R(nd["right"]))
        if op in ("ConcatRows", "ConcatBelow"):
            return G.concat_rows(R(nd["top"]), R(nd["bottom"]))
        if op == "SumInner":
            return G.concat_inner_r(R(nd["left"]), R(nd["right"]))
        if op == "Transpose":
            child = R(nd["child"])
            perm = nd.get("perm", "")
            ex = G.permute_axes(child, perm)
            if ex is not None:
                return ex
            arrow = perm.find("->")
            if arrow < 0:
                return child
            src = {"N": child.n, "M": child.m, "P": child.p, "A": child.n, "B": child.m, "C": child.p}
            tgt = perm[arrow + 2:]
            try:
                want = (src[tgt[0]], src[tgt[1]], src[tgt[2]])
            except (KeyError, IndexError):
                return child
            return G.orient_as(child, want) or child
        if op == "OrientAs":
            child = R(nd["child"])
            if nd.get("axisMap"):
                perm = ["nmp".index(ch) for ch in nd["axisMap"]]
                return G.orient_by_perm(child, perm)
            o = G.orient_as(child, (nd["n"], nd["m"], nd["p"]))
            if o is None:
                raise ReplayError("OrientAs failed")
            return o
        if op == "AxisPermute":
            return G.axis_permute(R(nd["child"]), nd["permA"], nd["permB"], nd["permC"])
        if op == "DCE":
            return G.clean(R(nd["child"]))
        if op == "Project":
            return G.project(R(nd["child"]), nd["keepN"], nd["keepM"], nd["keepP"])
        if op == "SerendipitousProduct":
            base = G.clean(R(nd["base"]))
            return G.serendipitous(base, nd["n2"], nd["m2"], nd["p2"], self._resolve_inner, self.best_rank)
        if op in ("Recombination", "RecombinationN"):
            return self._recomb(nd, memo)
        raise ReplayError("unsupported op " + str(op))

    def _resolve_inner(self, shape):
        if 1 in shape:
            return G.naive(*shape)
        return self.best(shape)

    def _recomb(self, nd, memo):
        base = G.clean(self._rep(nd["base"], memo))
        aA, aB, aC = nd["allocA"], nd["allocB"], nd["allocC"]
        want = (len(aA), len(aB), len(aC))
        if base.shape != want:
            o = G.orient_as(base, want)
            if o is not None:
                base = o
        leaves = nd.get("leaves") or []
        leaf_cache = {}

        def leaf_for(key):
            if key in leaf_cache:
                return leaf_cache[key]
            found = None
            for lf in leaves:
                try:
                    a = self._rep(lf, memo)
                except ReplayError as e:
                    log("recomb leaf failed", str(e)[:200])
                    continue
                if tuple(sorted(a.shape)) == key and (found is None or a.r < found.r):
                    found = a
            leaf_cache[key] = found
            return found

        def sub_lookup(sz):
            sz = tuple(sz)
            if 1 in sz:
                return G.naive(*sz)
            key = tuple(sorted(sz))
            b = self.best(sz)
            lf = None
            if b is None or b.r >= key[0] * key[1] * key[2] or os.environ.get("MMC_RECORDED_LEAVES"):
                lf = leaf_for(key)
            if lf is not None and (b is None or lf.r < b.r):
                return G.orient_as(G.clean(lf), sz)
            return b
        return G.recombination(base, aA, aB, aC, sub_lookup)
