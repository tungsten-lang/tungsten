"""flipfleet — an exact-gated, persistent-island flip-graph search for GF(2)
matrix multiplication, with a live TUI and per-new-best benchmarking.

The default ``islands`` strategy gives every walker a sticky exploration role
and keeps those distinct doors alive across global improvements.  Only one
leader/frontier lane migrates on a strict rank drop.  Every candidate is exact
tensor-verified before adoption, every distinct frontier snapshot observed by
the coordinator is atomically archived, and cycle-outs draw from the frontier,
exact +1/+2 shoulder banks, symmetry moves, or the original start according to
their role.  ``independent`` disables migration; ``converge`` retains the old
reseed-everyone policy for controlled comparisons.

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
  python3 flipfleet.py --tensor 3x3 --walkers 12 --secs 60
  python3 flipfleet.py --tensor 5x5 --strategy islands --tui
  python3 flipfleet.py --tensor 4x4 --escape-kind split
  python3 flipfleet.py --tensor 6x6 --no-gpu
  python3 flipfleet.py --attach <run_dir>                    # TUI only, attach to a run
"""
import argparse
from dataclasses import replace
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
from c3_gpu_relay import (C3GpuConfig, C3GpuRelay,
                          capacity_for_rank as c3_capacity_for_rank)  # noqa: E402
from cpu_seed_banks import (NearFrontierBank,
                            build_symmetry_move_bank)  # noqa: E402
from escape_portfolio import build_portfolio  # noqa: E402
from gpu_cal2zone_gen import gen as gpu_cal2zone_gen  # noqa: E402
from gpu_mitm_surgery import GpuMitmFleetAdapter  # noqa: E402
from simdgroup_relay import (CooperativeSimdRelay, SimdgroupConfig,
                             capacity_for_rank)  # noqa: E402
from sym_escape import (best_bridge, bridge_error, describe as describe_escape,
                        is_c3_closed)  # noqa: E402
from tensor_profiles import (KNOWN_C3_SEEDS, KNOWN_RECORD_RANKS,
                             KNOWN_RECORD_SEEDS, ROLE_KEYS,
                             profile_for_tensor, tensor_arg)  # noqa: E402
from tui_dashboard import (build_time_timeline, derive_health_state,
                           format_cpu_island_row, format_objective,
                           summarize_diversity, summarize_effectiveness,
                           summarize_gpu_roles)  # noqa: E402

CAP_MOVES = 50_000_000_000_000          # INTEGER — a float cap emits a float literal and nan-boxes
KNOWN_RECORDS = dict(KNOWN_RECORD_RANKS)
RECORD_SEEDS = dict(KNOWN_RECORD_SEEDS)
C3_RECORD_SEEDS = dict(KNOWN_C3_SEEDS)
ESCAPE_KINDS = ("none", "split", "break", "orbit-split", "polarize")
ESCAPE_PROFILES = ("none", "single", "mixed")
ESCAPE_TRIGGERS = ("startup", "cycleout", "both")
ESCAPE_MAX_DELTA = {"none": 0, "split": 1, "break": 1,
                    "orbit-split": 5, "polarize": 7}
GPU_POLICIES = ("single", "adaptive")
GPU_ROLE_ORDER = ROLE_KEYS
# Cal2zone schedule profiles.  ``symmetry``, ``simd``, and ``mitm`` are
# heterogeneous engines and are dispatched by dedicated adapters; the escape
# families use the same exact-preserving kernel from different verified seeds.
GPU_ROLE_PROFILES = {
    "rank": {"reseed": 300, "margin": 8, "workq": 220_000,
             "wanderq": 90_000, "wthr": 9, "escapes": 1},
    "density": {"reseed": 800, "margin": 1, "workq": 250_000,
                "wanderq": 100_000, "wthr": 9, "escapes": 1},
    "split": {"reseed": 20, "margin": 8, "workq": 80_000,
              "wanderq": 25_000, "wthr": 4, "escapes": "all"},
    "break": {"reseed": 40, "margin": 8, "workq": 90_000,
              "wanderq": 30_000, "wthr": 4, "escapes": 1},
    "orbit": {"reseed": 60, "margin": 10, "workq": 100_000,
              "wanderq": 35_000, "wthr": 5, "escapes": 1},
    "polarize": {"reseed": 60, "margin": 12, "workq": 100_000,
                 "wanderq": 35_000, "wthr": 5, "escapes": 1},
    "compose": {"reseed": 30, "margin": 14, "workq": 90_000,
                "wanderq": 30_000, "wthr": 4, "escapes": 1},
    "novelty": {"reseed": 100, "margin": 3, "workq": 120_000,
                "wanderq": 40_000, "wthr": 6, "escapes": 1},
}

# Sticky CPU doors prevent a strict best from turning every island into the
# same trajectory.  The twelve-slot patterns are evidence-guided starting
# portfolios; shorter fleets take a deterministic prefix and longer fleets
# repeat it.  ``symmetry`` means one replayable C3-preserving escape, not a
# claim that C3 is globally best.
CPU_DOOR_PATTERNS = {
    3: ("leader", "frontier", "near1", "near1", "near1", "near1",
        "near2", "near2", "near2", "mixed", "mixed", "anchor"),
    4: ("leader", "near1", "near1", "near1", "near1", "near1",
        "near2", "near2", "near2", "near2", "mixed", "anchor"),
    5: ("leader", "frontier", "near1", "near1", "near2", "near2",
        "symmetry", "symmetry", "symmetry", "mixed", "mixed", "anchor"),
    6: ("leader", "frontier", "frontier", "near1", "near1", "near2",
        "near2", "near2", "symmetry", "mixed", "mixed", "anchor"),
    7: ("leader", "frontier", "frontier", "frontier", "frontier", "near1",
        "near1", "near2", "near2", "symmetry", "mixed", "anchor"),
}

# Four independent move-budget arms.  Wander is intentionally much shorter
# than work: the earlier record-band override made a 10B cohort spend 10B in
# every high wander band, defeating fast basin turnover.  The scale reflects
# the measured campaign regimes; it is a portfolio, not an asserted optimum.
CPU_ZONE_ARMS = {
    3: ((25_000_000, 6_250_000), (125_000_000, 25_000_000),
        (625_000_000, 125_000_000), (2_500_000_000, 250_000_000)),
    4: ((50_000_000, 12_500_000), (250_000_000, 50_000_000),
        (1_250_000_000, 250_000_000), (5_000_000_000, 500_000_000)),
    5: ((100_000_000, 25_000_000), (500_000_000, 100_000_000),
        (2_500_000_000, 500_000_000), (10_000_000_000, 1_000_000_000)),
    6: ((100_000_000, 25_000_000), (500_000_000, 100_000_000),
        (2_500_000_000, 500_000_000), (10_000_000_000, 1_000_000_000)),
    7: ((200_000_000, 50_000_000), (1_000_000_000, 200_000_000),
        (5_000_000_000, 1_000_000_000), (20_000_000_000, 2_000_000_000)),
}
CPU_ZONE_NAMES = ("short", "balanced", "high-band", "marathon")
CPU_ZONE_ORDER = (1, 0, 1, 2, 0, 1, 2, 3, 0, 1, 2, 3)


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
        return any(needle in ln for ln in read_tail_lines(path)[-n:])
    except Exception:
        return False


