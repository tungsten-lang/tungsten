"""flipfleet — an exact-gated, persistent-island flip-graph search for GF(2)
matrix multiplication, with a live TUI and per-new-best benchmarking.

The default ``islands`` strategy keeps independent walkers alive across global
improvements and migrates only one quarter of them on a strict rank drop.  Every
candidate is exact tensor-verified before adoption, every distinct frontier
snapshot observed by the coordinator is atomically archived, and cycle-outs draw from that diversity archive
or the original start.  ``independent`` disables migration; ``converge`` retains
the old reseed-everyone policy for controlled comparisons.

The dimensions, record, initial scheme, plus-axis policy, migration policy, and
optional exact escape-seed policy are runtime options.  ``--seed record``
selects the sparsest tracked exact record for square sizes 3 through 6;
``--seed c3-record`` selects the C3 frontier for sizes 5 and 6.  The
generated Tungsten walker uses random-axis plus transitions by default;
``--plus-axes w`` restores the historical policy.  ``--escape-kind`` injects
one exact split/polarization excursion into a deterministic subset of startup
and/or genuine cycle-out launches without replacing the coordinator's frontier.

BENCHMARK: every new fleet best is scored for ACTUAL work, not just rank —
  ops = bits - rank - outputs  (base-case GF(2) op count, mults+adds)
  omega = log_n(rank)          (asymptotic recursion exponent)
so you can see whether descending rank is climbing or sliding the performance curve.

HOOKS: the search continuously writes <run_dir>/status.json and events.log. The
built-in curses TUI renders them; any other tool (or an agent) can read the same
files to watch progress.

Usage:
  python3 flipfleet.py --size 3 --walkers 12 --secs 60
  python3 flipfleet.py --size 5 --seed record --strategy islands --tui
  python3 flipfleet.py --size 4 --seed record --escape-kind split
  python3 flipfleet.py --size 5 --seed c3-record --escape-kind orbit-split
  python3 flipfleet.py --attach <run_dir>                    # TUI only, attach to a run
"""
import argparse
import fnmatch
import glob
import hashlib
import json
import math
import os
import random
import re
import subprocess
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, "benchmarks", "matmul", "zoo"))
from bench_decomp import cost, parse_scheme, naive_scheme, verify  # noqa: E402
from bucket_gen import gen as bucket_gen  # noqa: E402
from gpu_cal2zone_gen import gen as gpu_cal2zone_gen  # noqa: E402
from sym_escape import (best_bridge, bridge_error, describe as describe_escape,
                        is_c3_closed)  # noqa: E402

CAP_MOVES = 50_000_000_000_000          # INTEGER — a float cap emits a float literal and nan-boxes
KNOWN_RECORDS = {3: 23, 4: 47, 5: 93, 6: 153}
RECORD_SEEDS = {
    3: os.path.join(ROOT, "benchmarks", "matmul", "search", "scheme23.txt"),
    4: os.path.join(HERE, "matmul_4x4_rank47_d450_gf2.txt"),
    5: os.path.join(HERE, "matmul_5x5_rank93_d1155_gf2.txt"),
    6: os.path.join(HERE, "matmul_6x6_rank153_d2512_gf2.txt"),
}
C3_RECORD_SEEDS = {
    # The GPU density leader returned to a C3-closed frontier with three fixed
    # cubes, so it is eligible for both ordinary and symmetric escapes.
    5: RECORD_SEEDS[5],
    # The GPU density leader is not required to remain C3-closed; retain the
    # original symmetry-compatible rank-153 seed for orbit escapes.
    6: os.path.join(ROOT, "benchmarks", "matmul", "search", "seed_mp153.txt"),
}
ESCAPE_KINDS = ("none", "split", "break", "orbit-split", "polarize")
ESCAPE_TRIGGERS = ("startup", "cycleout", "both")
ESCAPE_MAX_DELTA = {"none": 0, "split": 1, "break": 1,
                    "orbit-split": 5, "polarize": 7}


# ---- scheme IO --------------------------------------------------------------
def write_dump(terms, path):
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        f.write(f"{len(terms)}\n")
        for u, v, w in terms:
            f.write(f"{u} {v} {w}\n")
    os.replace(tmp, path)                 # atomic — no torn reads by the walker


def read_dump(path):
    try:
        with open(path) as f:
            lines = f.read().splitlines()
        # Native GPU relays append density on the header (`rank density`),
        # while CPU/archival dumps use only `rank`.
        header = lines[0].split()
        if not header or len(header) > 2:
            return None, None
        rank = int(header[0])
        if rank < 0:
            return None, None
        rows = [ln.split() for ln in lines[1:1 + rank]]
        if len(rows) != rank or any(len(row) != 3 for row in rows):
            return None, None
        terms = [tuple(int(x) for x in row) for row in rows]
        return (rank, terms) if len(terms) == rank else (None, None)
    except Exception:
        return None, None


def tail_has(path, needle, n=256):
    try:
        with open(path) as f:
            return any(needle in ln for ln in f.read().splitlines()[-n:])
    except Exception:
        return False


def normalize_terms(terms):
    """Apply the benchmark's GF(2) zero/duplicate semantics to an input file."""
    out = set()
    for term in terms:
        term = tuple(term)
        if not all(term):
            continue
        out.discard(term) if term in out else out.add(term)
    return sorted(out)


def parse_move_budgets(spec):
    """Parse comma-separated move counts with optional k/m/b suffixes."""
    scales = {"k": 1_000, "m": 1_000_000, "b": 1_000_000_000}
    budgets = []
    try:
        for raw in spec.split(","):
            token = raw.strip().lower().replace("_", "")
            if not token:
                raise ValueError("empty move budget")
            scale = scales.get(token[-1], 1)
            number = token[:-1] if token[-1] in scales else token
            value = int(float(number) * scale)
            if value <= 0:
                raise ValueError("move budgets must be positive")
            budgets.append(value)
    except (ValueError, OverflowError) as exc:
        raise argparse.ArgumentTypeError(f"invalid move-budget list {spec!r}: {exc}")
    return tuple(budgets)


def validate_format(n, m, p):
    if any(not isinstance(value, int) or value <= 0 for value in (n, m, p)):
        raise ValueError("matrix dimensions must be positive integers")
    widths = (n * m, m * p, n * p)
    if any(width >= 63 for width in widths):
        raise ValueError("each factor mask must use fewer than 63 signed-i64 bits")


def terms_in_bounds(terms, n, m, p):
    limits = (1 << (n * m), 1 << (m * p), 1 << (n * p))
    return (len(set(terms)) == len(terms) and
            all(len(term) == 3 and
                all(isinstance(mask, int) and 0 < mask < limit
                    for mask, limit in zip(term, limits))
                for term in terms))


def looks_like_legacy_run(run_dir, entries):
    """Recognize pre-marker FlipFleet directories without guessing from names.

    Cleanup is destructive for known run artifacts, so a lone generic filename
    such as ``status.json`` is not sufficient evidence of ownership.  Genuine
    pre-marker runs have all three anchors below, a status document with the
    fleet schema, the startup event, and generated walker source containing the
    cycle-out protocol.
    """
    required = {"status.json", "events.log", "walker.w"}
    if not required.issubset(entries):
        return False
    try:
        with open(os.path.join(run_dir, "status.json")) as stream:
            status = json.load(stream)
        with open(os.path.join(run_dir, "events.log")) as stream:
            events = stream.read(1_000_000)
        with open(os.path.join(run_dir, "walker.w")) as stream:
            walker = stream.read(1_000_000)
    except (OSError, ValueError, TypeError):
        return False
    return (isinstance(status, dict) and
            isinstance(status.get("format"), str) and
            status.get("strategy") in ("islands", "independent", "converge") and
            isinstance(status.get("walkers"), list) and
            "flipfleet start:" in events and
            "CYCLEOUT" in walker)