def read_tail_lines(path, max_bytes=131_072):
    """Read a bounded UTF-8 tail without rescanning a growing walker log."""
    with open(path, "rb") as stream:
        stream.seek(0, os.SEEK_END)
        size = stream.tell()
        offset = max(0, size - max_bytes)
        stream.seek(offset)
        data = stream.read()
    text = data.decode("utf-8", errors="replace")
    lines = text.splitlines()
    if offset and lines:
        lines = lines[1:]
    return lines


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
        "best.txt", "WORLD_RECORD.txt", "BASELINE_IMPROVEMENT.txt",
        "walker", "walker.w", "walker.sidemap",
        "best.txt.tmp", "WORLD_RECORD.txt.tmp", "cpu_*.txt", "cpu_*.txt.tmp",
        "cpu_*.log", "reseed_*.txt", "reseed_*.txt.tmp",
        "gpu_best.txt", "gpu_best.txt.tmp", "gpu_relay", "gpu_relay.w",
        "gpu_relay.ll", "gpu_relay.metal", "gpu_relay.sidemap", "gpu_relay.log",
        "gpu_*_best.txt", "gpu_*_best.txt.tmp", "gpu_*_seed.txt",
        "gpu_*_seed.txt.tmp", "gpu_*_live.txt", "gpu_*_live.txt.tmp",
        "gpu_*_relay.log",
        "simdgroup_relay", "simdgroup_relay.w", "simdgroup_relay.ll",
        "simdgroup_relay.metal", "simdgroup_relay.sidemap",
        "simdgroup_relay.log", "simdgroup_best.txt",
        "c3_gpu_relay", "c3_gpu_relay.w", "c3_gpu_relay.ll",
        "c3_gpu_relay.metal", "c3_gpu_relay.sidemap",
        "c3_gpu_relay.log", "c3_gpu_best.txt",
    )

    def __init__(self, run_dir, nwalkers, secs, n=5, m=5, p=5, record=93,
                 initial_terms=None, strategy="islands", cycles=4, migrate=None,
                 archive_reseed=1.0, archive_size=256, plus_axes="any",
                 stop_on_record=False, record_band_moves=None,
                 wander_zone_moves=None,
                 escape_kind="none", escape_at="both", escape_every=2,
                 escape_part=None, escape_profile="none", escape_bank_count=24,
                 cpu_near_size=128, cpu_near_signature_quota=8,
                 cpu_symmetry_seeds=24,
                 c3_terms=None, gpu=False, gpu_escapes=256,
                 gpu_walkers=4096, gpu_steps=500_000, gpu_policy="single",
                 gpu_novelty_size=32, gpu_adapt_secs=300,
                 tensor_profile=None, gpu_role_weights=None,
                 record_known=True):
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
        if escape_profile not in ESCAPE_PROFILES:
            raise ValueError(f"escape_profile must be one of {ESCAPE_PROFILES}")
        if escape_profile == "none" and escape_kind != "none":
            # Preserve the pre-profile programmatic API: specifying a kind
            # still opts into the historical single-identity behavior.
            escape_profile = "single"
        if escape_profile == "single" and escape_kind == "none":
            raise ValueError("single escape_profile requires an escape_kind")
        if escape_at not in ESCAPE_TRIGGERS:
            raise ValueError(f"escape_at must be one of {ESCAPE_TRIGGERS}")
        if not isinstance(escape_every, int) or escape_every <= 0:
            raise ValueError("escape_every must be positive")
        if (escape_kind != "none" or escape_profile == "mixed") and not (n == m == p):
            raise ValueError("escape moves currently require a square format")
        if not isinstance(escape_bank_count, int) or escape_bank_count < 2:
            raise ValueError("escape_bank_count must be at least two")
        if not isinstance(cpu_near_size, int) or cpu_near_size < 2:
            raise ValueError("cpu_near_size must be at least two")
        if (not isinstance(cpu_near_signature_quota, int) or
                cpu_near_signature_quota <= 0):
            raise ValueError("cpu_near_signature_quota must be positive")
        if not isinstance(cpu_symmetry_seeds, int) or cpu_symmetry_seeds <= 0:
            raise ValueError("cpu_symmetry_seeds must be positive")
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
        if gpu_policy not in GPU_POLICIES:
            raise ValueError(f"gpu_policy must be one of {GPU_POLICIES}")
        if not isinstance(gpu_novelty_size, int) or gpu_novelty_size <= 0:
            raise ValueError("gpu_novelty_size must be positive")
        if (not isinstance(gpu_adapt_secs, int) or gpu_adapt_secs <= 0):
            raise ValueError("gpu_adapt_secs must be positive")
        self.dir = run_dir
        self.nw = nwalkers
        self.secs = secs
        self.n, self.m, self.p = n, m, p
        self.strategy = strategy
        self.cycles = cycles            # sawtooth cycles before a walker CYCLEOUTs -> reseed
        self.world_record = record
        self.configured_record = record
        self.record_known = bool(record_known)
        source_terms = naive_scheme(n, m, p) if initial_terms is None else initial_terms
        self.initial = normalize_terms(source_terms)
        # One exploitation lane follows a strict leader by default.  The old
        # quarter-fleet reset still collapsed too many intentionally different
        # shoulder/symmetry doors.
        self.migrate = 1 if migrate is None else max(0, migrate)
        self.archive_reseed = archive_reseed
        self.archive_size = archive_size
        self.plus_axes = plus_axes
        self.stop_on_record = stop_on_record
        self.escape_kind = escape_kind
        self.escape_profile = escape_profile
        self.escape_at = escape_at
        self.escape_every = escape_every
        self.escape_part = escape_part
        self.escape_bank_count = escape_bank_count
        self.c3_terms = normalize_terms(c3_terms) if c3_terms is not None else None
        if (self.c3_terms is None and self.initial and n == m == p and
                is_c3_closed(self.initial, n)):
            self.c3_terms = list(self.initial)
        if self.c3_terms is not None:
            if (not terms_in_bounds(self.c3_terms, n, m, p) or
                    not verify(self.c3_terms, n, m, p) or
                    not is_c3_closed(self.c3_terms, n)):
                raise ValueError("c3_terms must be an exact C3-closed square scheme")
        self.c3_best = ((len(self.c3_terms), list(self.c3_terms))
                        if self.c3_terms is not None else None)
        self.escape_considered = 0
        self.escape_applied = 0
        self.escape_bypassed = 0
        self.escape_skipped = 0
        self.escape_cache = {}
        self.escape_portfolio_cache = {}
        self.escape_recipe_counts = {}
        self.cpu_near_size = cpu_near_size
        self.cpu_near_signature_quota = cpu_near_signature_quota
        self.cpu_symmetry_seed_count = cpu_symmetry_seeds
        self.cpu_near_bank = None
        self.cpu_symmetry_bank = ()
        self.cpu_symmetry_uses = {}
        self.cpu_active_near_seed = [None] * (nwalkers + 1)
        self.cpu_role_escape_considered = [0] * (nwalkers + 1)
        self.cpu_near_seen = {}
        self.cpu_near_admissions = 0
        self.cpu_near_hydrated = 0
        self.cpu_near_rebases = 0
        self.gpu = gpu
        self.gpu_escapes = gpu_escapes
        self.gpu_walkers = gpu_walkers
        self.gpu_steps = gpu_steps
        self.gpu_allocation_quantum = 32
        self.gpu_policy = gpu_policy
        self.tensor_profile = tensor_profile
        default_weights = ({role: 1.0 for role in ("rank", "density", "split", "novelty")}
                           if self.tensor_profile is None else
                           dict(self.tensor_profile.role_fractions))
        self.gpu_role_weights = dict(default_weights if gpu_role_weights is None
                                     else gpu_role_weights)
        unknown_roles = set(self.gpu_role_weights) - set(GPU_ROLE_ORDER)
        if unknown_roles:
            raise ValueError(f"unknown GPU roles: {sorted(unknown_roles)}")
        if any(not math.isfinite(float(value)) or float(value) < 0
               for value in self.gpu_role_weights.values()):
            raise ValueError("GPU role weights must be finite and nonnegative")
        if sum(float(value) for value in self.gpu_role_weights.values()) <= 0:
            raise ValueError("at least one GPU role weight must be positive")
        self.gpu_roles = tuple(
            role for role in GPU_ROLE_ORDER
            if (float(self.gpu_role_weights.get(role, 0.0)) > 0 and
                (role not in ("symmetry", "orbit", "polarize") or
                 self.c3_terms is not None))
        )
        self.gpu_novelty_size = gpu_novelty_size
        self.gpu_adapt_secs = gpu_adapt_secs
        self.gpu_proc = None
        self.gpu_log = None
        self.gpu_invalid_digest = None
        self.gpu_exit_reported = False
        self.gpu_procs = {}
        self.gpu_logs = {}
        self.gpu_engine_adapters = {}
        self.gpu_role_allocations = {}
        self.gpu_role_stats = {
            role: {"epochs": 0, "lane_epochs": 0, "reward": 0.0,
                   "epoch_reward": 0.0,
                   "candidates": 0, "pareto": 0, "rank_drops": 0,
                   "density_improvements": 0}
            for role in self.gpu_roles
        }
        self.gpu_role_seen = {}
        self.gpu_role_invalid = {}
        self.gpu_role_seed_banks = {}
        self.gpu_role_seed_profiles = {}
        self.gpu_role_launches = {role: 0 for role in self.gpu_roles}
        self.gpu_role_plans = {}
        self.gpu_role_failures = {role: 0 for role in self.gpu_roles}
        self.gpu_role_retry_at = {}
        self.gpu_role_exit_reported = set()
        self.gpu_last_adapt = 0.0
        self.gpu_adapt_generation = 0
        self.gpu_pareto = {}
        self.gpu_pareto_admissions = 0
        self.gpu_pareto_rejections = 0
        self.gpu_pareto_evictions = 0
        zone_arms = CPU_ZONE_ARMS.get(n, CPU_ZONE_ARMS[7])
        default_work = tuple(pair[0] for pair in zone_arms)
        default_wander = tuple(pair[1] for pair in zone_arms)
        work_moves = default_work if record_band_moves is None else tuple(record_band_moves)
        wander_moves = (default_wander if wander_zone_moves is None else
                        tuple(wander_zone_moves))
        if (not work_moves or
                any(not isinstance(value, int) or value <= 0 for value in work_moves)):
            raise ValueError("work-zone move budgets must contain positive integers")
        if (not wander_moves or
                any(not isinstance(value, int) or value <= 0 for value in wander_moves)):
            raise ValueError("wander-zone move budgets must contain positive integers")
        self.work_zone_moves = work_moves
        self.wander_zone_moves = wander_moves
        # Compatibility alias used by older status readers and callers.
        self.record_band_moves = self.work_zone_moves
        door_pattern = CPU_DOOR_PATTERNS.get(n, CPU_DOOR_PATTERNS[7])
        self.cpu_door_roles = [None] + [
            door_pattern[(index - 1) % len(door_pattern)]
            for index in range(1, nwalkers + 1)
        ]
        self.cpu_zone_profiles = [None] + [
            CPU_ZONE_ORDER[(index - 1) % len(CPU_ZONE_ORDER)]
            for index in range(1, nwalkers + 1)
        ]
        self.cpu_door_launches = {role: 0 for role in set(door_pattern)}
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
        self.status_sequence = 0
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
        self.cpu_launch_sources = [None] * (nwalkers + 1)
        self.cpu_launch_seed_ranks = [None] * (nwalkers + 1)
        self.cpu_launch_seed_digests = [None] * (nwalkers + 1)
        self.cpu_launch_seed_c3 = [None] * (nwalkers + 1)
        self.cpu_launch_cohorts = [None] * (nwalkers + 1)
        self.cpu_last_accounted_mv = [0] * (nwalkers + 1)
        self.cpu_last_accounted_at = [0.0] * (nwalkers + 1)
        self.cpu_sample_launch = [0] * (nwalkers + 1)
        self.cpu_sample_mv = [0] * (nwalkers + 1)
        self.cpu_sample_at = [0.0] * (nwalkers + 1)
        self.cpu_progress_at = [0.0] * (nwalkers + 1)
        self.cpu_rate_mps = [None] * (nwalkers + 1)
        self.cpu_last_exit_code = [None] * (nwalkers + 1)
        self.cpu_accounting_closed = [True] * (nwalkers + 1)
        self.cpu_cohort_stats = {}
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
        seed_highwater = max(
            len(self.initial),
            len(self.c3_terms) if self.c3_terms is not None else 0)
        src = bucket_gen(self.n, self.m, self.p, self.world_record - 1,
                         seed=None, cap=CAP_MOVES,
                         arr=seed_highwater +
                         max(80, ESCAPE_MAX_DELTA[self.escape_kind] + 8),
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
        seed_highwater = max(
            len(self.initial),
            len(self.c3_terms) if self.c3_terms is not None else 0)
        cap = seed_highwater + max(32, ESCAPE_MAX_DELTA[self.escape_kind] + 12)
        wpg = 16
        while cap * wpg * mask_bytes * 3 > 32768:
            wpg //= 2
        if wpg < 1:
            raise ValueError("GPU scheme capacity exceeds Metal threadgroup memory")
        nw = self.gpu_walkers - (self.gpu_walkers % wpg)
        if nw <= 0:
            raise ValueError(f"gpu_walkers must be at least the generated WPG ({wpg})")
        self.gpu_walkers = nw
        self.gpu_wpg = wpg
        # One scheduler quantum is one hardware SIMD-group.  It is a legal
        # multiple of every generated cal2zone WPG and maps directly to one
        # cooperative trajectory or one MITM threadgroup.
        self.gpu_allocation_quantum = 32
        nw -= nw % self.gpu_allocation_quantum
        if nw <= 0:
            raise ValueError("gpu_walkers must provide at least one 32-lane SIMD-group")
        self.gpu_walkers = nw
        if self.gpu_policy == "adaptive" and nw < len(self.gpu_roles) * self.gpu_allocation_quantum:
            raise ValueError(
                f"adaptive GPU policy needs at least "
                f"{len(self.gpu_roles) * self.gpu_allocation_quantum} walkers "
                f"({len(self.gpu_roles)} roles times 32 lanes)")
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
        if self.gpu_policy == "adaptive" and "simd" in self.gpu_roles:
            seed_rank = max(len(self.initial),
                            len(self.c3_terms) if self.c3_terms is not None else 0)
            simd_cap = capacity_for_rank(seed_rank, margin=16, reserve=24)
            simd_steps = min(self.gpu_steps, 100_000)
            simd_config = SimdgroupConfig(
                n=self.n, cap=simd_cap, groups=1, steps=simd_steps,
                dispatches=5, margin=16, mode="auto")
            adapter = CooperativeSimdRelay(self.dir, simd_config, root=ROOT)
            adapter.build()
            self.gpu_engine_adapters["simd"] = adapter
            self.log(f"GPU cooperative SIMD engine compiled "
                     f"(cap={simd_cap}, mode={simd_config.selected_mode})")
        if self.gpu_policy == "adaptive" and "symmetry" in self.gpu_roles:
            c3_rank = len(self.c3_terms)
            c3_rank = max(
                len(entry.scheme) for entry in self._mixed_portfolio(self.c3_terms)
                if entry.profile["c3"])
            c3_band = 15
            c3_cap = c3_capacity_for_rank(c3_rank, band=c3_band, reserve=8)
            c3_steps = min(self.gpu_steps, 20_000)
            c3_dispatches = max(1, min(5, self.gpu_steps // c3_steps))
            c3_config = C3GpuConfig(
                n=self.n, cap=c3_cap, walkers=32, steps=c3_steps,
                dispatches=c3_dispatches, band=c3_band, plus_period=200)
            adapter = C3GpuRelay(self.dir, c3_config, root=ROOT)
            adapter.build()
            self.gpu_engine_adapters["symmetry"] = adapter
            self.log(f"GPU C3-preserving engine compiled "
                     f"(cap={c3_cap}, band={c3_band})")
        if self.gpu_policy == "adaptive" and "mitm" in self.gpu_roles:
            adapter = GpuMitmFleetAdapter(self.n, max_pool=700)
            adapter.build()
            self.gpu_engine_adapters["mitm"] = adapter
            self.log("GPU 5->4 meet-in-the-middle engine compiled (pool<=700)")

    def _gpu_role_profile(self, role):
        profile = dict(GPU_ROLE_PROFILES[role])
        profile["escapes"] = (self.gpu_escapes if profile["escapes"] == "all"
                              else profile["escapes"])
        return profile

    def _gpu_role_live_path(self, role):
        return os.path.join(self.dir, f"gpu_{role}_live.txt")

    def _write_gpu_role_live(self, role):
        profile = self._gpu_role_profile(role)
        path = self._gpu_role_live_path(role)
        body = (f"{self.gpu_steps} {profile['reseed']} {profile['margin']} "
                f"{profile['workq']} {profile['wanderq']} {profile['wthr']} "
                f"{self.gpu_adapt_generation}\n")
        tmp = path + ".tmp"
        with open(tmp, "w") as stream:
            stream.write(body)
        os.replace(tmp, path)
        return path

    def _gpu_role_seed_path(self, role):
        return os.path.join(self.dir, f"gpu_{role}_seed.txt")

    @staticmethod
    def _portfolio_bank(entries, predicate):
        """Rank exact bank entries by search utility while retaining diversity."""
        candidates = [entry for entry in entries if predicate(tuple(entry.recipe))]
        candidates.sort(key=lambda entry: (
            entry.profile["rank"], -entry.profile["flip_pairs"],
            entry.profile["density"], -entry.profile["distance"], entry.scheme))
        seen = set()
        bank = []
        for entry in candidates:
            scheme = tuple(entry.scheme)
            if scheme in seen:
                continue
            seen.add(scheme)
            bank.append({"terms": list(scheme),
                         "recipe": tuple(entry.recipe) or ("base",)})
        return bank

    def _write_gpu_role_seed_slot(self, role, ordinal):
        bank = self.gpu_role_seed_banks.get(role)
        if not bank:
            raise RuntimeError(f"GPU role {role} has no exact seed bank")
        slot = ordinal % len(bank)
        selected = bank[slot]
        terms = list(selected["terms"])
        base = list(self.best[1] if self.best is not None else self.initial)
        if not self.exact_valid(len(terms), terms):
            raise RuntimeError(f"GPU role {role} seed failed exact verification")
        if role == "symmetry" and not is_c3_closed(terms, self.n):
            raise RuntimeError("C3 GPU role bank contained a non-C3 seed")
        write_dump(terms, self._gpu_role_seed_path(role))
        self.gpu_role_seed_profiles[role] = {
            "rank": len(terms), "bits": self.score(len(terms), terms)["bits"],
            "c3": bool(self.n == self.m == self.p and
                       is_c3_closed(terms, self.n)),
            "distance": self.scheme_distance(frozenset(terms), frozenset(base)),
            "recipe": "+".join(selected["recipe"]),
            "slot": slot, "bank_size": len(bank),
        }
        return terms

    def refresh_gpu_role_seeds(self, preserve_novelty=True):
        """Materialize exact role-specific seeds from the current mixed banks."""
        base = list(self.best[1] if self.best is not None else self.initial)
        ordinary = self._mixed_portfolio(base)
        symmetric = (self._mixed_portfolio(self.c3_terms)
                     if self.c3_terms is not None else ())
        base_entry = {"terms": base, "recipe": ("base",)}
        pools = list(ordinary) + list(symmetric)
        banks = {
            "rank": [base_entry], "density": [base_entry],
            "simd": [base_entry], "mitm": [base_entry],
            # The cal2zone split role constructs hundreds of distinct +1
            # identities internally at each reseed.  Feeding it an already
            # split seed would silently turn this into a depth-two lane.
            "split": [base_entry],
            "break": self._portfolio_bank(
                pools, lambda recipe: recipe == ("break",)),
            "orbit": self._portfolio_bank(
                pools, lambda recipe: recipe == ("orbit-split",)),
            "polarize": self._portfolio_bank(
                pools, lambda recipe: recipe == ("polarize",)),
            "compose": self._portfolio_bank(
                pools, lambda recipe: len(recipe) >= 2),
        }
        if self.c3_terms is not None:
            symmetric_c3 = [entry for entry in symmetric if entry.profile["c3"]]
            banks["symmetry"] = self._portfolio_bank(
                symmetric_c3, lambda recipe: True)
        for role in ("split", "break", "orbit", "polarize", "compose",
                     "symmetry"):
            if role in self.gpu_roles and not banks.get(role):
                banks[role] = [base_entry]
        novelty_path = self._gpu_role_seed_path("novelty")
        novelty = None
        if preserve_novelty and os.path.exists(novelty_path):
            novelty_rank, novelty_terms = read_dump(novelty_path)
            if (novelty_rank is not None and
                    self.exact_valid(novelty_rank, novelty_terms)):
                novelty = list(novelty_terms)
        banks["novelty"] = [{"terms": novelty or base,
                             "recipe": ("archive",) if novelty else ("base",)}]
        self.gpu_role_seed_banks = {
            role: banks[role] for role in self.gpu_roles if banks.get(role)
        }
        self.gpu_role_seed_profiles = {}
        for role in self.gpu_roles:
            self._write_gpu_role_seed_slot(
                role, self.gpu_role_launches.get(role, 0))

    def _initial_gpu_role_allocation(self):
        quantum = self.gpu_allocation_quantum
        chunks = self.gpu_walkers // quantum
        allocation = {role: 1 for role in self.gpu_roles}
        remaining = chunks - len(self.gpu_roles)
        weights = {role: float(self.gpu_role_weights.get(role, 0.0))
                   for role in self.gpu_roles}
        total = sum(weights.values())
        raw = {role: remaining * weights[role] / total for role in self.gpu_roles}
        for role in self.gpu_roles:
            allocation[role] += int(raw[role])
        left = chunks - sum(allocation.values())
        order = sorted(self.gpu_roles,
                       key=lambda role: (-(raw[role] - int(raw[role])),
                                         self.gpu_roles.index(role)))
        for role in order[:left]:
            allocation[role] += 1
        return {role: value * quantum for role, value in allocation.items()}

    def gpu_role_scores(self):
        """UCB1 scores normalized by completed threadgroup-epochs.

        A threadgroup-epoch with no exact candidate is still a zero-reward
        pull.  Exposure normalization prevents an already-large role from
        receiving free positive feedback merely because it had more lanes.
        The exploration bonus and lane floor keep every role live, while rank
        drops dominate the bounded novelty/density rewards.
        """
        total = sum(stats["lane_epochs"] for stats in self.gpu_role_stats.values())
        scores = {}
        for role in self.gpu_roles:
            stats = self.gpu_role_stats[role]
            pulls = stats["lane_epochs"]
            if pulls == 0:
                scores[role] = float("inf")
            else:
                mean = stats["reward"] / pulls
                bonus = math.sqrt(2.0 * math.log(max(2, total)) / pulls)
                scores[role] = mean + bonus
        return scores

    def gpu_lane_allocation(self):
        """Allocate WPG-sized chunks, with one exploration floor per role."""
        quantum = self.gpu_allocation_quantum
        chunks = self.gpu_walkers // quantum
        if chunks < len(self.gpu_roles):
            raise ValueError("not enough GPU threadgroups for all adaptive roles")
        allocation = {role: 1 for role in self.gpu_roles}
        scores = self.gpu_role_scores()
        if any(math.isinf(value) for value in scores.values()):
            # Cold start uses evidence-guided fixed fractions.  Subsequent
            # epochs switch to measured UCB productivity.
            return self._initial_gpu_role_allocation()
        else:
            # Diminishing returns prevents a single lucky role from consuming
            # the entire GPU while still making productivity affect lane share.
            while sum(allocation.values()) < chunks:
                role = max(self.gpu_roles,
                           key=lambda item: (scores[item] /
                                             math.sqrt(allocation[item]),
                                             -self.gpu_roles.index(item)))
                allocation[role] += 1
        return {role: value * quantum for role, value in allocation.items()}

    def _launch_gpu_role(self, role, lanes):
        launch_number = self.gpu_role_launches.get(role, 0) + 1
        self._write_gpu_role_seed_slot(role, launch_number - 1)
        seed_path = self._gpu_role_seed_path(role)
        out_path = os.path.join(self.dir, f"gpu_{role}_best.txt")
        self.gpu_role_exit_reported.discard(role)
        if role == "simd":
            adapter = self.gpu_engine_adapters[role]
            groups = max(1, lanes // 32)
            adapter.config = replace(adapter.config, groups=groups)
            adapter.launch(seed_path, out_path)
            self.gpu_procs[role] = adapter.process
            self.gpu_role_plans[role] = {
                "engine": "cooperative-simd", "groups": groups,
                "steps": adapter.config.steps,
                "dispatches": adapter.config.dispatches,
                "mode": adapter.config.selected_mode,
            }
            self.gpu_role_launches[role] = launch_number
            self.gpu_role_failures[role] = 0
            self.gpu_role_retry_at.pop(role, None)
            return
        if role == "symmetry":
            adapter = self.gpu_engine_adapters[role]
            adapter.config = replace(adapter.config, walkers=lanes)
            adapter.launch(seed_path, out_path)
            self.gpu_procs[role] = adapter.process
            self.gpu_role_plans[role] = {
                "engine": "c3-preserving", "walkers": lanes,
                "steps": adapter.config.steps,
                "dispatches": adapter.config.dispatches,
                "band": adapter.config.band,
            }
            self.gpu_role_launches[role] = launch_number
            self.gpu_role_failures[role] = 0
            self.gpu_role_retry_at.pop(role, None)
            return
        if role == "mitm":
            adapter = self.gpu_engine_adapters[role]
            # Convert the assigned physical-lane share into a bounded amount of
            # regular pair/probe work.  The cap keeps a single finite surgery
            # round short enough to participate in the adaptive epoch.
            logical_threads = lanes * min(self.gpu_steps, 4096)
            nearby = 1 + ((launch_number - 1) % 3)
            plan = adapter.launch(
                seed_path, out_path, lane_budget=logical_threads, nearby=nearby)
            self.gpu_procs[role] = adapter.process
            self.gpu_role_plans[role] = {
                "engine": "gpu-mitm-5-to-4", "nearby": nearby,
                "logical_threads": plan.logical_threads,
                "subsets": plan.subsets, "pool": plan.pool,
                "subset_offset": adapter.subset_offset,
                "dispatched_threads": plan.dispatched_threads,
            }
            self.gpu_role_launches[role] = launch_number
            self.gpu_role_failures[role] = 0
            self.gpu_role_retry_at.pop(role, None)
            return
        open(out_path, "w").close()
        log = open(os.path.join(self.dir, f"gpu_{role}_relay.log"), "a")
        self.gpu_logs[role] = log
        profile = self._gpu_role_profile(role)
        live_path = self._write_gpu_role_live(role)
        argv = [
            self.gpu_bin, seed_path, out_path,
            str(self.n), str(self.m), str(self.p), "x", "0",
            str(self.gpu_steps), str(profile["reseed"]), str(profile["margin"]),
            str(profile["workq"]), str(profile["wanderq"]), str(profile["wthr"]),
            str(lanes), live_path, str(profile["escapes"]),
        ]
        try:
            self.gpu_procs[role] = subprocess.Popen(
                argv, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
            self.gpu_role_plans[role] = {
                "engine": "cal2zone", "lanes": lanes,
                "reseed": profile["reseed"], "margin": profile["margin"],
                "escapes": profile["escapes"],
            }
            self.gpu_role_launches[role] = launch_number
            self.gpu_role_failures[role] = 0
            self.gpu_role_retry_at.pop(role, None)
        except Exception:
            self.gpu_logs.pop(role, None)
            log.close()
            raise

    @staticmethod
    def _stop_gpu_process(proc):
        if proc is None or proc.poll() is not None:
            return
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=5)

    def _stop_gpu_role(self, role):
        adapter = self.gpu_engine_adapters.get(role)
        if adapter is not None:
            adapter.terminate()
        self._stop_gpu_process(self.gpu_procs.pop(role, None))
        log = self.gpu_logs.pop(role, None)
        if log is not None:
            log.close()

    def _defer_gpu_role_retry(self, role):
        failures = self.gpu_role_failures.get(role, 0) + 1
        self.gpu_role_failures[role] = failures
        self.gpu_role_retry_at[role] = (
            time.time() + min(300, 5 * (2 ** min(failures - 1, 6))))

    def repair_gpu_roles(self, now=None):
        """Relaunch missing adaptive roles without discarding completed outputs."""
        if self.gpu_policy != "adaptive" or self.stop_requested.is_set():
            return
        now = time.time() if now is None else now
        for role in self.gpu_roles:
            if role in self.gpu_procs or now < self.gpu_role_retry_at.get(role, 0):
                continue
            try:
                self._launch_gpu_role(
                    role, self.gpu_role_allocations.get(
                        role, self.gpu_allocation_quantum))
                self.log(f"GPU {role} role recovered after a stopped worker")
            except Exception as exc:
                self._defer_gpu_role_retry(role)
                self.log(f"GPU {role} role recovery failed: {exc}")

    def launch_gpu_relay(self):
        best_path = os.path.join(self.dir, "best.txt")
        if self.gpu_policy == "adaptive":
            self.refresh_gpu_role_seeds(preserve_novelty=False)
            self.gpu_role_allocations = self._initial_gpu_role_allocation()
            self.gpu_last_adapt = time.time()
            for role, lanes in self.gpu_role_allocations.items():
                self._launch_gpu_role(role, lanes)
            detail = ", ".join(f"{role}={lanes}"
                               for role, lanes in self.gpu_role_allocations.items())
            self.log(f"GPU adaptive roles launched: {detail}")
            return
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

    def _gpu_flip_pairs(self, terms):
        """Count available equal-factor pair/axis choices in a scheme."""
        pairs = 0
        for left_index, left in enumerate(terms):
            for right in terms[left_index + 1:]:
                pairs += sum(a == b for a, b in zip(left, right))
        return pairs

    @staticmethod
    def _gpu_dominates(left, right):
        no_worse = (left["bits"] <= right["bits"] and
                    left["flip_pairs"] >= right["flip_pairs"] and
                    left["novelty"] >= right["novelty"])
        strict = (left["bits"] < right["bits"] or
                  left["flip_pairs"] > right["flip_pairs"] or
                  left["novelty"] > right["novelty"])
        return no_worse and strict

    def _gpu_metrics(self, rank, terms):
        termset = frozenset(terms)
        references = []
        if self.best is not None and self.best[0] == rank:
            references.append(frozenset(self.best[1]))
        references.extend(entry["termset"] for entry in self.gpu_pareto.values()
                          if entry["rank"] == rank)
        novelty = (min(self.scheme_distance(termset, reference)
                       for reference in references)
                   if references else 2 * rank)
        return {"bits": self.score(rank, terms)["bits"],
                "flip_pairs": self._gpu_flip_pairs(terms),
                "novelty": novelty}

    def gpu_pareto_admit(self, rank, terms, role):
        """Retain a bounded nondominated set of exact GPU frontier outputs."""
        if self.gpu_policy != "adaptive":
            return False, None
        if not self.exact_valid(rank, terms):
            return False, None
        key = self.canonical(terms)
        if key in self.gpu_pareto:
            return False, self.gpu_pareto[key]
        metrics = self._gpu_metrics(rank, terms)
        entry = {"rank": rank, "terms": list(terms), "termset": frozenset(terms),
                 "role": role, **metrics}
        if (self.best is not None and rank == self.best[0] and
                key == self.canonical(self.best[1])):
            # A bounded engine returning its input proves liveness, not search
            # productivity.  Do not let role ordering turn the shared baseline
            # into a novelty reward for whichever adapter is polled first.
            self.gpu_pareto_rejections += 1
            return False, entry
        ranks = {entry["rank"] for entry in self.gpu_pareto.values()}
        if ranks and rank > min(ranks):
            self.gpu_pareto_rejections += 1
            return False, entry
        if ranks and rank < min(ranks):
            self.gpu_pareto = {
                key: entry for key, entry in self.gpu_pareto.items()
                if entry["rank"] == rank
            }
        if any(self._gpu_dominates(existing, entry)
               for existing in self.gpu_pareto.values()):
            self.gpu_pareto_rejections += 1
            return False, entry
        dominated = [existing_key for existing_key, existing in self.gpu_pareto.items()
                     if self._gpu_dominates(entry, existing)]
        for existing_key in dominated:
            del self.gpu_pareto[existing_key]
            self.gpu_pareto_evictions += 1
        self.gpu_pareto[key] = entry
        if len(self.gpu_pareto) > self.gpu_novelty_size:
            # Deterministic diversity-biased truncation of an otherwise
            # nondominated set: first sacrifice low novelty, then high density,
            # then low connectivity.
            victim = min(self.gpu_pareto,
                         key=lambda item: (self.gpu_pareto[item]["novelty"],
                                           -self.gpu_pareto[item]["bits"],
                                           self.gpu_pareto[item]["flip_pairs"], item))
            del self.gpu_pareto[victim]
            self.gpu_pareto_evictions += 1
            if victim == key:
                self.gpu_pareto_rejections += 1
                return False, entry
        self.gpu_pareto_admissions += 1
        if "novelty" in self.gpu_roles:
            self.gpu_role_seed_banks["novelty"] = [
                {"terms": list(terms), "recipe": ("archive",)}]
            self._write_gpu_role_seed_slot("novelty", 0)
        self.gpu_adapt_generation += 1
        if "novelty" in self.gpu_procs:
            self._write_gpu_role_live("novelty")
        return True, entry

    def _reward_gpu_role(self, role, rank, entry, admitted):
        stats = self.gpu_role_stats[role]
        stats["candidates"] += 1
        best_rank = self.best[0] if self.best is not None else rank
        rank_gain = max(0, best_rank - rank)
        reward = 10.0 * rank_gain
        if rank_gain:
            stats["rank_drops"] += 1
        elif self.best is not None and rank == best_rank:
            current_bits = self.score(*self.best)["bits"]
            bit_gain = max(0, current_bits - entry["bits"])
            if bit_gain:
                stats["density_improvements"] += 1
                reward += min(2.0, 2.0 * bit_gain / max(1, current_bits))
        if admitted:
            stats["pareto"] += 1
            reward += 1.0 + min(1.0, entry["novelty"] / max(1, 2 * rank))
        stats["reward"] += reward
        stats["epoch_reward"] += reward

    def _consider_c3_leader(self, rank, terms, refresh=True):
        """Advance the independent symmetry branch even behind the global cost lead."""
        if not self.exact_valid(rank, terms) or not is_c3_closed(terms, self.n):
            return False
        candidate_key = (rank, self.score(rank, terms)["bits"],
                         self.canonical(terms))
        if self.c3_best is not None:
            current_rank, current_terms = self.c3_best
            current_key = (current_rank,
                           self.score(current_rank, current_terms)["bits"],
                           self.canonical(current_terms))
            if candidate_key >= current_key:
                return False
        self.c3_terms = list(terms)
        self.c3_best = (rank, list(terms))
        self.refresh_cpu_symmetry_bank()
        if refresh:
            self.refresh_gpu_role_seeds(preserve_novelty=True)
            self.gpu_adapt_generation += 1
            for engine_role in self.gpu_roles:
                if engine_role in self.gpu_procs and engine_role in GPU_ROLE_PROFILES:
                    self._write_gpu_role_live(engine_role)
        self.log(f"GPU C3 LEADER rank={rank} bits={candidate_key[1]} exact=1 c3=1")
        return True

    def _adaptive_gpu_candidate(self, role, max_rank):
        rank, terms = None, None
        if role in ("simd", "symmetry"):
            adapter = self.gpu_engine_adapters[role]
            try:
                candidate = adapter.poll()
            except Exception as exc:
                self.log(f"GPU {role} relay rejected: {exc}")
                self._stop_gpu_role(role)
                self._defer_gpu_role_retry(role)
                return None
            if candidate is None:
                return None
            rank, terms = candidate.rank, list(candidate.terms)
            if role == "symmetry":
                self._consider_c3_leader(rank, terms)
            # These engines are deliberately bounded.  Relaunch immediately so
            # their assigned share stays occupied between allocator epochs.
            if not self.stop_requested.is_set():
                try:
                    self._launch_gpu_role(
                        role, self.gpu_role_allocations.get(
                            role, self.gpu_allocation_quantum))
                except Exception as exc:
                    self.log(f"GPU {role} relay could not relaunch: {exc}")
                    self._stop_gpu_role(role)
                    self._defer_gpu_role_retry(role)
        elif role == "mitm":
            adapter = self.gpu_engine_adapters[role]
            try:
                state = adapter.poll()
                if state["running"]:
                    return None
                if state["returncode"] not in (0, None):
                    raise RuntimeError(
                        f"worker exited {state['returncode']}; see {state['log']}")
                if state["hit"]:
                    rank, terms = read_dump(state["output"])
                # A miss is useful negative work, and the next bounded launch
                # rotates the candidate-neighborhood depth.
                if not self.stop_requested.is_set():
                    self._launch_gpu_role(
                        role, self.gpu_role_allocations.get(
                            role, self.gpu_allocation_quantum))
            except Exception as exc:
                self.log(f"GPU mitm relay rejected: {exc}")
                self._stop_gpu_role(role)
                self._defer_gpu_role_retry(role)
                return None
        else:
            path = os.path.join(self.dir, f"gpu_{role}_best.txt")
            rank, terms = read_dump(path)
        proc = self.gpu_procs.get(role)
        if proc is not None and proc.poll() is not None:
            if role not in self.gpu_role_exit_reported:
                self.gpu_role_exit_reported.add(role)
                self.log(f"GPU {role} relay exited with status {proc.returncode}; "
                         f"see gpu_{role}_relay.log")
            # Preserve the just-read output, then rotate this role to its next
            # exact bank slot.  This also repairs clean finite host exits.
            self._stop_gpu_role(role)
            if not self.stop_requested.is_set():
                try:
                    self._launch_gpu_role(
                        role, self.gpu_role_allocations.get(
                            role, self.gpu_allocation_quantum))
                except Exception as exc:
                    self._defer_gpu_role_retry(role)
                    self.log(f"GPU {role} relay restart failed: {exc}")
        if rank is None or rank > max_rank:
            return None
        digest = hashlib.sha256(repr((rank, terms)).encode()).hexdigest()
        role_valid = self.exact_valid(rank, terms)
        if role == "symmetry" and role_valid:
            role_valid = is_c3_closed(terms, self.n)
        if not role_valid:
            if digest != self.gpu_role_invalid.get(role):
                self.gpu_role_invalid[role] = digest
                self.invalid_candidates += 1
                requirement = " exact/C3" if role == "symmetry" else " exact"
                self.log(f"REJECTED invalid{requirement} rank={rank} from GPU/{role}")
            return None
        self.gpu_role_invalid.pop(role, None)
        if digest == self.gpu_role_seen.get(role):
            return None
        self.gpu_role_seen[role] = digest
        admitted, entry = self.gpu_pareto_admit(rank, terms, role)
        self._reward_gpu_role(role, rank, entry, admitted)
        return rank, 0, terms, f"gpu/{role}"

    def gpu_candidates(self, max_rank):
        if not self.gpu:
            return []
        if self.gpu_policy == "adaptive":
            self.repair_gpu_roles()
            roles = (self.gpu_roles if not self.stop_requested.is_set() else
                     tuple(role for role in self.gpu_roles
                           if role in GPU_ROLE_PROFILES))
            return [candidate for role in roles
                    for candidate in [self._adaptive_gpu_candidate(role, max_rank)]
                    if candidate is not None]
        candidate = self.gpu_candidate(max_rank)
        return [candidate] if candidate is not None else []

    def rebalance_gpu_roles(self, now=None, force=False):
        if self.gpu_policy != "adaptive" or not self.gpu_procs:
            return False
        now = time.time() if now is None else now
        if not force and now - self.gpu_last_adapt < self.gpu_adapt_secs:
            return False
        for role, stats in self.gpu_role_stats.items():
            stats["epochs"] += 1
            stats["lane_epochs"] += max(
                1, self.gpu_role_allocations.get(
                    role, self.gpu_allocation_quantum) // self.gpu_allocation_quantum)
            stats["epoch_reward"] = 0.0
        allocation = self.gpu_lane_allocation()
        self.gpu_last_adapt = now
        if allocation == self.gpu_role_allocations:
            return False
        old = dict(self.gpu_role_allocations)
        self.gpu_adapt_generation += 1
        for role in self.gpu_roles:
            if allocation[role] != old.get(role):
                self._stop_gpu_role(role)
                try:
                    self._launch_gpu_role(role, allocation[role])
                except Exception as exc:
                    self._defer_gpu_role_retry(role)
                    self.log(f"GPU {role} rebalance launch failed: {exc}")
        self.gpu_role_allocations = allocation
        detail = ", ".join(f"{role}={old.get(role, 0)}->{allocation[role]}"
                           for role in self.gpu_roles)
        self.log(f"GPU BANDIT rebalance: {detail}")
        return True

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

    @staticmethod
    def _empty_cpu_cohort():
        return {
            "launches": 0, "moves": 0, "cpu_seconds": 0.0,
            "completions": 0, "cycleouts": 0, "exits": 0,
            "rank_drops": 0, "tie_improvements": 0,
            "near_admissions": 0, "frontier_returns": 0,
            "quarantines": 0, "migrations": 0, "sources": {},
        }

    @staticmethod
    def _cpu_cohort_status(stats):
        moves = stats["moves"]
        billions = moves / 1_000_000_000
        seconds = stats["cpu_seconds"]
        productive = (stats["rank_drops"] + stats["tie_improvements"] +
                      stats["near_admissions"])
        return {
            **stats,
            "cpu_seconds": round(seconds, 3),
            "move_billions": round(billions, 6),
            "moves_per_second": round(moves / seconds, 1) if seconds > 0 else None,
            "productive_per_billion": round(productive / billions, 4)
            if billions > 0 else None,
            "rank_drops_per_billion": round(stats["rank_drops"] / billions, 4)
            if billions > 0 else None,
        }

    def _cpu_cohort_key(self, i):
        key = self.cpu_launch_cohorts[i]
        if key is not None:
            return key
        return f"{self.cpu_door_roles[i]}/{CPU_ZONE_NAMES[self.cpu_zone_profiles[i]]}"

    def _cpu_cohort(self, i):
        key = self._cpu_cohort_key(i)
        if key not in self.cpu_cohort_stats:
            self.cpu_cohort_stats[key] = self._empty_cpu_cohort()
        return self.cpu_cohort_stats[key]

    def credit_cpu_cohort(self, i, field, amount=1):
        if not 0 < i <= self.nw:
            return False
        stats = self._cpu_cohort(i)
        if field not in stats or isinstance(stats[field], dict):
            raise ValueError(f"unknown numeric CPU cohort field {field!r}")
        stats[field] += amount
        return True

    @staticmethod
    def _line_fields(line):
        fields = {}
        for token in line.split():
            if "=" not in token:
                continue
            key, value = token.split("=", 1)
            fields[key] = value.rstrip(",")
        return fields

    def _walker_log_snapshot(self, i):
        """Parse a bounded active-log tail into current walker telemetry."""
        result = {
            "rank": self.cpu_launch_seed_ranks[i],
            "current_rank": self.cpu_launch_seed_ranks[i],
            "mv": 0, "band": None, "threshold": None, "verify": None,
        }
        path = os.path.join(self.dir, f"cpu_{i}.log")
        try:
            lines = read_tail_lines(path)
        except (OSError, UnicodeError):
            return result
        for raw in lines:
            line = raw.strip()
            fields = self._line_fields(line)
            try:
                if line.startswith("seed rank="):
                    result["rank"] = int(fields["rank"])
                    result["current_rank"] = result["rank"]
                    result["verify"] = int(fields.get("verify", 0))
                elif line.startswith("mv="):
                    result["mv"] = max(result["mv"], int(fields["mv"]))
                    result["rank"] = int(fields.get("best", result["rank"]))
                    result["current_rank"] = int(fields.get("cur", result["current_rank"]))
                    result["verify"] = int(fields.get("v", result["verify"] or 0))
                elif line.startswith("IMP "):
                    result["mv"] = max(result["mv"], int(fields["mv"]))
                    result["rank"] = int(fields["rank"])
                    result["current_rank"] = result["rank"]
                    result["band"] = int(fields["band"])
                elif line.startswith("BAND "):
                    result["mv"] = max(result["mv"], int(fields["mv"]))
                    result["current_rank"] = int(fields["rank"])
                    result["band"] = int(fields["band"])
                elif line.startswith("WTHR "):
                    result["mv"] = max(result["mv"], int(fields["mv"]))
                    result["band"] = int(fields["band"])
                    result["threshold"] = int(fields["thr"])
                elif line.startswith("CYCLEOUT "):
                    result["mv"] = max(result["mv"], int(fields["mv"]))
                    result["current_rank"] = int(fields["rank"])
                elif line.startswith("DONE best="):
                    result["rank"] = int(fields["best"])
                    result["verify"] = int(fields.get("verify", result["verify"] or 0))
                elif line.startswith("BSTART "):
                    result["band"] = int(line.split()[-1])
            except (KeyError, TypeError, ValueError):
                continue
        return result

    def _account_cpu_walker(self, i, now=None, snapshot=None):
        """Update launch/cohort exposure once and return a status row."""
        now = time.time() if now is None else now
        snapshot = self._walker_log_snapshot(i) if snapshot is None else snapshot
        launch_id = self.launch_count[i]
        mv = max(0, int(snapshot.get("mv") or 0))
        process = self.procs[i]
        exit_code = process.poll() if process is not None else self.cpu_last_exit_code[i]
        if process is None and self.stop_requested.is_set():
            exit_code = None
        running = process is not None and exit_code is None
        if process is None:
            process_state = "stopped" if launch_id else "not-started"
        elif running:
            process_state = "running"
        else:
            process_state = "exited"
            self.cpu_last_exit_code[i] = exit_code

        if launch_id and not self.cpu_accounting_closed[i]:
            stats = self._cpu_cohort(i)
            if self.cpu_last_accounted_at[i]:
                stats["cpu_seconds"] += max(0.0, now - self.cpu_last_accounted_at[i])
            if mv >= self.cpu_last_accounted_mv[i]:
                stats["moves"] += mv - self.cpu_last_accounted_mv[i]
            self.cpu_last_accounted_mv[i] = mv
            self.cpu_last_accounted_at[i] = now
            if process is not None and not running:
                self.cpu_accounting_closed[i] = True

        if self.cpu_sample_launch[i] != launch_id:
            self.cpu_sample_launch[i] = launch_id
            self.cpu_sample_mv[i] = mv
            self.cpu_sample_at[i] = now
            self.cpu_progress_at[i] = now
            self.cpu_rate_mps[i] = None
        elif mv > self.cpu_sample_mv[i] and now > self.cpu_sample_at[i]:
            instant = (mv - self.cpu_sample_mv[i]) / (now - self.cpu_sample_at[i])
            old_rate = self.cpu_rate_mps[i]
            self.cpu_rate_mps[i] = instant if old_rate is None else 0.7 * old_rate + 0.3 * instant
            self.cpu_sample_mv[i] = mv
            self.cpu_sample_at[i] = now
            self.cpu_progress_at[i] = now

        progress_at = self.cpu_progress_at[i] or self.launched_at[i] or now
        rank = snapshot.get("rank")
        current_rank = snapshot.get("current_rank")
        return {
            "id": i, "rank": "?" if rank is None else rank,
            "current_rank": "?" if current_rank is None else current_rank,
            "mv": mv, "rate_mps": self.cpu_rate_mps[i],
            "progress_age": round(max(0.0, now - progress_at), 1),
            "since_reseed": (round(now - self.reseeded_at[i], 1)
                             if self.reseeded_at[i] else 0.0),
            "door": self.cpu_door_roles[i],
            "zone": CPU_ZONE_NAMES[self.cpu_zone_profiles[i]],
            "source": self.cpu_launch_sources[i],
            "work_moves": self.work_zone_moves[
                self.cpu_zone_profiles[i] % len(self.work_zone_moves)],
            "wander_moves": self.wander_zone_moves[
                self.cpu_zone_profiles[i] % len(self.wander_zone_moves)],
            "band": snapshot.get("band"),
            "threshold": snapshot.get("threshold"),
            "verify": snapshot.get("verify"),
            "running": running, "process_state": process_state,
            "pid": process.pid if process is not None else None,
            "exit_code": exit_code, "launch_count": launch_id,
            "seed_rank": self.cpu_launch_seed_ranks[i],
            "seed_digest": self.cpu_launch_seed_digests[i],
            "seed_c3": self.cpu_launch_seed_c3[i],
        }

    def launch(self, i, salt, seed, source=None):
        if self.launch_count[i]:
            self._account_cpu_walker(i)
        active_near = self.cpu_active_near_seed[i]
        if (active_near is not None and
                self.canonical(seed) != active_near.terms):
            self.cpu_active_near_seed[i] = None
        if i in self.logs:
            try:
                self.logs[i].close()
            except Exception:
                pass
        self.launch_count[i] += 1
        launch_id = self.launch_count[i]
        door = self.cpu_door_roles[i]
        zone = CPU_ZONE_NAMES[self.cpu_zone_profiles[i]]
        source = door if source is None else source
        seed_key = self.canonical(seed)
        self.cpu_launch_sources[i] = source
        self.cpu_launch_seed_ranks[i] = len(seed)
        self.cpu_launch_seed_digests[i] = hashlib.sha256(
            repr(seed_key).encode()).hexdigest()[:12]
        self.cpu_launch_seed_c3[i] = bool(
            self.n == self.m == self.p and is_c3_closed(seed, self.n))
        self.cpu_launch_cohorts[i] = f"{door}/{zone}"
        cohort = self._cpu_cohort(i)
        cohort["launches"] += 1
        cohort["sources"][source] = cohort["sources"].get(source, 0) + 1
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
        profile_index = self.cpu_zone_profiles[i]
        work_moves = self.work_zone_moves[profile_index % len(self.work_zone_moves)]
        wander_moves = self.wander_zone_moves[profile_index % len(self.wander_zone_moves)]
        self.cpu_door_launches[door] = self.cpu_door_launches.get(door, 0) + 1
        near_base_rank = self.best[0] if self.best is not None else self.world_record
        # launch_id is essential: a leader/anchor cohort may leave every global
        # restart counter unchanged, and would otherwise replay the identical
        # RNG stream after every CYCLEOUT despite the parameterized generator.
        runtime_seed = (i * 97 + 13 + salt * 100_003 +
                        launch_id * 1_000_000_007) & ((1 << 62) - 1)
        self.procs[i] = subprocess.Popen(
            [self.bin, str(runtime_seed), self.dump_file(i),
             os.path.join(self.spool, f"cpu{i}l{launch_id}"),
             os.path.join(self.spool, f"tie{i}l{launch_id}"),
             self.reseed_file(i), str(self.cycles), str(work_moves),
             str(wander_moves), os.path.join(self.spool, f"near{i}l{launch_id}"),
             str(near_base_rank)],
            stdout=lf, stderr=subprocess.STDOUT)
        self.launched_at[i] = time.time()
        self.reseeded_at[i] = time.time()
        self.cpu_last_accounted_mv[i] = 0
        self.cpu_last_accounted_at[i] = self.launched_at[i]
        self.cpu_sample_launch[i] = launch_id
        self.cpu_sample_mv[i] = 0
        self.cpu_sample_at[i] = self.launched_at[i]
        self.cpu_progress_at[i] = self.launched_at[i]
        self.cpu_rate_mps[i] = None
        self.cpu_last_exit_code[i] = None
        self.cpu_accounting_closed[i] = False

    def drain_spool(self, max_rank):
        """Return newly completed exact frontier/shoulder snapshots through max_rank.

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
            match = re.match(r"(?:cpu|tie|near)(\d+)(?:l\d+)?_", name)
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
        if pr is not None and self.launch_count[i]:
            self._account_cpu_walker(i)
        if pr and pr.poll() is None:
            pr.kill()
            try:
                pr.wait(timeout=5)
            except subprocess.TimeoutExpired:
                pr.terminate()
                pr.wait(timeout=5)
        if pr is not None:
            self.cpu_last_exit_code[i] = pr.returncode
        self.cpu_accounting_closed[i] = True
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

    def initialize_cpu_seed_banks(self, best_rank=None):
        """Create exact shoulder/symmetry banks around the active frontier."""
        best_rank = (self.best[0] if best_rank is None and self.best is not None
                     else len(self.initial) if best_rank is None else best_rank)
        self.cpu_near_bank = NearFrontierBank(
            self.n, best_rank, capacity=self.cpu_near_size,
            signature_quota=self.cpu_near_signature_quota,
            m=self.m, p=self.p)
        self.hydrate_cpu_near_bank()
        base = list(self.best[1] if self.best is not None else self.initial)
        self.populate_cpu_near_bank(base, source="mixed-bank")
        self.refresh_cpu_symmetry_bank()

    def consider_cpu_near_seed(self, rank, terms, source="candidate", metadata=None,
                               persist=True):
        """Exact-gate R+1/R+2 for restart use without touching global best."""
        if self.cpu_near_bank is None:
            return False
        admitted = self.cpu_near_bank.admit(
            terms, source=source, metadata=metadata, expected_rank=rank)
        if not admitted:
            return False
        self.cpu_near_admissions += 1
        entry = next(
            seed for seed in self.cpu_near_bank.entries(rank - self.cpu_near_bank.best_rank)
            if seed.terms == self.canonical(terms))
        if persist:
            write_dump(
                entry.terms,
                os.path.join(self.record,
                             f"near_rank{entry.rank}_{entry.digest[:12]}.txt"))
        return True

    def consider_cpu_near_observation(self, rank, terms, walker=-1,
                                      source="candidate", metadata=None):
        """Admit a changed walker/spool observation in the active +1/+2 window."""
        if self.cpu_near_bank is None:
            return False
        delta = rank - self.cpu_near_bank.best_rank
        if delta not in (1, 2):
            return False
        observation_slot = (walker, source)
        key = (rank, self.canonical(terms))
        if self.cpu_near_seen.get(observation_slot) == key:
            return False
        self.cpu_near_seen[observation_slot] = key
        details = dict(metadata or {})
        details.setdefault("walker", walker)
        admitted = self.consider_cpu_near_seed(
            rank, terms, source=source, metadata=details)
        if admitted and 0 < walker <= self.nw:
            self.credit_cpu_cohort(walker, "near_admissions")
        return admitted

    def bank_near_observations(self, observations):
        """Route exact observations above the current best into restart banks."""
        if self.cpu_near_bank is None:
            return 0
        admitted = 0
        for rank, walker, terms, source in observations:
            if rank <= self.cpu_near_bank.best_rank:
                continue
            admitted += int(self.consider_cpu_near_observation(
                rank, terms, walker=walker, source=source))
        return admitted

    def mark_cpu_seed_success(self, walker, resulting_rank):
        """Credit a selected shoulder when it returns to the launch frontier."""
        if not 0 < walker < len(self.cpu_active_near_seed):
            return False
        selected = self.cpu_active_near_seed[walker]
        if selected is None or self.cpu_near_bank is None:
            return False
        if resulting_rank > self.cpu_near_bank.best_rank:
            return False
        credited = self.cpu_near_bank.mark_success(selected, resulting_rank)
        self.cpu_active_near_seed[walker] = None
        if credited:
            self.credit_cpu_cohort(walker, "frontier_returns")
        return credited

    def populate_cpu_near_bank(self, base, source="mixed-bank"):
        """Materialize exact +1/+2 shoulders before learned waypoints exist."""
        if (self.cpu_near_bank is None or self.escape_profile != "mixed" or
                not (self.n == self.m == self.p)):
            return 0
        admitted = 0
        base_rank = self.cpu_near_bank.best_rank
        for entry in self._mixed_portfolio(base):
            rank = len(entry.scheme)
            if rank not in (base_rank + 1, base_rank + 2):
                continue
            admitted += int(self.consider_cpu_near_seed(
                rank, entry.scheme, source=source,
                metadata={"recipe": "+".join(entry.recipe) or "base",
                          "synthetic": True}))
        return admitted

    def hydrate_cpu_near_bank(self):
        if self.cpu_near_bank is None:
            return 0
        loaded = 0
        paths = []
        for delta in (1, 2):
            rank = self.cpu_near_bank.best_rank + delta
            paths.extend(glob.glob(os.path.join(
                self.record, f"near_rank{rank}_*.txt")))
        for path in sorted(paths):
            rank, terms = read_dump(path)
            if rank not in (self.cpu_near_bank.best_rank + 1,
                            self.cpu_near_bank.best_rank + 2):
                continue
            if self.consider_cpu_near_seed(
                    rank, terms, source="durable-near",
                    metadata={"path": path}, persist=False):
                loaded += 1
        self.cpu_near_hydrated += loaded
        return loaded

    def refresh_cpu_symmetry_bank(self):
        self.cpu_symmetry_bank = ()
        self.cpu_symmetry_uses = {}
        if (self.escape_profile != "mixed" or self.c3_terms is None or
                not (self.n == self.m == self.p)):
            return
        self.cpu_symmetry_bank = build_symmetry_move_bank(
            self.c3_terms, self.n, self.cpu_symmetry_seed_count)
        self.cpu_symmetry_uses = {
            self.canonical(entry.scheme): 0 for entry in self.cpu_symmetry_bank
        }

    def _select_cpu_symmetry_seed(self, walker):
        if not self.cpu_symmetry_bank:
            return None
        least = min(self.cpu_symmetry_uses.values())
        candidates = [entry for entry in self.cpu_symmetry_bank
                      if self.cpu_symmetry_uses[self.canonical(entry.scheme)] == least]
        entry = min(candidates, key=lambda item: hashlib.blake2b(
            f"{walker}:{self.canonical(item.scheme)!r}".encode(),
            digest_size=16).digest())
        key = self.canonical(entry.scheme)
        self.cpu_symmetry_uses[key] += 1
        return list(entry.scheme), "symmetry:" + "+".join(entry.recipe)

    def cpu_launch_seed(self, walker, trigger, base_terms=None):
        """Select one sticky per-walker door and never stack near/symmetry moves."""
        base = list(base_terms if base_terms is not None else
                    self.best[1] if self.best is not None else self.initial)
        role = self.cpu_door_roles[walker]
        self.cpu_active_near_seed[walker] = None

        # An explicitly selected one-move profile keeps its historical meaning.
        if (self.escape_profile == "single" and
                trigger in ("startup", "cycleout")):
            seed, escape = self.prepare_launch_seed(
                base, trigger, strict=(trigger == "startup"))
            return seed, "single-escape", escape

        if role == "leader":
            return base, "leader", None
        if role == "anchor":
            return list(self.initial), "anchor", None
        role_trigger_enabled = (
            trigger in ("startup", "cycleout") and
            self.escape_enabled_for(trigger))
        role_escape_scheduled = False
        if role_trigger_enabled and role in ("near1", "near2", "symmetry"):
            self.cpu_role_escape_considered[walker] += 1
            ordinal = self.cpu_role_escape_considered[walker]
            role_escape_scheduled = (ordinal - 1) % self.escape_every == 0
        if (role_escape_scheduled and role in ("near1", "near2") and
                self.cpu_near_bank is not None):
            delta = 1 if role == "near1" else 2
            selected = self.cpu_near_bank.select(
                delta, stable_key=(walker, self.launch_count[walker]))
            if selected is not None:
                self.cpu_active_near_seed[walker] = selected
                return list(selected.terms), role, None
        if role_escape_scheduled and role == "symmetry":
            selected = self._select_cpu_symmetry_seed(walker)
            if selected is not None:
                return selected[0], selected[1], None
        if role_trigger_enabled and role == "mixed":
            seed, escape = self.prepare_launch_seed(
                base, trigger, strict=(trigger == "startup"))
            return seed, "mixed", escape
        if role == "frontier":
            seed, source = self.frontier_seed()
            return seed, source, None
        # Empty shoulder/symmetry cohorts fall back to a separated frontier,
        # never to an unverified or recursively escaped seed.
        seed, source = self.frontier_seed()
        return seed, f"{role}-fallback/{source}", None

    def escape_enabled_for(self, trigger):
        enabled = (self.escape_profile == "mixed" or
                   (self.escape_profile == "single" and self.escape_kind != "none"))
        return (enabled and
                (self.escape_at == "both" or self.escape_at == trigger))

    def _mixed_portfolio(self, base):
        """Build and cache an independently exact variable-rank escape bank."""
        key = self.canonical(base)
        cached = self.escape_portfolio_cache.get(key)
        if cached is not None:
            return cached
        entries = build_portfolio(
            base, self.n, count=self.escape_bank_count, per_step=8,
            include_base=True)
        checked = []
        for entry in entries:
            terms = list(entry.scheme)
            if not self.exact_valid(len(terms), terms):
                raise RuntimeError("mixed escape portfolio failed exact verification")
            checked.append(entry)
        if len(checked) < 2:
            raise ValueError("mixed escape portfolio produced no non-base seeds")
        self.escape_portfolio_cache[key] = checked
        return checked

    def _prepare_mixed_escape(self, base, trigger, ordinal):
        entries = self._mixed_portfolio(base)
        slot = (ordinal - 1) % len(entries)
        entry = entries[slot]
        terms = list(entry.scheme)
        recipe = tuple(entry.recipe)
        recipe_name = "+".join(recipe) or "base"
        self.escape_recipe_counts[recipe_name] = (
            self.escape_recipe_counts.get(recipe_name, 0) + 1)
        applied = bool(recipe)
        if applied:
            self.escape_applied += 1
        else:
            self.escape_bypassed += 1
        digest = hashlib.sha256(repr(self.canonical(base)).encode()).hexdigest()[:12]
        metadata = {
            "applied": applied, "trigger": trigger, "kind": "mixed",
            "recipe": recipe, "recipe_name": recipe_name, "slot": slot,
            "base_rank": len(base), "output_rank": len(terms),
            "base_digest": digest, "profile": dict(entry.profile),
        }
        return terms, metadata

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

        if self.escape_profile == "mixed":
            try:
                return self._prepare_mixed_escape(base, trigger, ordinal)
            except ValueError as exc:
                self.escape_skipped += 1
                if strict:
                    raise ValueError(f"startup mixed escape is not applicable: {exc}")
                return base, {"applied": False, "trigger": trigger,
                              "kind": "mixed", "reason": str(exc),
                              "base_rank": len(base)}

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
            if metadata.get("kind") == "mixed" and metadata.get("recipe_name") == "base":
                self.log(f"ESCAPE {metadata['trigger']} w{walker} mixed slot=0 base "
                         f"rank={metadata['base_rank']} exact=1")
                return
            self.log(f"ESCAPE SKIP {metadata['trigger']} w{walker} "
                     f"kind={metadata['kind']} rank={metadata['base_rank']} "
                     f"reason={metadata['reason']}")
            return
        if metadata.get("kind") == "mixed":
            profile = metadata["profile"]
            self.log(
                f"ESCAPE {metadata['trigger']} w{walker} mixed "
                f"slot={metadata['slot']} recipe={metadata['recipe_name']} "
                f"rank={metadata['base_rank']}->{metadata['output_rank']} "
                f"distance={profile['distance']} pairs={profile['flip_pairs']} "
                f"c3={int(profile['c3'])} fixed={profile['fixed']} "
                f"base={metadata['base_digest']} exact=1")
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
            self.escape_profile == "single" and self.escape_kind != "none" and
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
        observations = []
        for i in range(1, self.nw + 1):
            rank, terms = read_dump(self.dump_file(i))
            if (rank is not None and rank <= old_best + 2 and
                    self.exact_valid(rank, terms)):
                observations.append((rank, i, terms, f"final/w{i}"))
                if rank <= old_best:
                    self.mark_cpu_seed_success(i, rank)
        observations.extend(self.drain_spool(old_best + 2))
        observations.extend(self.gpu_candidates(old_best + 2))
        self.bank_near_observations(observations)
        candidates = [item for item in observations if item[0] <= old_best]
        if not candidates:
            return
        frontier_rank = min(item[0] for item in candidates)
        frontier = [item for item in candidates if item[0] == frontier_rank]
        frontier.sort(key=lambda item: (self.score(frontier_rank, item[2])["bits"],
                                        self.canonical(item[2]), item[1]))
        if frontier_rank < old_best:
            # Preserve every old-frontier observation before note_best clears
            # the archive; it becomes useful +1/+2 restart material after a
            # one- or two-rank drop.
            for candidate_rank, _, candidate_terms, source in candidates:
                if candidate_rank == old_best:
                    self.archive_candidate(
                        candidate_rank, candidate_terms, source=source)
            _, finder, terms, _ = frontier[0]
            if self.note_best(frontier_rank, terms, time.time() - start):
                self.credit_cpu_cohort(finder, "rank_drops")
            for _, i, terms, source in frontier[1:]:
                self.archive_candidate(frontier_rank, terms, source=source)
            self.bank_near_observations(
                [item for item in observations if item[0] > frontier_rank])
            self.log(f"FINAL DRAIN: adopted verified rank {frontier_rank}")
        else:
            for _, i, terms, source in frontier:
                self.archive_candidate(frontier_rank, terms, source=source)
            best_tie = min(frontier, key=lambda item: (
                self.score(frontier_rank, item[2])["bits"],
                self.canonical(item[2]), item[1]))
            if self.note_tie_leader(
                    frontier_rank, best_tie[2], time.time() - start):
                self.credit_cpu_cohort(best_tie[1], "tie_improvements")

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
        previous_rank = self.best[0] if self.best is not None else None
        old_frontier = list(self.archive.values())
        if not self.archive_candidate(rank, terms, source="new-best"):
            return False
        self.best = (rank, terms)
        rank_drop = previous_rank is not None and rank < previous_rank
        if rank_drop and self.cpu_near_bank is not None:
            summary = self.cpu_near_bank.rebase(rank, old_frontier)
            self.cpu_near_rebases += 1
            self.cpu_near_seen.clear()
            self.cpu_active_near_seed = [None] * (self.nw + 1)
            hydrated = self.hydrate_cpu_near_bank()
            synthesized = self.populate_cpu_near_bank(
                terms, source="new-frontier")
            self.log(
                f"CPU NEAR REBASE: best={rank} retained={summary['retained']} "
                f"old_frontier={summary['old_frontier_admitted']} "
                f"hydrated={hydrated} synthesized={synthesized}")
        if (self.c3_terms is not None and self.n == self.m == self.p and
                is_c3_closed(terms, self.n)):
            self._consider_c3_leader(rank, terms, refresh=False)
        if self.gpu_policy == "adaptive":
            if rank_drop:
                # Pareto objectives compare one frontier rank at a time.
                self.gpu_pareto = {
                    key: entry for key, entry in self.gpu_pareto.items()
                    if entry["rank"] == rank
                }
            self.refresh_gpu_role_seeds(preserve_novelty=not rank_drop)
            self.gpu_adapt_generation += 1
            for role in self.gpu_roles:
                if role in self.gpu_procs and role in GPU_ROLE_PROFILES:
                    self._write_gpu_role_live(role)
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
            result_name = ("WORLD_RECORD.txt" if self.record_known else
                           "BASELINE_IMPROVEMENT.txt")
            write_dump(terms, os.path.join(self.dir, result_name))
            label = "WORLD RECORD" if self.record_known else "BASELINE IMPROVEMENT"
            self.log(f"{label}: verified rank={rank} beats {self.world_record}")
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
        synthesized = self.populate_cpu_near_bank(
            terms, source="tie-frontier")
        if synthesized:
            self.log(f"CPU NEAR REFRESH: rank={rank} synthesized={synthesized} "
                     f"from=sparser-tie")
        if (self.c3_terms is not None and self.n == self.m == self.p and
                is_c3_closed(terms, self.n)):
            self._consider_c3_leader(rank, terms, refresh=False)
        if self.gpu_policy == "adaptive":
            self.refresh_gpu_role_seeds(preserve_novelty=True)
            self.gpu_adapt_generation += 1
            for role in self.gpu_roles:
                if role in self.gpu_procs and role in GPU_ROLE_PROFILES:
                    self._write_gpu_role_live(role)
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
        if self.strategy == "independent":
            return []
        candidates = [i for i in range(1, self.nw + 1) if i != finder]
        if self.strategy == "converge":
            return candidates
        # Do not kill an unreadable island or an intentional shoulder/C3 lane.
        # Only the sticky exploitation cohort follows a strict new leader.
        candidates = [i for i in candidates
                      if i in ranks and self.cpu_door_roles[i] in
                      ("leader", "frontier")]
        candidates.sort(key=lambda i: ranks[i], reverse=True)
        return candidates[:self.migrate]

    def run(self):
        self.prepare_run()
        start = time.time()
        failure = None
        try:
            requested_rank, recovered_rank, recovered_path = self.recover_frontier()
            if self.escape_profile == "mixed" and self.escape_enabled_for("startup"):
                self._mixed_portfolio(self.initial)
            elif self.escape_enabled_for("startup"):
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
                     f"work={self.work_zone_moves}, wander={self.wander_zone_moves}, "
                     f"escape={self.escape_profile}:{self.escape_kind}@"
                     f"{self.escape_at}/every{self.escape_every}")
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
            self.append_perf(*self.best, 0.0)
            self.archive_candidate(*self.best, source="initial")
            self.hydrate_archive(len(self.initial))
            self.initialize_cpu_seed_banks(len(self.initial))
            write_dump(self.initial, os.path.join(self.dir, "best.txt"))
            if self.gpu:
                self.launch_gpu_relay()
            for i in range(1, self.nw + 1):
                launch_seed, source, escape = self.cpu_launch_seed(
                    i, "startup", self.initial)
                self.launch(i, 0, launch_seed, source=source)
                self.log_escape(i, escape)
                self.log(f"CPU DOOR: w{i} role={self.cpu_door_roles[i]} "
                         f"source={source} rank={len(launch_seed)} "
                         f"zone={CPU_ZONE_NAMES[self.cpu_zone_profiles[i]]}")
            self.log(f"launched {self.nw} walkers from exact-verified rank "
                     f"{len(self.initial)} frontier; shoulders="
                     f"{self.cpu_near_bank.status()['size']} symmetry="
                     f"{len(self.cpu_symmetry_bank)} escapes={self.escape_applied}")
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
                observations = []
                for i in range(1, self.nw + 1):
                    rnk, trm = read_dump(self.dump_file(i))
                    if rnk is None:
                        continue
                    if self.exact_valid(rnk, trm):
                        self.invalid_dumps.pop(i, None)
                        ranks[i] = rnk
                        if rnk <= old_best + 2:
                            observations.append((rnk, i, trm, f"w{i}"))
                            if rnk <= old_best:
                                self.mark_cpu_seed_success(i, rnk)
                    else:
                        digest = hashlib.sha256(repr((rnk, trm)).encode()).hexdigest()
                        prior_digest, prior_count = self.invalid_dumps.get(i, (None, 0))
                        count = prior_count + 1 if digest == prior_digest else 1
                        self.invalid_dumps[i] = (digest, count)
                        if count == 1:
                            self.invalid_candidates += 1
                            self.log(f"REJECTED invalid rank={rnk} from w{i}")
                        if count >= 2:
                            seed, source, escape = self.cpu_launch_seed(
                                i, "quarantine")
                            self.credit_cpu_cohort(i, "quarantines")
                            self.stop_process(i)
                            self.launch(i, self.reseeds + 1, seed, source=source)
                            self.log_escape(i, escape)
                            self.reseeds += 1
                            self.invalid_dumps.pop(i, None)
                            self.log(f"QUARANTINE: w{i} repeated an invalid dump; "
                                     f"role={self.cpu_door_roles[i]} source={source} "
                                     f"rank={len(seed)}")

                # Same-rank density snapshots and strict record beats use a
                # separate spool, so they remain visible even when the worker's
                # personal rank never drops below its record-valued seed.
                observations.extend(self.drain_spool(old_best + 2))
                observations.extend(self.gpu_candidates(old_best + 2))
                self.bank_near_observations(observations)
                candidates = [item for item in observations if item[0] <= old_best]
                self.rebalance_gpu_roles(now)

                frontier_rank = min((x[0] for x in candidates), default=old_best)
                frontier = [x for x in candidates if x[0] == frontier_rank]
                frontier.sort(key=lambda item: (
                    self.score(frontier_rank, item[2])["bits"],
                    self.canonical(item[2]), item[1]))
                finder = -1
                best_terms = self.best[1]
                if frontier_rank < old_best:
                    for candidate_rank, _, candidate_terms, candidate_source in candidates:
                        if candidate_rank == old_best:
                            self.archive_candidate(
                                candidate_rank, candidate_terms,
                                source=candidate_source)
                    _, finder, best_terms, source = frontier[0]
                    if self.note_best(frontier_rank, best_terms, now - start):
                        self.credit_cpu_cohort(finder, "rank_drops")
                        for _, i, terms, source in frontier[1:]:
                            self.archive_candidate(frontier_rank, terms, source=source)
                        self.bank_near_observations(
                            [item for item in observations
                             if item[0] > frontier_rank])
                else:
                    for _, i, terms, source in frontier:
                        self.archive_candidate(frontier_rank, terms, source=source)
                    if frontier:
                        best_tie = min(frontier, key=lambda item: (
                            self.score(frontier_rank, item[2])["bits"],
                            self.canonical(item[2]), item[1]))
                        if self.note_tie_leader(
                                frontier_rank, best_tie[2], now - start):
                            self.credit_cpu_cohort(best_tie[1], "tie_improvements")

                # -- migrate only a policy-selected slice; islands keep running --
                if frontier_rank < old_best:
                    if now - self.last_converge > 3.0:
                        self.last_converge = now
                        targets = self.migration_targets(finder, ranks)
                        for i in targets:
                            self.credit_cpu_cohort(i, "migrations")
                            write_dump(best_terms, self.reseed_file(i))
                            # Direct convergence bypasses cpu_launch_seed(); do
                            # not credit the coordinator-published leader dump
                            # to a shoulder process that was just killed.
                            self.cpu_active_near_seed[i] = None
                            self.stop_process(i)
                            self.launch(i, self.reseeds + 1, best_terms,
                                        source="migration/leader")
                            self.reseeds += 1
                        self.log(f"MIGRATE: {len(targets)} walkers onto rank {frontier_rank} "
                                 f"(found by {'GPU' if finder == 0 else 'w' + str(finder)}; "
                                 f"strategy={self.strategy})")

                # -- exhausted island -> a separated frontier seed or fresh start --
                for i in range(1, self.nw + 1):
                    pr = self.procs[i]
                    if pr and pr.poll() is not None:
                        cyc = tail_has(os.path.join(self.dir, f"cpu_{i}.log"), "CYCLEOUT")
                        self.credit_cpu_cohort(i, "completions")
                        self.credit_cpu_cohort(i, "cycleouts" if cyc else "exits")
                        trigger = "cycleout" if cyc else "exit"
                        seed, source, escape = self.cpu_launch_seed(i, trigger)
                        self.launch(
                            i, self.naive_wraps + self.frontier_wraps + self.reseeds + 1,
                            seed, source=source)
                        self.log_escape(i, escape)
                        self.log(f"EXPLORE: w{i} {'CYCLEOUT' if cyc else 'exit'} -> "
                                 f"role={self.cpu_door_roles[i]} source={source} "
                                 f"rank {len(seed)}"
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
            self._stop_gpu_process(self.gpu_proc)
            for role in list(self.gpu_procs):
                self._stop_gpu_role(role)
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
        now = time.time()
        self.status_sequence += 1
        walkers = [self._account_cpu_walker(i, now=now)
                   for i in range(1, self.nw + 1)]
        producer_state = ("failed" if self.error else "done" if done else
                          "compiling" if compiling else "live")
        c = self.score(*self.best) if self.best else {}
        omega = c.get("omega")
        omega = round(omega, 4) if isinstance(omega, float) and math.isfinite(omega) else None
        status = {
            "schema_version": 3,
            "started": start, "updated_at": now,
            "sequence": self.status_sequence,
            "producer_state": producer_state,
            "coordinator_pid": os.getpid(),
            "elapsed": round(now - start, 1),
            "done": done, "compiling": compiling, "strategy": self.strategy,
            "error": self.error,
            "format": f"{self.n}x{self.m}x{self.p}", "record": self.world_record,
            "configured_record": self.configured_record,
            "record_known": self.record_known,
            "recovered_rank": self.recovered_rank,
            "escape": {"profile": self.escape_profile, "kind": self.escape_kind,
                       "bank_count": self.escape_bank_count, "at": self.escape_at,
                       "every": self.escape_every, "part": self.escape_part,
                       "considered": self.escape_considered,
                       "applied": self.escape_applied,
                       "bypassed": self.escape_bypassed,
                       "skipped": self.escape_skipped,
                       "recipes": dict(self.escape_recipe_counts)},
            "cpu": {"work_moves": self.work_zone_moves,
                    "wander_moves": self.wander_zone_moves,
                    "door_launches": dict(self.cpu_door_launches),
                    "migration_limit": self.migrate,
                    "rng": "parameterized-lcg63",
                    "near": (self.cpu_near_bank.status()
                             if self.cpu_near_bank is not None else {}),
                    "near_admissions": self.cpu_near_admissions,
                    "near_hydrated": self.cpu_near_hydrated,
                    "near_rebases": self.cpu_near_rebases,
                    "cohorts": {
                        key: self._cpu_cohort_status(stats)
                        for key, stats in sorted(self.cpu_cohort_stats.items())
                    },
                    "symmetry": {
                        "size": len(self.cpu_symmetry_bank),
                        "ranks": sorted({len(entry.scheme)
                                         for entry in self.cpu_symmetry_bank}),
                        "least_uses": min(self.cpu_symmetry_uses.values(), default=0),
                        "most_uses": max(self.cpu_symmetry_uses.values(), default=0),
                    }},
            "gpu": {"enabled": self.gpu, "walkers": self.gpu_walkers,
                    "escapes": self.gpu_escapes, "steps": self.gpu_steps,
                    "policy": self.gpu_policy,
                    "c3_leader": ({"rank": self.c3_best[0],
                                   "bits": self.score(*self.c3_best)["bits"]}
                                  if self.c3_best is not None else None),
                    "running": (any(proc.poll() is None
                                    for proc in self.gpu_procs.values())
                                if self.gpu_policy == "adaptive" else
                                bool(self.gpu_proc and self.gpu_proc.poll() is None)),
                    "roles": {role: {**self.gpu_role_stats[role],
                                     "reward_per_lane_epoch": round(
                                         self.gpu_role_stats[role]["reward"] /
                                         max(1, self.gpu_role_stats[role]["lane_epochs"]),
                                         6),
                                     "lanes": self.gpu_role_allocations.get(role, 0),
                                     "weight": self.gpu_role_weights.get(role, 0),
                                     "seed": self.gpu_role_seed_profiles.get(role, {}),
                                     "launches": self.gpu_role_launches.get(role, 0),
                                     "failures": self.gpu_role_failures.get(role, 0),
                                     "retry_at": self.gpu_role_retry_at.get(role),
                                     "plan": self.gpu_role_plans.get(role, {})}
                              for role in self.gpu_roles}
                    if self.gpu_policy == "adaptive" else {},
                    "pareto": {"size": len(self.gpu_pareto),
                               "capacity": self.gpu_novelty_size,
                               "admissions": self.gpu_pareto_admissions,
                               "rejections": self.gpu_pareto_rejections,
                               "evictions": self.gpu_pareto_evictions}
                    if self.gpu_policy == "adaptive" else {}},
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

        def put(row, col, value, attr=0, limit=None):
            h, w = scr.getmaxyx()
            if row < 0 or row >= h or col < 0 or col >= w:
                return False
            room = max(0, w - col - (1 if row == h - 1 else 0))
            if limit is not None:
                room = min(room, max(0, limit))
            if room <= 0:
                return False
            try:
                scr.addnstr(row, col, str(value), room, attr)
                return True
            except curses.error:
                return False

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
                put(0, 0, "waiting for status.json …")
                scr.refresh(); time.sleep(0.5); continue
            b = s.get("best", {})
            health = derive_health_state(s)
            state = health["state"]
            state_attr = (A(4) if state in ("FAILED", "STALE") else
                          A(1) if state in ("COMPILING", "DEGRADED") else
                          A(3) if state == "DONE" else A(2))
            title = f" flipfleet  <{s['format']}> GF(2)   strategy={s['strategy']} "
            put(0, 0, title, A(1) | curses.A_BOLD)
            put(0, max(0, w - len(state) - 1), state,
                state_attr | curses.A_BOLD)
            om = f"{b.get('omega'):.3f}" if isinstance(b.get("omega"), float) else "-"
            objective = format_objective(s)
            put(1, 0, f" best r{b.get('rank', '?')} · {objective} · "
                f"ops {b.get('ops', '?')} · bits {b.get('bits', '?')} · ω {om}",
                A(2) | curses.A_BOLD)
            c = s.get("counters", {})
            health_detail = " · ".join(health.get("reasons", [])[:2])
            age = health.get("age")
            freshness = "?" if age is None else f"{age:.1f}s"
            put(2, 0, f" elapsed {s.get('elapsed', 0):.0f}s · status #{s.get('sequence', '?')} "
                f"age {freshness} · rank wins {c.get('new_bests', 0)} · density wins "
                f"{c.get('tie_improvements', 0)} · forced restarts {c.get('reseeds', 0)} · "
                f"invalid {c.get('invalid', 0)}", state_attr if health_detail else 0)
            row = 3
            if health_detail:
                put(row, 1, "health: " + health_detail, state_attr | curses.A_BOLD)
                row += 1

            def render_compact_panel(label, lines, attr, columns=2):
                nonlocal row
                if not lines:
                    return
                put(row, 0, f" {label}:", attr | curses.A_BOLD)
                row += 1
                panel_cols = columns if w >= 100 else 1
                column_width = max(1, w // panel_cols)
                for index, line in enumerate(lines):
                    rr = row + index // panel_cols
                    cc = (index % panel_cols) * column_width + 1
                    if rr >= h - 7:
                        break
                    put(rr, cc, line, attr, column_width - 2)
                row += (len(lines) + panel_cols - 1) // panel_cols

            render_compact_panel("diversity", summarize_diversity(s), A(3))
            render_compact_panel("effectiveness", summarize_effectiveness(s), A(1))

            perf_curve = s.get("perf_curve", [])
            timeline = build_time_timeline(
                perf_curve, s.get("elapsed", 0), max(12, w - 2))
            last_event = (perf_curve[-1].get("t") if perf_curve and
                          isinstance(perf_curve[-1], dict) else None)
            event_age = (max(0.0, float(s.get("elapsed", 0)) - float(last_event))
                         if isinstance(last_event, (int, float)) else None)
            event_text = (f" · last frontier event {event_age:.0f}s ago"
                          if event_age is not None else "")
            put(row, 0, " progress (wall time; lower rank is up)" + event_text + ":",
                A(3) | curses.A_BOLD)
            row += 1
            for line in timeline:
                if row >= h - 7:
                    break
                put(row, 1, line, A(2), w - 2)
                row += 1

            walkers = s.get("walkers", [])
            put(row, 0, " CPU islands:", A(3) | curses.A_BOLD)
            row += 1
            cpu_cols = 2 if w >= 104 else 1
            cpu_width = max(1, w // cpu_cols)
            best_rank = b.get("rank")
            for idx, wk in enumerate(walkers):
                rr, cc = row + idx // cpu_cols, (idx % cpu_cols) * cpu_width + 1
                if rr >= h - 7:
                    break
                process_state = wk.get("process_state")
                atr = A(4) if process_state == "exited" else (
                    A(2) if wk.get("running") else curses.A_DIM)
                put(rr, cc, format_cpu_island_row(
                    wk, best_rank=best_rank, width=cpu_width - 2), atr,
                    cpu_width - 2)
            row += (len(walkers) + cpu_cols - 1) // cpu_cols

            gpu = s.get("gpu", {})
            c3 = gpu.get("c3_leader")
            c3_text = f" · C3 r{c3.get('rank')}" if isinstance(c3, dict) else ""
            gpu_header = (" GPU portfolio: off" if gpu.get("enabled") is False else
                          f" GPU portfolio: {gpu.get('policy', '?')} · "
                          f"{gpu.get('walkers', 0)} lanes · "
                          f"{'running' if gpu.get('running') else 'stopped'}{c3_text}")
            put(row, 0, gpu_header, A(3) | curses.A_BOLD)
            row += 1
            gpu_lines = ([] if gpu.get("enabled") is False else
                         summarize_gpu_roles(s, limit=8))
            gpu_cols = 2 if w >= 120 else 1
            gpu_width = max(1, w // gpu_cols)
            for index, line in enumerate(gpu_lines):
                rr, cc = row + index // gpu_cols, (index % gpu_cols) * gpu_width + 1
                if rr >= h - 7:
                    break
                put(rr, cc, line, A(1), gpu_width - 2)
            row += (len(gpu_lines) + gpu_cols - 1) // gpu_cols

            ev_row = min(max(3, row + 1), max(3, h - 6))
            put(ev_row, 0, " events:", A(3))
            for j, e in enumerate(s.get("events", [])[-min(11, h - ev_row - 2):]):
                put(ev_row + 1 + j, 1, e,
                    A(4) if "ERROR" in e else A(2) if "NEW BEST" in e else (
                        A(1) if "EXPLORE" in e else 0), w - 2)
            put(h - 1, 0,
                " q to quit — data from status.json (also readable by other tools) ",
                curses.A_DIM)
            scr.refresh()
            time.sleep(0.5)

    curses.wrapper(draw)


def build_arg_parser():
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--tensor", type=tensor_arg,
        help="square tensor profile, e.g. 3x3 through 7x7")
    ap.add_argument("--size", type=int, help="square shortcut: sets n=m=p")
    ap.add_argument("--n", type=int)
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
                    help="leader/frontier islands migrated on a strict rank drop (default: 1)")
    ap.add_argument(
        "--archive-reseed", type=float, default=1.0,
        help=("probability a frontier door uses the least-used archive "
              "(default 1; the anchor door preserves the campaign start)"))
    ap.add_argument("--archive-size", type=int, default=256,
                    help="max in-memory max-min frontier sample (all remain on disk)")
    ap.add_argument("--cpu-work-moves", "--record-band-moves",
                    dest="record_band_moves", type=parse_move_budgets,
                    help=("comma-separated CPU work-zone portfolio; tensor-specific "
                          "mixed defaults, e.g. 100m,500m,2.5b,10b"))
    ap.add_argument("--cpu-wander-moves", dest="wander_zone_moves",
                    type=parse_move_budgets,
                    help=("comma-separated CPU wander-zone portfolio; defaults are "
                          "shorter than the paired work budgets"))
    ap.add_argument(
        "--cpu-near-size", type=int, default=128,
        help="total bounded capacity of the exact best+1/best+2 CPU seed bank")
    ap.add_argument(
        "--cpu-near-signature-quota", type=int, default=8,
        help="maximum retained near seeds per factor-reuse signature and rank tier")
    ap.add_argument(
        "--cpu-symmetry-seeds", type=int, default=24,
        help="maximum replayable one-move C3 seeds in the CPU symmetry bank")
    ap.add_argument("--plus-axes", choices=("w", "any"), default="any")
    ap.add_argument(
        "--escape-profile", choices=ESCAPE_PROFILES, default="mixed",
        help="none, one selected identity, or the default mixed variable-rank bank")
    ap.add_argument(
        "--escape-kind", choices=ESCAPE_KINDS, default="none",
        help=("exact launch excursion: split any term; break a fixed cube; or "
              "use a C3-preserving orbit-split/polarization (normally with "
              "--seed c3-record)"))
    ap.add_argument(
        "--escape-at", choices=ESCAPE_TRIGGERS, default="both",
        help="eligible launch sites (never migration, quarantine, or plain exits)")
    ap.add_argument(
        "--escape-every", type=int, default=1,
        help="schedule an escape bank on every Nth eligible launch")
    ap.add_argument(
        "--escape-bank-count", type=int, default=24,
        help="maximum exact variable-rank seeds cached per frontier")
    ap.add_argument(
        "--escape-part", type=lambda value: int(value, 0),
        help="optional fixed common-space part mask; default chooses deterministically")
    ap.add_argument("--stop-on-record", action="store_true")
    gpu_group = ap.add_mutually_exclusive_group()
    gpu_group.add_argument(
        "--gpu", dest="gpu", action="store_true",
        help="enable the heterogeneous Tungsten/Metal fleet (default)")
    gpu_group.add_argument(
        "--no-gpu", dest="gpu", action="store_false",
        help="disable every GPU search engine")
    ap.set_defaults(gpu=True)
    ap.add_argument(
        "--gpu-escapes", type=int, default=256,
        help="number of exact split basins in the GPU seed portfolio (default 256; 1=legacy)")
    ap.add_argument(
        "--gpu-walkers", type=int, default=4096,
        help="GPU lane count, rounded down to a generated threadgroup multiple")
    ap.add_argument(
        "--gpu-steps", type=int, default=500_000,
        help="moves per GPU dispatch and lane")
    ap.add_argument(
        "--gpu-policy", choices=GPU_POLICIES, default="adaptive",
        help=("single preserves the monolithic scout; adaptive divides lanes "
              "among tensor-specific walk, escape, novelty, SIMD, and MITM roles"))
    ap.add_argument(
        "--gpu-novelty-size", type=int, default=32,
        help="bounded nondominated exact GPU archive (adaptive policy only)")
    ap.add_argument(
        "--gpu-adapt-secs", type=int, default=300,
        help="seconds per adaptive GPU allocation epoch")
    ap.add_argument("--dir")
    ap.add_argument("--tui", action="store_true", help="run the search AND show the TUI")
    ap.add_argument("--attach", metavar="RUN_DIR", help="TUI only, attach to an existing run")
    return ap


def main(argv=None):
    ap = build_arg_parser()
    args = ap.parse_args(argv)

    if args.attach:
        tui(os.path.join(args.attach, "status.json"))
        return

    record_was_explicit = args.record is not None
    profile = None
    explicit_legacy_dims = any(value is not None for value in
                               (args.size, args.n, args.m, args.p))
    if args.tensor is not None:
        if explicit_legacy_dims:
            ap.error("--tensor cannot be combined with --size/--n/--m/--p")
        profile = profile_for_tensor(args.tensor)
        args.n, args.m, args.p = profile.dimensions
    elif args.size is not None:
        args.n = args.m = args.p = args.size
    else:
        args.n = 5 if args.n is None else args.n
        args.m = args.n if args.m is None else args.m
        args.p = args.n if args.p is None else args.p
    if profile is None and args.n == args.m == args.p and 3 <= args.n <= 7:
        profile = profile_for_tensor(args.n)
    if args.record is None:
        if profile is not None:
            args.record = profile.default_rank
        elif args.n == args.m == args.p and args.n in KNOWN_RECORDS:
            args.record = KNOWN_RECORDS[args.n]
        else:
            ap.error("--record is required for this format")
    if args.escape_kind != "none":
        args.escape_profile = "single"
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
        if args.cpu_near_size < 2:
            raise ValueError("--cpu-near-size must be at least two")
        if args.cpu_near_signature_quota <= 0 or args.cpu_symmetry_seeds <= 0:
            raise ValueError(
                "--cpu-near-signature-quota and --cpu-symmetry-seeds must be positive")
        if args.escape_every <= 0:
            raise ValueError("--escape-every must be positive")
        if args.escape_bank_count < 2:
            raise ValueError("--escape-bank-count must be at least two")
        if ((args.escape_kind != "none" or args.escape_profile == "mixed") and
                not (args.n == args.m == args.p)):
            raise ValueError("escape profiles currently require a square format")
        if args.escape_profile == "single" and args.escape_kind == "none":
            raise ValueError("--escape-profile single requires --escape-kind")
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
        if args.gpu_novelty_size <= 0 or args.gpu_adapt_secs <= 0:
            raise ValueError("--gpu-novelty-size and --gpu-adapt-secs must be positive")
    except ValueError as exc:
        ap.error(str(exc))
    if args.seed is None and profile is not None and profile.seed_path is not None:
        args.seed = profile.seed_path
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
    if (profile is not None and not profile.known_record and
            not record_was_explicit):
        # An unknown tensor profile is a baseline campaign.  If the user
        # supplies a stronger exact seed, target a strict improvement over that
        # seed instead of retaining the naive fallback rank.
        args.record = len(initial)
    c3_initial = None
    if profile is not None and profile.c3_eligible:
        if profile.c3_seed_path is not None:
            c3_initial = normalize_terms(parse_scheme(profile.c3_seed_path))
        elif profile.c3_seed_kind == "naive":
            c3_initial = naive_scheme(args.n, args.m, args.p)
    run_dir = args.dir or os.path.join(HERE, "runs", f"flipfleet_{args.n}{args.m}{args.p}")
    try:
        fleet = Fleet(run_dir, args.walkers, args.secs, n=args.n, m=args.m, p=args.p,
                      record=args.record, initial_terms=initial, strategy=args.strategy,
                      cycles=args.cycles, migrate=args.migrate,
                      archive_reseed=args.archive_reseed, archive_size=args.archive_size,
                      plus_axes=args.plus_axes,
                      stop_on_record=args.stop_on_record,
                      record_band_moves=args.record_band_moves,
                      wander_zone_moves=args.wander_zone_moves,
                      escape_kind=args.escape_kind, escape_at=args.escape_at,
                      escape_every=args.escape_every, escape_part=args.escape_part,
                      escape_profile=args.escape_profile,
                      escape_bank_count=args.escape_bank_count,
                      cpu_near_size=args.cpu_near_size,
                      cpu_near_signature_quota=args.cpu_near_signature_quota,
                      cpu_symmetry_seeds=args.cpu_symmetry_seeds,
                      c3_terms=c3_initial,
                      gpu=args.gpu, gpu_escapes=args.gpu_escapes,
                      gpu_walkers=args.gpu_walkers, gpu_steps=args.gpu_steps,
                      gpu_policy=args.gpu_policy,
                      gpu_novelty_size=args.gpu_novelty_size,
                      gpu_adapt_secs=args.gpu_adapt_secs,
                      tensor_profile=profile,
                      record_known=(record_was_explicit or
                                    (profile.known_record if profile is not None else
                                     args.n in KNOWN_RECORDS)))
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