# ---- the search fleet -------------------------------------------------------
class Fleet:
    OWNED_FILES = (
        "status.json", "status.json.tmp", "events.log", "perf_curve.csv",
        "best.txt", "WORLD_RECORD.txt", "walker", "walker.w", "walker.sidemap",
        "best.txt.tmp", "WORLD_RECORD.txt.tmp", "cpu_*.txt", "cpu_*.txt.tmp",
        "cpu_*.log", "reseed_*.txt", "reseed_*.txt.tmp",
        "gpu_best.txt", "gpu_best.txt.tmp", "gpu_relay", "gpu_relay.w",
        "gpu_relay.ll", "gpu_relay.metal", "gpu_relay.sidemap", "gpu_relay.log",
    )

    def __init__(self, run_dir, nwalkers, secs, n=5, m=5, p=5, record=93,
                 initial_terms=None, strategy="islands", cycles=4, migrate=None,
                 archive_reseed=0.75, archive_size=256, plus_axes="any",
                 stop_on_record=False, record_band_moves=None,
                 escape_kind="none", escape_at="both", escape_every=2,
                 escape_part=None, gpu=False, gpu_escapes=256,
                 gpu_walkers=4096, gpu_steps=500_000):
        validate_format(n, m, p)
        if not isinstance(nwalkers, int) or nwalkers <= 0:
            raise ValueError("nwalkers must be positive")
        if not isinstance(secs, int) or secs < 0:
            raise ValueError("secs must be a nonnegative integer")
        if not isinstance(cycles, int) or cycles <= 0:
            raise ValueError("cycles must be positive")
        if not isinstance(record, int) or record <= 0:
            raise ValueError("record must be positive")
        if not math.isfinite(archive_reseed) or not 0.0 <= archive_reseed <= 1.0:
            raise ValueError("archive_reseed must be finite and between 0 and 1")
        if not isinstance(archive_size, int) or archive_size <= 0:
            raise ValueError("archive_size must be positive")
        if migrate is not None and (not isinstance(migrate, int) or
                                    not 0 <= migrate <= nwalkers):
            raise ValueError("migrate must be between zero and nwalkers")
        if strategy not in ("islands", "independent", "converge"):
            raise ValueError("unknown fleet strategy")
        if plus_axes not in ("w", "any"):
            raise ValueError("plus_axes must be 'w' or 'any'")
        if escape_kind not in ESCAPE_KINDS:
            raise ValueError(f"escape_kind must be one of {ESCAPE_KINDS}")
        if escape_at not in ESCAPE_TRIGGERS:
            raise ValueError(f"escape_at must be one of {ESCAPE_TRIGGERS}")
        if not isinstance(escape_every, int) or escape_every <= 0:
            raise ValueError("escape_every must be positive")
        if escape_kind != "none" and not (n == m == p):
            raise ValueError("escape moves currently require a square format")
        if escape_part is not None:
            if escape_kind == "none":
                raise ValueError("escape_part requires an enabled escape_kind")
            if (not isinstance(escape_part, int) or escape_part <= 0 or
                    escape_part >= (1 << (n * n))):
                raise ValueError("escape_part must fit the nonzero square factor mask")
        if not isinstance(gpu_escapes, int) or gpu_escapes <= 0:
            raise ValueError("gpu_escapes must be positive")
        if not isinstance(gpu_walkers, int) or gpu_walkers <= 0:
            raise ValueError("gpu_walkers must be positive")
        if not isinstance(gpu_steps, int) or gpu_steps <= 0:
            raise ValueError("gpu_steps must be positive")
        self.dir = run_dir
        self.nw = nwalkers
        self.secs = secs
        self.n, self.m, self.p = n, m, p
        self.strategy = strategy
        self.cycles = cycles            # sawtooth cycles before a walker CYCLEOUTs -> reseed
        self.world_record = record
        self.configured_record = record
        source_terms = naive_scheme(n, m, p) if initial_terms is None else initial_terms
        self.initial = normalize_terms(source_terms)
        self.migrate = max(1, nwalkers // 4) if migrate is None else max(0, migrate)
        self.archive_reseed = archive_reseed
        self.archive_size = archive_size
        self.plus_axes = plus_axes
        self.stop_on_record = stop_on_record
        self.escape_kind = escape_kind
        self.escape_at = escape_at
        self.escape_every = escape_every
        self.escape_part = escape_part
        self.escape_considered = 0
        self.escape_applied = 0
        self.escape_bypassed = 0
        self.escape_skipped = 0
        self.escape_cache = {}
        self.gpu = gpu
        self.gpu_escapes = gpu_escapes
        self.gpu_walkers = gpu_walkers
        self.gpu_steps = gpu_steps
        self.gpu_proc = None
        self.gpu_log = None
        self.gpu_invalid_digest = None
        self.gpu_exit_reported = False
        default_bands = (250_000_000, 1_000_000_000, 10_000_000_000)
        bands = default_bands if record_band_moves is None else tuple(record_band_moves)
        if not bands or any(not isinstance(value, int) or value <= 0 for value in bands):
            raise ValueError("record_band_moves must contain positive integers")
        self.record_band_moves = bands
        self.record = os.path.join(run_dir, "records")
        self.spool = os.path.join(run_dir, "spool")
        os.makedirs(run_dir, exist_ok=True)
        self.owner_path = os.path.join(run_dir, ".flipfleet-owned")
        self.lock_path = os.path.join(run_dir, ".flipfleet-active")
        entries = os.listdir(run_dir)
        if not os.path.exists(self.owner_path):
            allowed = all(name in ("records", "spool", ".flipfleet-active") or
                          any(fnmatch.fnmatch(name, pattern)
                              for pattern in self.OWNED_FILES)
                          for name in entries)
            legacy_signature = looks_like_legacy_run(run_dir, set(entries))
            if entries and not (allowed and legacy_signature):
                raise ValueError(f"refusing nonempty unowned run directory: {run_dir}")
            with open(self.owner_path, "x") as stream:
                stream.write("flipfleet-v2\n")
        os.makedirs(self.record, exist_ok=True)
        os.makedirs(self.spool, exist_ok=True)
        self.status_path = os.path.join(run_dir, "status.json")
        self.events_path = os.path.join(run_dir, "events.log")
        self.curve_path = os.path.join(run_dir, "perf_curve.csv")
        self.events = []
        self.perf = []
        self.best = None                  # (rank, terms)
        self.archive = {}                 # canonical scheme -> terms, current best rank only
        self.archive_sets = {}            # canonical scheme -> frozenset, for distances
        self.archive_uses = {}            # canonical scheme -> number of cycle-out reseeds
        self.recorded = set()              # all distinct schemes durably written this run
        self.validated = {}               # canonical scheme -> exact validation result
        self.spool_seen = set()            # completely-read tie/beat snapshots
        self.spool_invalid = {}            # path -> (content digest, stable polls)
        self.invalid_dumps = {}            # walker -> (content digest, consecutive polls)
        self.reseeds = 0
        self.naive_wraps = 0
        self.frontier_wraps = 0
        self.invalid_candidates = 0
        self.record_hits = 0
        self.new_bests = 0
        self.tie_improvements = 0
        self.archive_evictions = 0
        self.archive_rejections = 0
        self.archive_min_distance = None
        self.archive_closest_pair = None
        self.archive_hydrated = 0
        self.recovered_rank = None
        self.error = None
        self.last_converge = 0.0
        self.procs = [None] * (nwalkers + 1)
        self.logs = {}
        self.launched_at = [0.0] * (nwalkers + 1)
        self.reseeded_at = [0.0] * (nwalkers + 1)
        self.launch_count = [0] * (nwalkers + 1)
        self.stop_requested = threading.Event()
        self.run_prepared = threading.Event()
        self.lock_token = f"{os.getpid()}:{id(self)}"
        self.lock_owned = False

    @staticmethod
    def _pid_alive(pid):
        try:
            os.kill(pid, 0)
            return True
        except ProcessLookupError:
            return False
        except PermissionError:
            return True

    def acquire_lock(self):
        for _ in range(3):
            try:
                fd = os.open(self.lock_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
                try:
                    os.write(fd, (self.lock_token + "\n").encode())
                finally:
                    os.close(fd)
                self.lock_owned = True
                return
            except FileExistsError:
                try:
                    with open(self.lock_path) as stream:
                        token = stream.read().strip()
                    pid = int(token.split(":", 1)[0])
                except (OSError, ValueError):
                    pid = -1
                if pid > 0 and self._pid_alive(pid):
                    raise RuntimeError(f"run directory is active (pid {pid}): {self.dir}")
                try:
                    os.remove(self.lock_path)
                except FileNotFoundError:
                    pass
        raise RuntimeError(f"could not acquire run-directory lock: {self.dir}")

    def release_lock(self):
        if not self.lock_owned:
            return
        try:
            with open(self.lock_path) as stream:
                token = stream.read().strip()
            if token == self.lock_token:
                os.remove(self.lock_path)
        except FileNotFoundError:
            pass
        finally:
            self.lock_owned = False

    def prepare_run(self):
        self.acquire_lock()
        try:
            for pattern in self.OWNED_FILES:
                for path in glob.glob(os.path.join(self.dir, pattern)):
                    if os.path.isfile(path):
                        os.remove(path)
            for path in glob.glob(os.path.join(self.spool, "*")):
                if os.path.isfile(path):
                    os.remove(path)
        except Exception:
            self.release_lock()
            raise

    def log(self, msg):
        line = f"[{time.strftime('%H:%M:%S')}] {msg}"
        self.events.append(line)
        self.events = self.events[-40:]
        with open(self.events_path, "a") as f:
            f.write(line + "\n")

    def reseed_file(self, i):
        return os.path.join(self.dir, f"reseed_{i}.txt")

    def dump_file(self, i):
        return os.path.join(self.dir, f"cpu_{i}.txt")

    def build_walker(self):
        binp = os.path.join(self.dir, "walker")
        src = bucket_gen(self.n, self.m, self.p, self.world_record - 1,
                         seed=None, cap=CAP_MOVES,
                         arr=len(self.initial) + max(80, ESCAPE_MAX_DELTA[self.escape_kind] + 8),
                         adaptive_esc="cal2zone2", band=1, thr0=7,
                         world_record=self.world_record, tiegap=20000,
                         record_bandq=self.record_band_moves[-1], runtime_seed=True,
                         plus_axes=self.plus_axes)
        open(binp + ".w", "w").write(src)
        r = subprocess.run(["bin/tungsten", "-o", binp, binp + ".w",
                            "--release", "--native", "--fast", "--lto"],
                           cwd=ROOT, capture_output=True, text=True, timeout=1200)
        if r.returncode != 0:
            raise RuntimeError("walker compile failed:\n" + r.stdout + r.stderr)
        self.bin = binp

    def build_gpu_relay(self):
        """Generate and compile the dimension-specialized Tungsten/Metal scout."""
        maxbits = max(self.n * self.m, self.m * self.p, self.n * self.p)
        mask_bytes = 8 if maxbits > 30 else 4
        cap = len(self.initial) + max(32, ESCAPE_MAX_DELTA[self.escape_kind] + 12)
        wpg = 16
        while cap * wpg * mask_bytes * 3 > 32768:
            wpg //= 2
        if wpg < 1:
            raise ValueError("GPU scheme capacity exceeds Metal threadgroup memory")
        nw = self.gpu_walkers - (self.gpu_walkers % wpg)
        if nw <= 0:
            raise ValueError(f"gpu_walkers must be at least the generated WPG ({wpg})")
        self.gpu_walkers = nw
        srcp = os.path.join(self.dir, "gpu_relay.w")
        llp = os.path.join(self.dir, "gpu_relay.ll")
        binp = os.path.join(self.dir, "gpu_relay")
        src, shared_bytes = gpu_cal2zone_gen(
            self.n, self.m, self.p, cap, wpg, cap, llp,
            nw=nw, steps=self.gpu_steps)
        with open(srcp, "w") as stream:
            stream.write(src)
        env = dict(os.environ, TUNGSTEN_LL_PATH=llp)
        result = subprocess.run(
            ["bin/tungsten", "-o", binp, srcp,
             "--release", "--native", "--fast", "--lto"],
            cwd=ROOT, env=env, capture_output=True, text=True, timeout=1200)
        if result.returncode != 0:
            hint = ""
            if maxbits > 30:
                hint = ("\n6x6 requires the new gpu.shared_i64 and Metal i64-buffer "
                        "runtime support; rebuild the Tungsten compiler first.")
            raise RuntimeError("GPU relay compile failed:\n" + result.stdout +
                               result.stderr + hint)
        self.gpu_bin = binp
        self.log(f"GPU relay compiled ({maxbits}-bit factors, WPG={wpg}, "
                 f"shared={shared_bytes}/32768B, escapes={self.gpu_escapes})")

    def launch_gpu_relay(self):
        best_path = os.path.join(self.dir, "best.txt")
        out_path = os.path.join(self.dir, "gpu_best.txt")
        open(out_path, "w").close()
        self.gpu_log = open(os.path.join(self.dir, "gpu_relay.log"), "w")
        # Positional slots mirror flipgraph_gpu_cal2zone.w.  The empty live
        # params path occupies argv[14]; argv[15] is the exact escape portfolio.
        argv = [
            self.gpu_bin, best_path, out_path,
            str(self.n), str(self.m), str(self.p), "x", "0",
            str(self.gpu_steps), "200", "4", "150000", "60000", "7",
            str(self.gpu_walkers), "", str(self.gpu_escapes),
        ]
        self.gpu_proc = subprocess.Popen(
            argv, cwd=ROOT, stdout=self.gpu_log, stderr=subprocess.STDOUT)
        self.log(f"GPU escape scout launched: {self.gpu_walkers} lanes across "
                 f"{self.gpu_escapes} exact split basins")

    def gpu_candidate(self, max_rank):
        if not self.gpu:
            return None
        if (self.gpu_proc is not None and self.gpu_proc.poll() is not None and
                not self.gpu_exit_reported):
            self.gpu_exit_reported = True
            self.log(f"GPU relay exited with status {self.gpu_proc.returncode}; "
                     f"see gpu_relay.log")
        path = os.path.join(self.dir, "gpu_best.txt")
        rank, terms = read_dump(path)
        if rank is None or rank > max_rank:
            return None
        if self.exact_valid(rank, terms):
            self.gpu_invalid_digest = None
            return rank, 0, terms, "gpu"
        digest = hashlib.sha256(repr((rank, terms)).encode()).hexdigest()
        if digest != self.gpu_invalid_digest:
            self.gpu_invalid_digest = digest
            self.invalid_candidates += 1
            self.log(f"REJECTED invalid rank={rank} from GPU")
        return None

    def launch(self, i, salt, seed):
        if i in self.logs:
            try:
                self.logs[i].close()
            except Exception:
                pass
        self.launch_count[i] += 1
        launch_id = self.launch_count[i]
        active_log = os.path.join(self.dir, f"cpu_{i}.log")
        if os.path.exists(active_log) and os.path.getsize(active_log):
            prior_log = os.path.join(self.dir, f"cpu_{i}_l{launch_id - 1}.log")
            os.replace(active_log, prior_log)
        # A worker only dumps on a strict personal improvement.  Publish the
        # seed ourselves so coordinator ranking can never inherit the previous
        # process's stale personal best.
        write_dump(seed, self.dump_file(i))
        # The generated runtime-seed loader reads argv[4], which is this file.
        # Keeping it in launch() makes the selected escape/base seed the single
        # source of truth for every launch reason.
        write_dump(seed, self.reseed_file(i))
        lf = open(active_log, "w")
        self.logs[i] = lf
        record_band_moves = self.record_band_moves[(i - 1) % len(self.record_band_moves)]
        self.procs[i] = subprocess.Popen(
            [self.bin, str(i * 97 + 13 + salt * 100003), self.dump_file(i),
             os.path.join(self.spool, f"cpu{i}l{launch_id}"),
             os.path.join(self.spool, f"tie{i}l{launch_id}"),
             self.reseed_file(i), str(self.cycles), str(record_band_moves)],
            stdout=lf, stderr=subprocess.STDOUT)
        self.launched_at[i] = time.time()
        self.reseeded_at[i] = time.time()

    def drain_spool(self, max_rank):
        """Return newly completed exact tie/beat snapshots at or below max_rank.

        The generated worker deliberately writes same-rank density improvements
        separately from its strict-personal-best dump.  A failed structural read
        is retried on the next poll because the native write may still be in
        flight; a structurally complete file is consumed exactly once.
        """
        candidates = []
        for path in sorted(glob.glob(os.path.join(self.spool, "*.txt"))):
            if path in self.spool_seen:
                continue
            rank, terms = read_dump(path)
            if rank is None:
                continue
            if rank > max_rank:
                self.spool_seen.add(path)
                self.spool_invalid.pop(path, None)
                continue
            name = os.path.basename(path)
            match = re.match(r"(?:cpu|tie)(\d+)(?:l\d+)?_", name)
            walker = int(match.group(1)) if match else -1
            if self.exact_valid(rank, terms):
                self.spool_seen.add(path)
                self.spool_invalid.pop(path, None)
                candidates.append((rank, walker, terms, f"spool/{name}"))
            else:
                # Native write_file is not atomic.  A cutoff inside the final
                # number can look structurally complete, so retry unless the
                # identical invalid content survives two coordinator polls.
                digest = hashlib.sha256(repr((rank, terms)).encode()).hexdigest()
                prior_digest, prior_count = self.spool_invalid.get(path, (None, 0))
                count = prior_count + 1 if digest == prior_digest else 1
                self.spool_invalid[path] = (digest, count)
                if count >= 2:
                    self.spool_seen.add(path)
                    self.spool_invalid.pop(path, None)
                    self.invalid_candidates += 1
                    self.log(f"REJECTED stable invalid rank={rank} from spool/{name}")
        return candidates

    def stop_process(self, i):
        pr = self.procs[i]
        if pr and pr.poll() is None:
            pr.kill()
            try:
                pr.wait(timeout=5)
            except subprocess.TimeoutExpired:
                pr.terminate()
                pr.wait(timeout=5)
        self.procs[i] = None

    def request_stop(self):
        self.stop_requested.set()

    def score(self, rank, terms):
        c = cost(terms, self.n, self.m, self.p)
        return c

    @staticmethod
    def canonical(terms):
        return tuple(sorted(terms))

    @staticmethod
    def scheme_distance(left, right):
        """Term-set symmetric-difference distance between two schemes."""
        return len(left.symmetric_difference(right))

    def _insert_archive(self, key, terms):
        termset = frozenset(terms)
        for existing_key, existing in self.archive_sets.items():
            distance = self.scheme_distance(termset, existing)
            left, right = sorted((key, existing_key))
            pair = (distance, left, right)
            if self.archive_closest_pair is None or pair < self.archive_closest_pair:
                self.archive_closest_pair = pair
                self.archive_min_distance = distance
        self.archive[key] = list(terms)
        self.archive_sets[key] = termset
        self.archive_uses[key] = 0

    def _closest_archive_pair(self):
        keys = list(self.archive)
        closest = None
        for ai, left in enumerate(keys):
            for right in keys[ai + 1:]:
                distance = self.scheme_distance(self.archive_sets[left],
                                                self.archive_sets[right])
                item = (distance, left, right)
                if closest is None or item < closest:
                    closest = item
        return closest

    def _refresh_archive_closest(self):
        self.archive_closest_pair = self._closest_archive_pair()
        self.archive_min_distance = (self.archive_closest_pair[0]
                                     if self.archive_closest_pair else None)

    def _remove_archive(self, key):
        del self.archive[key]
        del self.archive_sets[key]
        del self.archive_uses[key]

    @staticmethod
    def _density(key):
        return sum(bin(u).count("1") + bin(v).count("1") + bin(w).count("1")
                   for u, v, w in key)

    def _admit_diverse(self, key, terms, rank):
        """Maintain an online max-min sample of a potentially unbounded frontier."""
        if len(self.archive) < self.archive_size:
            self._insert_archive(key, terms)
            return True
        candidate_set = frozenset(terms)
        novelty = min(self.scheme_distance(candidate_set, existing)
                      for existing in self.archive_sets.values())
        closest = self.archive_closest_pair
        if closest is None or novelty <= closest[0]:
            self.archive_rejections += 1
            return False
        _, left, right = closest
        protected = (self.canonical(self.best[1])
                     if self.best is not None and self.best[0] == rank else None)
        if left == protected:
            victim = right
        elif right == protected:
            victim = left
        else:
            # At equal rank, retain the sparser member of the closest pair.
            victim = max((left, right), key=lambda item: (self._density(item), item))
        self._remove_archive(victim)
        self.archive_closest_pair = None
        self.archive_min_distance = None
        self._insert_archive(key, terms)
        self._refresh_archive_closest()
        self.archive_evictions += 1
        return True

    def _pin_archive(self, key, terms):
        """Ensure the rank-then-density leader remains a restart candidate."""
        if key in self.archive:
            return
        if len(self.archive) >= self.archive_size:
            victim = max(self.archive, key=lambda item: (self._density(item), item))
            self._remove_archive(victim)
            self.archive_evictions += 1
        self.archive_closest_pair = None
        self.archive_min_distance = None
        self._insert_archive(key, terms)
        self._refresh_archive_closest()

    def exact_valid(self, rank, terms):
        if rank != len(terms) or not terms_in_bounds(terms, self.n, self.m, self.p):
            return False
        key = self.canonical(terms)
        if key not in self.validated:
            self.validated[key] = verify(terms, self.n, self.m, self.p)
        return self.validated[key]

    def escape_enabled_for(self, trigger):
        return (self.escape_kind != "none" and
                (self.escape_at == "both" or self.escape_at == trigger))

    def _compute_escape(self, base):
        """Build, exact-gate, and cache one deterministic escape."""
        key = (self.escape_kind, self.escape_part, self.canonical(base))
        cached = self.escape_cache.get(key)
        if cached is not None:
            return cached
        scheme = set(base)
        output, bridge = best_bridge(
            scheme, self.n, kind=self.escape_kind, part=self.escape_part)
        terms = sorted(output)
        if not self.exact_valid(len(terms), terms):
            raise RuntimeError("generated escape failed exact tensor verification")
        after = describe_escape(output, self.n)
        if (self.escape_kind in ("orbit-split", "polarize") and
                not is_c3_closed(output, self.n)):
            raise RuntimeError("C3-preserving escape lost C3 closure")
        before = describe_escape(scheme, self.n)
        cached = (terms, dict(bridge), before, after)
        self.escape_cache[key] = cached
        return cached

    def prepare_launch_seed(self, base_terms, trigger, strict=False):
        """Optionally turn an exact frontier into one non-recursive excursion.

        The deterministic cadence counts only eligible launch sites.  Returned
        escaped terms are never installed directly as ``initial``/``best``.
        Nominal higher-rank excursions are ignored by frontier admission; if
        parity collisions make a generated seed tie or beat the frontier, its
        published worker dump is exact-gated and adopted normally.
        """
        base = list(base_terms)
        if not self.escape_enabled_for(trigger):
            return base, None
        self.escape_considered += 1
        ordinal = self.escape_considered
        if (ordinal - 1) % self.escape_every != 0:
            self.escape_bypassed += 1
            return base, None
        if not self.exact_valid(len(base), base):
            raise RuntimeError("escape source failed exact tensor verification")

        scheme = set(base)
        error = bridge_error(scheme, self.n, self.escape_kind)
        if error:
            self.escape_skipped += 1
            metadata = {"applied": False, "trigger": trigger,
                        "kind": self.escape_kind, "reason": error,
                        "base_rank": len(base)}
            if strict:
                raise ValueError(f"startup escape is not applicable: {error}")
            return base, metadata

        try:
            terms, bridge, before, after = self._compute_escape(base)
        except ValueError as exc:
            self.escape_skipped += 1
            if strict:
                raise ValueError(f"startup escape is not applicable: {exc}")
            return base, {"applied": False, "trigger": trigger,
                          "kind": self.escape_kind, "reason": str(exc),
                          "base_rank": len(base)}
        self.escape_applied += 1
        digest = hashlib.sha256(repr(self.canonical(base)).encode()).hexdigest()[:12]
        metadata = dict(bridge)
        metadata.update({"applied": True, "trigger": trigger,
                         "base_rank": len(base), "output_rank": len(terms),
                         "base_digest": digest, "before": before, "after": after})
        return list(terms), metadata

    def log_escape(self, walker, metadata):
        if metadata is None:
            return
        if not metadata.get("applied"):
            self.log(f"ESCAPE SKIP {metadata['trigger']} w{walker} "
                     f"kind={metadata['kind']} rank={metadata['base_rank']} "
                     f"reason={metadata['reason']}")
            return
        before, after = metadata["before"], metadata["after"]
        anchor = metadata.get("factor")
        if anchor is None:
            anchor = metadata.get("x")
        self.log(
            f"ESCAPE {metadata['trigger']} w{walker} kind={metadata['kind']} "
            f"rank={metadata['base_rank']}->{metadata['output_rank']} "
            f"fixed={before['fixed']}->{after['fixed']} "
            f"c3={before['c3']}->{after['c3']} "
            f"factor={anchor} part={metadata['part']} axis={metadata['axis']} "
            f"base={metadata['base_digest']} exact={after['exact']}")

    def archive_candidate(self, rank, terms, source="candidate"):
        """Durably retain every distinct exact-valid frontier snapshot received."""
        if not self.exact_valid(rank, terms):
            self.invalid_candidates += 1
            self.log(f"REJECTED invalid rank={rank} from {source}")
            return False
        key = self.canonical(terms)
        if self.best is not None and rank > self.best[0]:
            return True
        if self.best is not None and rank < self.best[0]:
            self.archive.clear()
            self.archive_sets.clear()
            self.archive_uses.clear()
            self.archive_min_distance = None
            self.archive_closest_pair = None
        if key not in self.recorded:
            self.recorded.add(key)
            digest = hashlib.sha256(repr(key).encode()).hexdigest()[:12]
            write_dump(terms, os.path.join(self.record, f"rank{rank}_{digest}.txt"))
        if key not in self.archive:
            self._admit_diverse(key, terms, rank)
        return True

    def hydrate_archive(self, rank):
        """Exact-gate and reuse durable frontier schemes from earlier runs."""
        loaded = 0
        pattern = os.path.join(self.record, f"rank{rank}_*.txt")
        for path in sorted(glob.glob(pattern)):
            stored_rank, terms = read_dump(path)
            if stored_rank != rank or not self.exact_valid(stored_rank, terms):
                continue
            key = self.canonical(terms)
            self.recorded.add(key)
            if key not in self.archive:
                if self._admit_diverse(key, terms, rank):
                    loaded += 1
        self.archive_hydrated += loaded
        if loaded:
            self.log(f"HYDRATE: admitted {loaded} durable rank-{rank} frontier schemes; "
                     f"retained {len(self.archive)}/{self.archive_size}")
        return loaded

    def recover_frontier(self):
        """Recover by rank, then requested escape eligibility, then density."""
        if not self.exact_valid(len(self.initial), self.initial):
            raise ValueError("initial scheme failed exact tensor verification")
        # If the requested profile is eligible for an enabled escape, do not
        # silently replace it with a denser/sparser but ineligible scheme at the
        # same rank, where a lower-density tie may not satisfy the requested
        # symmetry escape profile.
        preserve_escape_profile = (
            self.escape_kind != "none" and
            bridge_error(set(self.initial), self.n, self.escape_kind) is None)
        initial_key = self.canonical(self.initial)
        best = (len(self.initial), 0, self._density(initial_key), initial_key,
                list(self.initial), None)
        for path in sorted(glob.glob(os.path.join(self.record, "rank*_*.txt"))):
            rank, terms = read_dump(path)
            if rank is None or rank > best[0] or not self.exact_valid(rank, terms):
                continue
            candidate_error = (bridge_error(set(terms), self.n, self.escape_kind)
                               if preserve_escape_profile else None)
            if (preserve_escape_profile and candidate_error is None and
                    self.escape_part is not None):
                try:
                    best_bridge(set(terms), self.n, kind=self.escape_kind,
                                part=self.escape_part)
                except ValueError:
                    candidate_error = "explicit part has no bridge candidate"
            key = self.canonical(terms)
            # Rank remains primary: never hide a strict world-record recovery
            # merely to preserve symmetry.  At the same rank, prefer a scheme
            # eligible for the requested escape profile before density.
            candidate = (rank, int(candidate_error is not None),
                         self._density(key), key, list(terms), path)
            if candidate[:4] < best[:4]:
                best = candidate
        previous_rank = len(self.initial)
        self.initial = best[4]
        if best[5] is not None:
            self.recovered_rank = best[0]
        if best[0] < self.world_record:
            self.world_record = best[0]
        return previous_rank, best[0], best[5]

    def final_drain(self, start):
        """After workers quiesce, exact-gate their last dumps and spool writes."""
        if self.best is None:
            return
        old_best = self.best[0]
        candidates = []
        for i in range(1, self.nw + 1):
            rank, terms = read_dump(self.dump_file(i))
            if rank is not None and rank <= old_best and self.exact_valid(rank, terms):
                candidates.append((rank, i, terms, f"final/w{i}"))
        candidates.extend(self.drain_spool(old_best))
        gpu_candidate = self.gpu_candidate(old_best)
        if gpu_candidate is not None:
            candidates.append(gpu_candidate)
        if not candidates:
            return
        frontier_rank = min(item[0] for item in candidates)
        frontier = [item for item in candidates if item[0] == frontier_rank]
        frontier.sort(key=lambda item: (self.score(frontier_rank, item[2])["bits"],
                                        self.canonical(item[2]), item[1]))
        if frontier_rank < old_best:
            _, _, terms, _ = frontier[0]
            self.note_best(frontier_rank, terms, time.time() - start)
            for _, i, terms, source in frontier[1:]:
                self.archive_candidate(frontier_rank, terms, source=source)
            self.log(f"FINAL DRAIN: adopted verified rank {frontier_rank}")
        else:
            for _, i, terms, source in frontier:
                self.archive_candidate(frontier_rank, terms, source=source)
            best_tie = min((terms for _, _, terms, _ in frontier),
                           key=lambda item: (self.score(frontier_rank, item)["bits"],
                                             self.canonical(item)))
            self.note_tie_leader(frontier_rank, best_tie, time.time() - start)

    def append_perf(self, rank, terms, t):
        c = self.score(rank, terms)
        omega = c["omega"]
        omega = round(omega, 4) if math.isfinite(omega) else None
        pt = {"t": round(t, 1), "rank": rank, "bits": c["bits"],
              "ops": c["ops"], "omega": omega}
        self.perf.append(pt)
        with open(self.curve_path, "a") as stream:
            if os.path.getsize(self.curve_path) == 0:
                stream.write("t,rank,bits,ops,omega\n")
            stream.write(f"{pt['t']},{rank},{c['bits']},{c['ops']},{pt['omega']}\n")
        return c

    def note_best(self, rank, terms, t):
        if not self.archive_candidate(rank, terms, source="new-best"):
            return False
        self.best = (rank, terms)
        self.hydrate_archive(rank)
        self.new_bests += 1
        c = self.append_perf(rank, terms, t)
        omega_text = f"{c['omega']:.3f}" if math.isfinite(c["omega"]) else "n/a"
        self.log(f"NEW BEST rank={rank} bits={c['bits']} ops={c['ops']} omega={omega_text}")
        # bank a copy of the record scheme
        write_dump(terms, os.path.join(self.record, f"best_rank{rank}.txt"))
        write_dump(terms, os.path.join(self.dir, "best.txt"))
        if rank < self.world_record:
            self.record_hits += 1
            write_dump(terms, os.path.join(self.dir, "WORLD_RECORD.txt"))
            self.log(f"WORLD RECORD: verified rank={rank} beats {self.world_record}")
        return True

    def note_tie_leader(self, rank, terms, t):
        if self.best is None or rank != self.best[0]:
            return False
        candidate = self.score(rank, terms)
        current = self.score(*self.best)
        if candidate["bits"] >= current["bits"]:
            return False
        if not self.archive_candidate(rank, terms, source="tie-leader"):
            return False
        self._pin_archive(self.canonical(terms), terms)
        self.best = (rank, list(terms))
        self.tie_improvements += 1
        self.append_perf(rank, terms, t)
        write_dump(terms, os.path.join(self.record, f"best_rank{rank}.txt"))
        write_dump(terms, os.path.join(self.dir, "best.txt"))
        self.log(f"TIE LEADER rank={rank} bits={candidate['bits']} ops={candidate['ops']}")
        return True

    def frontier_seed(self):
        if self.archive and random.random() < self.archive_reseed:
            self.frontier_wraps += 1
            least_used = min(self.archive_uses.values())
            pool = [key for key, uses in self.archive_uses.items() if uses == least_used]
            key = random.choice(pool)
            self.archive_uses[key] += 1
            return list(self.archive[key]), "frontier"
        self.naive_wraps += 1
        return list(self.initial), "initial"

    def migration_targets(self, finder, ranks):
        candidates = [i for i in range(1, self.nw + 1) if i != finder]
        if self.strategy == "independent":
            return []
        if self.strategy == "converge":
            return candidates
        candidates.sort(key=lambda i: ranks.get(i, 10**9), reverse=True)
        return candidates[:self.migrate]

    def run(self):
        self.prepare_run()
        start = time.time()
        failure = None
        try:
            requested_rank, recovered_rank, recovered_path = self.recover_frontier()
            if self.escape_enabled_for("startup"):
                error = bridge_error(set(self.initial), self.n, self.escape_kind)
                if error:
                    recovery = (f" after recovering rank {recovered_rank} from "
                                f"{recovered_path}" if recovered_path else "")
                    raise ValueError(
                        f"startup escape is not applicable{recovery}: {error}")
                try:
                    self._compute_escape(self.initial)
                except ValueError as exc:
                    raise ValueError(
                        f"startup escape is not applicable: {exc}") from exc
            self.log(f"flipfleet start: {self.nw} walkers, strategy={self.strategy}, "
                     f"cycles={self.cycles}, <{self.n},{self.m},{self.p}> "
                     f"record={self.world_record}, plus={self.plus_axes}, "
                     f"record-bands={self.record_band_moves}, "
                     f"escape={self.escape_kind}@{self.escape_at}/every{self.escape_every}")
            if recovered_path is not None:
                self.log(f"RECOVER: rank {recovered_rank} from {recovered_path} "
                         f"(requested seed rank {requested_rank})")
            self.write_status(start, compiling=True)
            self.run_prepared.set()
            self.build_walker()
            self.log("walker compiled (cal2zone2, band=1, --release --native --fast --lto)")
            if self.gpu:
                self.build_gpu_relay()
            if self.stop_requested.is_set():
                raise InterruptedError("stop requested during compilation")
            open(self.curve_path, "w").close()
            self.best = (len(self.initial), list(self.initial))
            self.archive_candidate(*self.best, source="initial")
            self.hydrate_archive(len(self.initial))
            write_dump(self.initial, os.path.join(self.dir, "best.txt"))
            if self.gpu:
                self.launch_gpu_relay()
            for i in range(1, self.nw + 1):
                launch_seed, escape = self.prepare_launch_seed(
                    self.initial, "startup", strict=True)
                self.launch(i, 0, launch_seed)
                self.log_escape(i, escape)
            self.log(f"launched {self.nw} walkers from exact-verified rank "
                     f"{len(self.initial)} frontier; escapes={self.escape_applied}")
            start = time.time()  # --secs measures search time, not compilation
            self.write_status(start, compiling=False)

            while ((self.secs == 0 or (time.time() - start) < self.secs)
                   and not self.stop_requested.is_set()
                   and not (self.stop_on_record and self.record_hits)):
                if self.stop_requested.wait(1.0):
                    break
                now = time.time()

                # -- exact-gated best + a diversity archive at the frontier ----
                old_best = self.best[0]
                ranks = {}
                candidates = []
                for i in range(1, self.nw + 1):
                    rnk, trm = read_dump(self.dump_file(i))
                    if rnk is None:
                        continue
                    if self.exact_valid(rnk, trm):
                        self.invalid_dumps.pop(i, None)
                        ranks[i] = rnk
                        if rnk <= old_best:
                            candidates.append((rnk, i, trm, f"w{i}"))
                    else:
                        digest = hashlib.sha256(repr((rnk, trm)).encode()).hexdigest()
                        prior_digest, prior_count = self.invalid_dumps.get(i, (None, 0))
                        count = prior_count + 1 if digest == prior_digest else 1
                        self.invalid_dumps[i] = (digest, count)
                        if count == 1:
                            self.invalid_candidates += 1
                            self.log(f"REJECTED invalid rank={rnk} from w{i}")
                        if count >= 2:
                            seed, source = self.frontier_seed()
                            write_dump(seed, self.reseed_file(i))
                            self.stop_process(i)
                            self.launch(i, self.reseeds + 1, seed)
                            self.reseeds += 1
                            self.invalid_dumps.pop(i, None)
                            self.log(f"QUARANTINE: w{i} repeated an invalid dump; "
                                     f"restarted from {source} rank {len(seed)}")

                # Same-rank density snapshots and strict record beats use a
                # separate spool, so they remain visible even when the worker's
                # personal rank never drops below its record-valued seed.
                candidates.extend(self.drain_spool(old_best))
                gpu_candidate = self.gpu_candidate(old_best)
                if gpu_candidate is not None:
                    candidates.append(gpu_candidate)

                frontier_rank = min((x[0] for x in candidates), default=old_best)
                frontier = [x for x in candidates if x[0] == frontier_rank]
                frontier.sort(key=lambda item: (
                    self.score(frontier_rank, item[2])["bits"],
                    self.canonical(item[2]), item[1]))
                finder = -1
                best_terms = self.best[1]
                if frontier_rank < old_best:
                    _, finder, best_terms, source = frontier[0]
                    if self.note_best(frontier_rank, best_terms, now - start):
                        for _, i, terms, source in frontier[1:]:
                            self.archive_candidate(frontier_rank, terms, source=source)
                else:
                    for _, i, terms, source in frontier:
                        self.archive_candidate(frontier_rank, terms, source=source)
                    if frontier:
                        best_tie = min((terms for _, _, terms, _ in frontier),
                                       key=lambda item: (
                                           self.score(frontier_rank, item)["bits"],
                                           self.canonical(item)))
                        self.note_tie_leader(frontier_rank, best_tie, now - start)

                # -- migrate only a policy-selected slice; islands keep running --
                if frontier_rank < old_best:
                    if now - self.last_converge > 3.0:
                        self.last_converge = now
                        targets = self.migration_targets(finder, ranks)
                        for i in targets:
                            write_dump(best_terms, self.reseed_file(i))
                            self.stop_process(i)
                            self.launch(i, self.reseeds + 1, best_terms)
                            self.reseeds += 1
                        self.log(f"MIGRATE: {len(targets)} walkers onto rank {frontier_rank} "
                                 f"(found by {'GPU' if finder == 0 else 'w' + str(finder)}; "
                                 f"strategy={self.strategy})")

                # -- exhausted island -> a separated frontier seed or fresh start --
                for i in range(1, self.nw + 1):
                    pr = self.procs[i]
                    if pr and pr.poll() is not None:
                        cyc = tail_has(os.path.join(self.dir, f"cpu_{i}.log"), "CYCLEOUT")
                        seed, source = self.frontier_seed()
                        escape = None
                        if cyc:
                            seed, escape = self.prepare_launch_seed(seed, "cycleout")
                        self.launch(
                            i, self.naive_wraps + self.frontier_wraps + self.reseeds + 1, seed)
                        self.log_escape(i, escape)
                        self.log(f"EXPLORE: w{i} {'CYCLEOUT' if cyc else 'exit'} -> "
                                 f"{source} rank {len(seed)}"
                                 f"{' (escaped)' if escape and escape.get('applied') else ''}")

                self.write_status(start, compiling=False)
        except InterruptedError as exc:
            self.log(str(exc))
        except KeyboardInterrupt:
            self.log("interrupted, stopping")
        except Exception as exc:
            failure = exc
            self.error = f"{type(exc).__name__}: {exc}"
            self.log(f"ERROR: {self.error}")
        finally:
            self.stop_requested.set()
            for i in range(1, self.nw + 1):
                self.stop_process(i)
            if self.gpu_proc is not None and self.gpu_proc.poll() is None:
                self.gpu_proc.terminate()
                try:
                    self.gpu_proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    self.gpu_proc.kill()
                    self.gpu_proc.wait(timeout=5)
            try:
                self.final_drain(start)
            except Exception as exc:
                failure = failure or exc
                self.error = self.error or f"final drain: {type(exc).__name__}: {exc}"
                self.log(f"ERROR: {self.error}")
            for lf in self.logs.values():
                try:
                    lf.close()
                except Exception:
                    pass
            if self.gpu_log is not None:
                self.gpu_log.close()
            try:
                self.log("search stopped")
                self.write_status(start, done=True)
                self.run_prepared.set()
            finally:
                self.release_lock()
        if failure is not None:
            raise failure

    def write_status(self, start, compiling=False, done=False):
        walkers = []
        for i in range(1, self.nw + 1):
            r, m = "?", 0
            try:
                with open(os.path.join(self.dir, f"cpu_{i}.log")) as f:
                    lines = f.read().splitlines()
                for ln in reversed(lines):
                    if ln.strip().startswith("mv="):
                        parts = dict(p.split("=") for p in ln.split() if "=" in p)
                        r, m = parts.get("best", "?"), int(parts.get("mv", 0))
                        break
            except Exception:
                pass
            since_reseed = (round(time.time() - self.reseeded_at[i], 0)
                            if self.reseeded_at[i] else 0)
            walkers.append({"id": i, "rank": r, "mv": m,
                            "since_reseed": since_reseed,
                            "record_band_moves": self.record_band_moves[
                                (i - 1) % len(self.record_band_moves)]})
        c = self.score(*self.best) if self.best else {}
        omega = c.get("omega")
        omega = round(omega, 4) if isinstance(omega, float) and math.isfinite(omega) else None
        status = {
            "started": start, "elapsed": round(time.time() - start, 1),
            "done": done, "compiling": compiling, "strategy": self.strategy,
            "error": self.error,
            "format": f"{self.n}x{self.m}x{self.p}", "record": self.world_record,
            "configured_record": self.configured_record,
            "recovered_rank": self.recovered_rank,
            "escape": {"kind": self.escape_kind, "at": self.escape_at,
                       "every": self.escape_every, "part": self.escape_part,
                       "considered": self.escape_considered,
                       "applied": self.escape_applied,
                       "bypassed": self.escape_bypassed,
                       "skipped": self.escape_skipped},
            "gpu": {"enabled": self.gpu, "walkers": self.gpu_walkers,
                    "escapes": self.gpu_escapes, "steps": self.gpu_steps,
                    "running": bool(self.gpu_proc and self.gpu_proc.poll() is None)},
            "best": {"rank": self.best[0], "bits": c.get("bits"), "ops": c.get("ops"),
                     "omega": omega} if self.best else {},
            "walkers": walkers,
            "perf_curve": self.perf[-200:],
            "counters": {"reseeds": self.reseeds, "initial_wraps": self.naive_wraps,
                         "frontier_wraps": self.frontier_wraps,
                         "archive": len(self.archive),
                         "archive_capacity": self.archive_size,
                         "archive_evictions": self.archive_evictions,
                         "archive_rejections": self.archive_rejections,
                         "archive_min_distance": self.archive_min_distance,
                         "archive_hydrated": self.archive_hydrated,
                         "invalid": self.invalid_candidates,
                         "record_hits": self.record_hits,
                         "new_bests": self.new_bests,
                         "tie_improvements": self.tie_improvements},
            "events": self.events[-14:],
        }
        tmp = self.status_path + ".tmp"
        with open(tmp, "w") as f:
            json.dump(status, f, allow_nan=False)
        os.replace(tmp, self.status_path)


# ---- the TUI ----------------------------------------------------------------
def spark(vals, lo=None, hi=None, width=40):
    if not vals:
        return ""
    blocks = "▁▂▃▄▅▆▇█"
    lo = min(vals) if lo is None else lo
    hi = max(vals) if hi is None else hi
    if hi == lo:
        hi = lo + 1
    vals = vals[-width:]
    return "".join(blocks[min(7, max(0, int((v - lo) / (hi - lo) * 7)))] for v in vals)


def tui(status_path):
    import curses

    def draw(scr):
        try:
            curses.curs_set(0)
        except curses.error:
            pass
        scr.nodelay(True)
        try:
            curses.start_color(); curses.use_default_colors()
            curses.init_pair(1, curses.COLOR_YELLOW, -1)
            curses.init_pair(2, curses.COLOR_GREEN, -1)
            curses.init_pair(3, curses.COLOR_CYAN, -1)
            curses.init_pair(4, curses.COLOR_RED, -1)
        except Exception:
            pass
        A = lambda n: curses.color_pair(n)
        while True:
            ch = scr.getch()
            if ch in (ord("q"), ord("Q")):
                break
            try:
                s = json.load(open(status_path))
            except Exception:
                s = None
            scr.erase()
            h, w = scr.getmaxyx()
            if not s:
                scr.addstr(0, 0, "waiting for status.json …")
                scr.refresh(); time.sleep(0.5); continue
            b = s.get("best", {})
            done = s.get("done")
            title = f" flipfleet  <{s['format']}> GF(2)   strategy={s['strategy']} "
            scr.addstr(0, 0, title[:w - 1], A(1) | curses.A_BOLD)
            st = "DONE" if done else "LIVE"
            scr.addstr(0, max(0, w - len(st) - 1), st, A(4 if done else 2) | curses.A_BOLD)
            om = f"{b.get('omega'):.3f}" if isinstance(b.get("omega"), float) else "-"
            gap = (b.get("rank", 0) - s["record"]) if b.get("rank") else "?"
            scr.addstr(2, 0, f" best rank ", A(3))
            scr.addstr(2, 11, f"{b.get('rank','?')}", A(2) | curses.A_BOLD)
            scr.addstr(2, 18, f" (+{gap} to record {s['record']})   ops={b.get('ops','?')}  "
                              f"bits={b.get('bits','?')}  ω={om}")
            c = s.get("counters", {})
            min_distance = c.get("archive_min_distance")
            min_distance = "-" if min_distance is None else min_distance
            scr.addstr(3, 0, f" elapsed {s['elapsed']:.0f}s   new-bests {c.get('new_bests',0)}   "
                             f"migrations {c.get('reseeds',0)}   archive {c.get('archive',0)}"
                             f"/{c.get('archive_capacity','?')} Δmin="
                             f"{min_distance}   invalid {c.get('invalid',0)}")

            # perf curve sparklines (rank down, ops)
            pc = s.get("perf_curve", [])
            row = 5
            escape = s.get("escape", {})
            if escape.get("kind", "none") != "none":
                scr.addstr(4, 0, f" escape {escape['kind']}@{escape['at']}/every"
                                 f"{escape['every']}   applied {escape['applied']}   "
                                 f"bypassed {escape['bypassed']}   skipped "
                                 f"{escape['skipped']}", A(1))
                row = 6
            if pc:
                ranks = [p["rank"] for p in pc]
                opss = [p["ops"] for p in pc]
                scr.addstr(row, 0, " rank  " + spark(ranks, width=w - 20) +
                           f"  {ranks[0]}→{ranks[-1]}", A(2))
                scr.addstr(row + 1, 0, " ops   " + spark(opss, width=w - 20) +
                           f"  {opss[0]}→{opss[-1]}", A(1))
                row += 3
            scr.addstr(row, 0, " walkers (rank · Bmoves · since-reseed s):", A(3))
            row += 1
            cols = max(1, (w - 2) // 26)
            for idx, wk in enumerate(s["walkers"]):
                rr, cc = row + idx // cols, 1 + (idx % cols) * 26
                if rr >= h - 14:
                    break
                atr = A(2) if str(wk["rank"]).isdigit() and int(wk["rank"]) <= s["record"] + 8 else 0
                scr.addstr(rr, cc, f"w{wk['id']:02d} {str(wk['rank']):>3} "
                                   f"{wk['mv']/1e9:>5.1f}B {int(wk['since_reseed']):>4}s"[:25], atr)
            ev_row = min(h - 13, row + (len(s["walkers"]) + cols - 1) // cols + 1)
            scr.addstr(ev_row, 0, " events:", A(3))
            for j, e in enumerate(s.get("events", [])[-min(11, h - ev_row - 2):]):
                scr.addstr(ev_row + 1 + j, 1, e[:w - 2],
                           A(2) if "NEW BEST" in e else (A(1) if "EXPLOIT" in e else 0))
            scr.addstr(h - 1, 0, " q to quit — data from status.json (also readable by other tools) ",
                       curses.A_DIM)
            scr.refresh()
            time.sleep(0.5)

    curses.wrapper(draw)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--size", type=int, help="square shortcut: sets n=m=p")
    ap.add_argument("--n", type=int, default=5)
    ap.add_argument("--m", type=int)
    ap.add_argument("--p", type=int)
    ap.add_argument("--record", type=int, help="known record (auto for square 3..6)")
    ap.add_argument(
        "--seed", help="scheme path, 'record', 'c3-record', or omitted for naive")
    ap.add_argument("--walkers", type=int, default=12)
    ap.add_argument("--secs", type=int, default=0, help="0 = run until stopped")
    ap.add_argument("--cycles", type=int, default=4,
                    help="sawtooth cycles a walker runs before CYCLEOUT -> reseed")
    ap.add_argument("--strategy", choices=("islands", "independent", "converge"),
                    default="islands")
    ap.add_argument("--migrate", type=int,
                    help="islands migrated on a strict rank drop (default: walkers/4)")
    ap.add_argument("--archive-reseed", type=float, default=0.75,
                    help="probability a cycle-out restarts from a random frontier scheme")
    ap.add_argument("--archive-size", type=int, default=256,
                    help="max in-memory max-min frontier sample (all remain on disk)")
    ap.add_argument("--record-band-moves", type=parse_move_budgets,
                    default=(250_000_000, 1_000_000_000, 10_000_000_000),
                    help="comma-separated frontier dwell portfolio, e.g. 250m,1b,10b")
    ap.add_argument("--plus-axes", choices=("w", "any"), default="any")
    ap.add_argument(
        "--escape-kind", choices=ESCAPE_KINDS, default="none",
        help=("exact launch excursion: split any term; break a fixed cube; or "
              "use a C3-preserving orbit-split/polarization (normally with "
              "--seed c3-record)"))
    ap.add_argument(
        "--escape-at", choices=ESCAPE_TRIGGERS, default="both",
        help="eligible launch sites (never migration, quarantine, or plain exits)")
    ap.add_argument(
        "--escape-every", type=int, default=2,
        help="escape every Nth eligible launch (default 2: escaped/base portfolio)")
    ap.add_argument(
        "--escape-part", type=lambda value: int(value, 0),
        help="optional fixed common-space part mask; default chooses deterministically")
    ap.add_argument("--stop-on-record", action="store_true")
    ap.add_argument(
        "--gpu", action="store_true",
        help="launch the dimension-specialized Tungsten/Metal exact-escape scout")
    ap.add_argument(
        "--gpu-escapes", type=int, default=256,
        help="number of exact split basins in the GPU seed portfolio (default 256; 1=legacy)")
    ap.add_argument(
        "--gpu-walkers", type=int, default=4096,
        help="GPU lane count, rounded down to a generated threadgroup multiple")
    ap.add_argument(
        "--gpu-steps", type=int, default=500_000,
        help="moves per GPU dispatch and lane")
    ap.add_argument("--dir")
    ap.add_argument("--tui", action="store_true", help="run the search AND show the TUI")
    ap.add_argument("--attach", metavar="RUN_DIR", help="TUI only, attach to an existing run")
    args = ap.parse_args()

    if args.attach:
        tui(os.path.join(args.attach, "status.json"))
        return

    if args.size is not None:
        args.n = args.m = args.p = args.size
    else:
        args.m = args.n if args.m is None else args.m
        args.p = args.n if args.p is None else args.p
    if args.record is None:
        if args.n == args.m == args.p and args.n in KNOWN_RECORDS:
            args.record = KNOWN_RECORDS[args.n]
        else:
            ap.error("--record is required for this format")
    try:
        validate_format(args.n, args.m, args.p)
        if args.walkers <= 0:
            raise ValueError("--walkers must be positive")
        if args.secs < 0:
            raise ValueError("--secs must be nonnegative")
        if args.cycles <= 0:
            raise ValueError("--cycles must be positive")
        if args.record <= 0:
            raise ValueError("--record must be positive")
        if args.archive_size <= 0:
            raise ValueError("--archive-size must be positive")
        if args.escape_every <= 0:
            raise ValueError("--escape-every must be positive")
        if args.escape_kind != "none" and not (args.n == args.m == args.p):
            raise ValueError("--escape-kind currently requires a square format")
        if args.escape_part is not None:
            if args.escape_kind == "none":
                raise ValueError("--escape-part requires --escape-kind")
            if not 0 < args.escape_part < (1 << (args.n * args.n)):
                raise ValueError("--escape-part must fit the nonzero square factor mask")
        if not math.isfinite(args.archive_reseed) or not 0 <= args.archive_reseed <= 1:
            raise ValueError("--archive-reseed must be finite and between zero and one")
        if args.migrate is not None and not 0 <= args.migrate <= args.walkers:
            raise ValueError("--migrate must be between zero and --walkers")
        if args.gpu_escapes <= 0 or args.gpu_walkers <= 0 or args.gpu_steps <= 0:
            raise ValueError("--gpu-escapes, --gpu-walkers, and --gpu-steps must be positive")
    except ValueError as exc:
        ap.error(str(exc))
    if args.seed == "record":
        if args.n != args.m or args.m != args.p or args.n not in RECORD_SEEDS:
            ap.error("no built-in record seed for this format")
        args.seed = RECORD_SEEDS[args.n]
    elif args.seed == "c3-record":
        if args.n != args.m or args.m != args.p or args.n not in C3_RECORD_SEEDS:
            ap.error("no built-in C3 record seed for this format")
        args.seed = C3_RECORD_SEEDS[args.n]
    if args.seed:
        try:
            initial = normalize_terms(parse_scheme(args.seed))
        except (OSError, ValueError, IndexError) as exc:
            ap.error(f"could not parse --seed {args.seed!r}: {exc}")
        if not initial:
            ap.error(f"--seed {args.seed!r} contained no scheme terms")
        if (not terms_in_bounds(initial, args.n, args.m, args.p) or
                not verify(initial, args.n, args.m, args.p)):
            ap.error(f"--seed {args.seed!r} failed exact tensor verification")
    else:
        initial = naive_scheme(args.n, args.m, args.p)
    run_dir = args.dir or os.path.join(HERE, "runs", f"flipfleet_{args.n}{args.m}{args.p}")
    try:
        fleet = Fleet(run_dir, args.walkers, args.secs, n=args.n, m=args.m, p=args.p,
                      record=args.record, initial_terms=initial, strategy=args.strategy,
                      cycles=args.cycles, migrate=args.migrate,
                      archive_reseed=args.archive_reseed, archive_size=args.archive_size,
                      plus_axes=args.plus_axes,
                      stop_on_record=args.stop_on_record,
                      record_band_moves=args.record_band_moves,
                      escape_kind=args.escape_kind, escape_at=args.escape_at,
                      escape_every=args.escape_every, escape_part=args.escape_part,
                      gpu=args.gpu, gpu_escapes=args.gpu_escapes,
                      gpu_walkers=args.gpu_walkers, gpu_steps=args.gpu_steps)
    except ValueError as exc:
        ap.error(str(exc))
    if args.tui:
        t = threading.Thread(target=fleet.run)
        try:
            t.start()
            while not fleet.run_prepared.wait(0.3):
                if not t.is_alive():
                    t.join()
                    return
            if not os.path.exists(fleet.status_path):
                t.join()
                return
            tui(fleet.status_path)
        except KeyboardInterrupt:
            pass
        finally:
            fleet.request_stop()
            if t.is_alive():
                t.join()
    else:
        print(f"run dir: {run_dir}\nstatus:  {fleet.status_path}\nattach:  "
              f"python3 {os.path.basename(__file__)} --attach {run_dir}", flush=True)
        fleet.run()


if __name__ == "__main__":
    main()
