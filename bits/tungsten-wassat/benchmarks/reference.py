#!/usr/bin/env python3
"""The reference suite: wassat against every installed rival, exit-coded.

This file DEFINES the performance goal. Instances are pinned and the set
only grows. Four classes:

  parity instances   — wassat must be within TOLERANCE of the best rival
                       (exit nonzero otherwise; this is a regression gate);
  survey instances   — the breadth set. Correctness gates (verdicts must
                       agree with each other and with the known answer), speed
                       is reported per family but does not gate. This is the
                       honest map of where the solver stands; rows graduate
                       into `parity` once wassat holds its own on them.
  competition rows   — SAT Competition 2026 main-track instances, carrying the
                       published instance-wise runtimes of the actual field
                       (CaDiCaL 3, Kissat, and the best of all 31 entrants) so
                       a local measurement can be placed against it;
  frontier instances — hard instances tracked with a per-run budget so the
                       suite stays fast; improving these is the standing
                       goal, regressing parity is failure. They stay listed
                       here after wassat overtakes the rival, as the record
                       of what the frontier used to be.

Every verdict is cross-checked between solvers; disagreement is fatal.

Instance sets, all optional — a missing directory skips its section rather
than failing, so the suite still runs on a bare checkout:

  BENCH=/tmp/satbench           generated corpus (benchmarks/gen_instances.py)
  SATLIB_ROOT=...               SATLIB, as unpacked by the original refbench
  SATBENCH_EXT=/tmp/satbench-ext   breadth set: SATLIB structured families plus
                                a slice of older SAT Competition tracks. Sources
                                are cs.ubc.ca/~hoos/SATLIB/benchm.html and
                                benchmark-database.de; the SATLIB tarballs end
                                each file with a `%`/`0` sentinel that CaDiCaL
                                rejects, so strip from the `%` line onward.
  SATBENCH_2026=/tmp/satbench-2026  SAT Competition 2026 main track. The rows
                                below were fetched with, in order:
                                  benchmarks/sc2026.py fetch --per-family 2 \
                                      --max-field-seconds 60
                                  benchmarks/sc2026.py fetch --per-family 1 \
                                      --min-field-seconds 60 --max-field-seconds 900
"""

from __future__ import annotations

import json
import math
import os
import shutil
import statistics
import subprocess
import sys
import tempfile
import time
from collections import defaultdict
from pathlib import Path

from lrc13_reference import materialize as materialize_lrc13

ROOT = Path(__file__).resolve().parents[1]
WASSAT = os.environ.get("WASSAT", str(ROOT / "bin" / "wassat"))
CADICAL = os.environ.get("CADICAL", shutil.which("cadical") or "")
CMS5 = os.environ.get("CRYPTOMINISAT5", shutil.which("cryptominisat5") or "")
REPS = int(os.environ.get("REPS", "3"))
TOLERANCE = float(os.environ.get("TOLERANCE", "1.5"))
# The dominance goal: wassat fastest on every row by MARGIN. Rows where the
# best rival is under DOM_FLOOR seconds are startup-noise territory and pass
# when wassat is within NOISE_MS of the best rival instead.
DOMINANCE = os.environ.get("DOMINANCE", "") == "1"
MARGIN = float(os.environ.get("MARGIN", "1.25"))
DOM_FLOOR = float(os.environ.get("DOM_FLOOR", "0.05"))
NOISE_MS = float(os.environ.get("NOISE_MS", "8")) / 1000.0
FRONTIER_BUDGET = float(os.environ.get("FRONTIER_BUDGET", "60"))
SURVEY_BUDGET = float(os.environ.get("SURVEY_BUDGET", "120"))
COMP_BUDGET = float(os.environ.get("COMP_BUDGET", "60"))
LYMPH_BUDGET = float(os.environ.get("LYMPH_BUDGET", "5"))
LYMPH_REPS = int(os.environ.get("LYMPH_REPS", "5"))
XORSHIFT_BUDGET = float(os.environ.get("XORSHIFT_BUDGET", "30"))
XORSHIFT_REPS = int(os.environ.get("XORSHIFT_REPS", "1"))
# A row counts as a tie when the two times are within TIE_BAND of each other;
# below TIE_FLOOR seconds the row is process-startup noise and always ties.
TIE_BAND = float(os.environ.get("TIE_BAND", "1.10"))
TIE_FLOOR = float(os.environ.get("TIE_FLOOR", "0.05"))
BENCH = Path(os.environ.get("BENCH", "/tmp/satbench"))
SATLIB_ROOT = os.environ.get("SATLIB_ROOT", "")
EXT = Path(os.environ.get("SATBENCH_EXT", "/tmp/satbench-ext"))
SC2026 = Path(os.environ.get("SATBENCH_2026", "/tmp/satbench-2026"))
# The survey is broad and each row is measured REPS times by three solvers;
# SURVEY_REPS trades that down when only a smoke check is wanted. Competition
# rows run long enough that the median buys little, so they default to one rep.
SURVEY_REPS = int(os.environ.get("SURVEY_REPS", str(REPS)))
COMP_REPS = int(os.environ.get("COMP_REPS", "1"))
# Repeats stop paying for themselves once a single run is this long.
REP_CEILING = float(os.environ.get("REP_CEILING", "5"))

PARITY = [
    ("php76", str(BENCH / "php76.cnf")),
    ("php87", str(BENCH / "php87.cnf")),
    ("rand3_20", str(BENCH / "rand3_20.cnf")),
    ("rand3_40", str(BENCH / "rand3_40.cnf")),
]
if SATLIB_ROOT:
    satlib = Path(SATLIB_ROOT)
    bmc = satlib / "structclean" / "bmc"
    PARITY.extend(
        [
            ("uuf100-01", str(satlib / "clean" / "uuf100-430" / "uuf100-01.cnf")),
            ("uuf250-01", str(satlib / "clean" / "uuf250-1065" / "uuf250-01.cnf")),
            ("dubois26", str(satlib / "structclean" / "dubois" / "dubois26.cnf")),
            ("bmc-ibm-2", str(bmc / "bmc-ibm-2.cnf")),
            ("bmc-ibm-6", str(bmc / "bmc-ibm-6.cnf")),
            ("bmc-ibm-10", str(bmc / "bmc-ibm-10.cnf")),
            ("bmc-ibm-12", str(bmc / "bmc-ibm-12.cnf")),
        ]
    )

# --------------------------------------------------------------------------
# The survey: breadth over instance FAMILY, which is what the parity list
# lacks. Every row was screened so that the fastest rival needs a measurable
# amount of work on it; rows the rivals dispatch in milliseconds carry no
# signal and are deliberately absent. `expect` is the published answer, so a
# wrong verdict is caught even when both rivals agree with each other.
#
#   (family, name, relative path under SATBENCH_EXT, expect)
SURVEY: list[tuple[str, str, str, str]] = [
    ("beijing (planning/scheduling)", "3bitadd_31", "beijing/3bitadd_31.cnf", "sat"),
    ("beijing (planning/scheduling)", "2bitadd_10", "beijing/2bitadd_10.cnf", "unsat"),
    ("bmc-ibm/galileo (hardware BMC)", "bmc-ibm-6", "bmc/bmc-ibm-6.cnf", "sat"),
    ("bmc-ibm/galileo (hardware BMC)", "bmc-ibm-12", "bmc/bmc-ibm-12.cnf", "sat"),
    ("graph-colouring (DIMACS large)", "g250.15", "gcp-large/g250.15.cnf", "sat"),
    ("graph-colouring (DIMACS large)", "g125.18", "gcp-large/g125.18.cnf", "sat"),
    ("lran-f (large random 3-SAT)", "f1000", "lran/f1000.cnf", "sat"),
    ("lran-f (large random 3-SAT)", "f600", "lran/f600.cnf", "sat"),
    ("pigeonhole", "hole9", "pigeon/hole9.cnf", "unsat"),
    ("pigeonhole", "php109", "pigeon/php109.cnf", "unsat"),
    ("quasigroup (QG)", "qg3-09", "quasigroup/qg3-09.cnf", "unsat"),
    ("quasigroup (QG)", "qg5-13", "quasigroup/qg5-13.cnf", "unsat"),
    ("random-3sat SAT (uf)", "uf250-0100", "rand3/uf250-0100.cnf", "sat"),
    ("random-3sat SAT (uf)", "uf225-015", "rand3/uf225-015.cnf", "sat"),
    ("random-3sat UNSAT (uuf)", "uuf200-013", "rand3/uuf200-013.cnf", "unsat"),
    ("random-3sat UNSAT (uuf)", "uuf225-015", "rand3/uuf225-015.cnf", "unsat"),
    ("sc-archive: agile", "bench_1614.smt2", "comp/agile-sat__bench_1614.smt2.cnf", "sat"),
    ("sc-archive: bitvector", "minand064", "comp/bitvector-unsat__minand064.cnf", "unsat"),
    ("sc-archive: bitvector", "smulo016", "comp/bitvector-unsat__smulo016.cnf", "unsat"),
    ("sc-archive: cryptography", "cms-scheel-md5-families-r24-c11-p1", "comp/cryptography-sat__cms-scheel-md5-families-r24-c11-p1-4-6-9-10-11-1.cnf", "sat"),
    ("sc-archive: edge-matching", "em_7_3_6_fbc", "comp/edge-matching-sat__em_7_3_6_fbc.cnf", "sat"),
    ("sc-archive: graph-based", "urqh2x5.shuffled-as.sat03-1473", "comp/graph-based-unsat__urqh2x5.shuffled-as.sat03-1473.cnf", "unsat"),
    ("sc-archive: hardware-bmc", "shuffling-1-s1722048485-of-bench-s", "comp/hardware-bmc-unsat__shuffling-1-s1722048485-of-bench-sat04-437.used-.cnf", "unsat"),
    ("sc-archive: hardware-verification", "ibm-2004-03-k70", "comp/hardware-verification-sat__ibm-2004-03-k70.cnf", "sat"),
    ("sc-archive: hardware-verification", "SAT_dat.k10", "comp/hardware-verification-unsat__SAT_dat.k10.cnf", "unsat"),
    ("sc-archive: planning", "mrpp_6x6#14_10", "comp/planning-sat__mrpp_6x6#14_10.cnf", "sat"),
    ("sc-archive: planning", "blocks-4-ipc5-h21-unknown", "comp/planning-unsat__blocks-4-ipc5-h21-unknown.cnf", "unsat"),
    ("sc-archive: popularity-similarity", "mp1-ps_5000_21250_3_0_0.8_0_1.50_6", "comp/popularity-similarity-unsat__mp1-ps_5000_21250_3_0_0.8_0_1.50_6.cnf", "unsat"),
    ("sc-archive: quasigroup-completion", "qwh.35.405.shuffled-as.sat03-1651", "comp/quasigroup-completion-sat__qwh.35.405.shuffled-as.sat03-1651.cnf", "sat"),
    ("sc-archive: quasigroup-completion", "gensys-icl003.shuffled-as.sat05-27", "comp/quasigroup-completion-unsat__gensys-icl003.shuffled-as.sat05-2715.cnf", "unsat"),
    ("sc-archive: random-planted-solution", "fla-350-6", "comp/random-planted-solution-sat__fla-350-6.cnf", "sat"),
    ("sc-archive: scheduling", "Break_triple_10_16.xml", "comp/scheduling-sat__Break_triple_10_16.xml.cnf", "sat"),
    ("sc-archive: social-golfer", "ContextModel_output_8_3_10.bul_.di", "comp/social-golfer-sat__ContextModel_output_8_3_10.bul_.dimacs.cnf", "sat"),
    ("sc-archive: software-verification", "dspam_dump_vc972", "comp/software-verification-unsat__dspam_dump_vc972.cnf", "unsat"),
    ("sc-archive: tseitin", "Urquhart-s3-b3.shuffled-as.sat03-1", "comp/tseitin-unsat__Urquhart-s3-b3.shuffled-as.sat03-1556.cnf", "unsat"),
    ("sc-archive: tseitin", "urquhart3_25bis.shuffled", "comp/tseitin-unsat__urquhart3_25bis.shuffled.cnf", "unsat"),
]

# SAT Competition 2026 main track. `field_best` / `cadical3` / `kissat` are the
# competition's own published instance-wise runtimes (downloads/scores.csv),
# measured on competition hardware with a 5000s budget — they order the field,
# they do not convert into a ratio against a local measurement.
#
#   (family, name, relative path under SATBENCH_2026, expect, best, cadical3, kissat)
COMPETITION: list[tuple[str, str, str, str, float | None, float | None, float | None]] = [
    ("sc2026: miter", "ak128modbtbg2msisc", "ak128modbtbg2msisc.cnf", "sat", 0.27, 0.63, 0.31),
    ("sc2026: n320p5q", "n320p5q2_n.af_239", "n320p5q2_n.af_239.cnf", "sat", 0.11, 1.53, 6.06),
    ("sc2026: sembuster", "sembuster_4200.af_72", "sembuster_4200.af_72.cnf", "sat", 0.44, 1.48, 0.60),
    ("sc2026: sembuster", "sembuster_7500.af_74", "sembuster_7500.af_74.cnf", "sat", 0.65, 1.96, 0.93),
    ("sc2026: scc", "scc_9630_26_0.3_0.1_17.af_76", "scc_9630_26_0.3_0.1_17.af_76.cnf", "sat", 0.80, 2.68, 1.01),
    ("sc2026: Large", "Large-result_b23.af_303", "Large-result_b23.af_303.cnf", "sat", 1.09, 3.83, 1.47),
    ("sc2026: scc", "scc_7216_12_0.5_0.2_11.af", "scc_7216_12_0.5_0.2_11.af.cnf", "sat", 0.98, 3.45, 1.28),
    ("sc2026: Carry", "Carry_Bits_Fast_12", "Carry_Bits_Fast_12.cnf", "sat", 0.04, 15.53, 5.39),
    ("sc2026: n384p5q", "n384p5q2_vh.af_138", "n384p5q2_vh.af_138.cnf", "sat", 1.47, 3.94, 8.53),
    ("sc2026: DivS", "DivS_568_11", "DivS_568_11.cnf", "sat", 3.35, 4.19, 22.64),
    ("sc2026: planning", "mrpp_8x8#20_14", "mrpp_8x8_20_14.cnf", "sat", 9.71, 9.71, 23.49),
    ("sc2026: Large", "Large-result_b24.af_2238", "Large-result_b24.af_2238.cnf", "sat", 2.84, 10.27, 3.81),
    ("sc2026: DivS", "DivS_862_11", "DivS_862_11.cnf", "sat", 5.59, 6.59, 21.52),
    ("sc2026: ais", "ais8.mis-97.debugged", "ais8.mis-97.debugged.cnf", "unsat", 2.59, 7.51, 2.61),
    ("sc2026: hardware-verification", "4pipe", "4pipe.cnf", "unsat", 3.97, 9.88, 5.81),
    ("sc2026: crusti", "crusti_g2io_200_0.1_127_14.af_151", "crusti_g2io_200_0.1_127_14.af_151.cnf", "unsat", 33.03, 44.07, 63.82),
    ("sc2026: schooltt", "schooltt-5-7-12-2-4-1.4-2.6-0.2-0.", "schooltt-5-7-12-2-4-1.4-2.6-0.2-0.9-seed2.cnf", "sat", 12.47, 34.38, 19.17),
    ("sc2026: ntil", "ntil-90d-33", "ntil-90d-33.cnf", "sat", 10.94, 109.56, 175.61),
    ("sc2026: set-covering", "SCPC-500-19", "SCPC-500-19.cnf", "unsat", 26.01, 33.05, 34.58),
    ("sc2026: generic-csp", "connm-ue-csp-sat-n600-d0.04-s17930", "connm-ue-csp-sat-n600-d0.04-s1793042357.used-as.sat04-975.cnf", "unsat", 30.42, 48.95, 37.71),
    ("sc2026: hgen", "170225812", "170225812.cnf", "sat", 0.39, 14.08, 34.86),
    ("sc2026: station-repacking", "41-119494", "41-119494.cnf", "sat", 6.31, 124.51, 27.90),
    # Direct binary-DFA image encoding.  The strict structural shortcut
    # recovers the Černý merge/cycle letters and constructs a checked word;
    # only the two LymphoSAT variants solved this row in the published field.
    ("sc2026: automata-synchronization", "crn_40_1521_s", "crn_40_1521_s--b358bf711108.cnf", "sat", 0.16, None, None),
    ("sc2026: cellular-automata", "spg_200_301", "spg_200_301.cnf", "unsat", 17.55, 70.95, 309.27),
    # Explicit clique obstructions in graph-coloring encodings.  These are
    # retained as individual competition rows because only two field entrants
    # solved either mulsol instance, while the generic structural certificate
    # in lib/coloring.w decides all five without CDCL.
    ("sc2026: graph-coloring", "adv_gc_n100_k10_UNSAT_s42", "adv_gc_n100_k10_UNSAT_s42.cnf", "unsat", 0.57, 122.94, 0.92),
    ("sc2026: graph-coloring", "adv_gc_n100_k14_UNSAT_s42", "adv_gc_n100_k14_UNSAT_s42.cnf", "unsat", 62.91, None, 486.86),
    ("sc2026: graph-coloring", "adv_gc_n300_k10_UNSAT_s42", "adv_gc_n300_k10_UNSAT_s42.cnf", "unsat", 0.97, 113.58, 3.05),
    ("sc2026: graph-coloring", "mulsol.i.2.30", "mulsol.i.2.30.cnf", "unsat", 0.18, None, None),
    ("sc2026: graph-coloring", "mulsol.i.4.30", "mulsol.i.4.30.cnf", "unsat", 0.18, None, None),
]

# These twelve official rows are exact ternary-affine GF(3) systems; only two
# of 31 entrants solved them. The dedicated section checks every sibling in
# Main-compatible proof mode without making two generic local rivals consume a
# timeout per row.
LYMPHOSAT = [
    ("1", "1.cnf", 0.04),
    ("2", "2.cnf", 0.04),
    ("4", "4.cnf", 0.04),
    ("6", "6.cnf", 0.04),
    ("8", "8.cnf", 0.04),
    ("9", "9.cnf", 0.04),
    ("10", "10.cnf", 0.04),
    ("12", "12.cnf", 0.04),
    ("13", "13.cnf", 0.04),
    ("14", "14.cnf", 0.04),
    ("15", "15.cnf", 0.04),
    ("16", "16.cnf", 0.04),
]

# Eleven official SAT rows that render a complete 32-bit xorshift/fold circuit
# and pin its accumulator word. The generic local rivals need minutes on
# competition hardware; keep them in a Wassat-only model-checked lane so the
# maintained reference suite can track the circuit-native specialist without
# paying 22 rival timeouts.
XORSHIFT = [
    ("r14_110", "xorshift_r14_110.cnf", 262.79),
    ("r14_31", "xorshift_r14_31.cnf", 191.73),
    ("r14_42", "xorshift_r14_42.cnf", 712.55),
    ("r14_7", "xorshift_r14_7.cnf", 309.72),
    ("r14_85", "xorshift_r14_85.cnf", 390.65),
    ("r15_104", "xorshift_r15_104.cnf", 547.36),
    ("r15_113", "xorshift_r15_113.cnf", 1235.19),
    ("r15_175", "xorshift_r15_175.cnf", 1580.73),
    ("r15_191", "xorshift_r15_191.cnf", 1088.34),
    ("r16_119", "xorshift_r16_119.cnf", 636.97),
    ("r16_180", "xorshift_r16_180.cnf", 760.58),
]

FRONTIER = []
for name, env_name in (("lr5_37", "LR5_37"), ("lr5_41", "LR5_41")):
    path = os.environ.get(env_name)
    if path:
        FRONTIER.append((name, path))


def benchmark_path(root: Path, relative: str) -> Path:
    """Resolve both legacy names and `sc2026.py fetch --all` hash suffixes."""
    direct = root / relative
    if direct.is_file():
        return direct
    index_path = root / "index.json"
    if not index_path.is_file():
        return direct
    try:
        index = json.loads(index_path.read_text())
    except (OSError, ValueError):
        return direct
    wanted = Path(relative).stem
    normalized_wanted = wanted.replace(".cnf", "")
    matches = [
        root / f"{stem}.cnf"
        for stem in index
        if (
            stem == wanted
            or stem.startswith(wanted + "--")
            or stem.rsplit("--", 1)[0].replace(".cnf", "") == normalized_wanted
        )
    ]
    matches = [path for path in matches if path.is_file()]
    return matches[0] if len(matches) == 1 else direct


def solvers():
    out = [("wassat", lambda f: [WASSAT, f, "--fast"])]
    if CADICAL:
        out.append(("cadical", lambda f: [CADICAL, "-q", f]))
    if CMS5:
        out.append(("cms5", lambda f: [CMS5, f]))
    return out


def verdict_of(text: str) -> str:
    for line in text.splitlines():
        if line.startswith("s "):
            return line[2:].strip()
    return "NONE"


def run(cmd, timeout):
    t0 = time.perf_counter()
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, check=False)
    except subprocess.TimeoutExpired:
        return timeout, "TIMEOUT"
    return time.perf_counter() - t0, verdict_of(p.stdout)


def median_time(cmd, timeout, reps=None):
    """Median of `reps` runs, but only while a repeat is worth its wall clock.

    Repetition exists to average out startup and scheduler noise, which is a
    few milliseconds. Once a single run takes longer than REP_CEILING that
    noise is already lost in the rounding, so measuring it three times buys
    nothing and costs three times the suite's runtime. Short rows — where the
    noise actually matters — still get the full median.
    """
    times, verdicts = [], set()
    for _ in range(reps or REPS):
        t, v = run(cmd, timeout)
        times.append(t)
        verdicts.add(v)
        if t > REP_CEILING:
            break
    if len(verdicts) != 1:
        raise SystemExit(f"nondeterministic verdicts {verdicts} for {cmd}")
    return statistics.median(times), verdicts.pop()


def outcome(ours: float, best_rival: float) -> str:
    """WIN / TIE / LOSS against the best rival, with a startup-noise floor."""
    if best_rival < TIE_FLOOR and ours < TIE_FLOOR:
        return "TIE"
    if ours * TIE_BAND < best_rival:
        return "WIN"
    if best_rival * TIE_BAND < ours:
        return "LOSS"
    return "TIE"


def geomean(values: list[float]) -> float | None:
    """None when no row raced to completion — a mean of nothing is not 1.0."""
    return math.exp(sum(math.log(v) for v in values) / len(values)) if values else None


def fmt_geomean(value: float | None) -> str:
    return "--" if value is None else f"{value:.2f}x"


def measure_row(path: str, budget: float, reps: int):
    """Median time and verdict per solver. TIMEOUT is recorded, not fatal."""
    times, verdicts = {}, {}
    for sname, mk in solvers():
        try:
            t, v = median_time(mk(path), budget, reps)
        except SystemExit as exc:
            raise SystemExit(f"{path}: {exc}") from exc
        times[sname], verdicts[sname] = t, v
    return times, verdicts


def check_verdicts(name: str, verdicts: dict, expect: str | None) -> str | None:
    """Return an error string when the row is not trustworthy, else None.

    A rival that answers nothing at all is refusing the input, not losing the
    race: CryptoMiniSat rejects the DIMACS variant that wraps a clause across
    lines, which CaDiCaL and wassat both accept. Such a rival drops out of the
    row. wassat answering nothing is always fatal — that is how a silently
    broken build gets caught instead of scoring a free win.
    """
    real = {k: v for k, v in verdicts.items() if v not in ("TIMEOUT",)}
    if real.get("wassat") == "NONE":
        return f"NO VERDICT from wassat (broken build?) verdicts={verdicts}"
    refused = sorted(k for k, v in real.items() if v == "NONE")
    real = {k: v for k, v in real.items() if v != "NONE"}
    if not real:
        # Everyone ran out of budget: uninformative, but not a correctness
        # failure. Only an actual refusal to read the input is one.
        return f"REFUSED by {refused}" if refused else None
    if len(set(real.values())) > 1:
        return f"VERDICT MISMATCH {verdicts}"
    if expect and real:
        got = next(iter(real.values()))
        want = {"sat": "SATISFIABLE", "unsat": "UNSATISFIABLE"}.get(expect, expect)
        if got != want:
            return f"WRONG ANSWER got={got} expected={want}"
    return None


def parity_section() -> int:
    print("\n== parity instances (regression gate) ==")
    failures = 0
    for name, path in PARITY:
        if not Path(path).is_file():
            print(f"  {name}: MISSING ({path})")
            failures += 1
            continue
        rows, verdicts = measure_row(path, 120, REPS)
        # A solver that emits no verdict (or only times out) is BROKEN, not
        # fast: a no-op such as /usr/bin/true reports "NONE" and must never
        # stand in as a passing row. Fail before the timing comparison.
        problem = check_verdicts(name, verdicts, None)
        if problem:
            print(f"  {name}: {problem}")
            failures += 1
            continue
        rivals = {k: v for k, v in rows.items()
                  if k != "wassat" and verdicts[k] not in ("TIMEOUT", "NONE")}
        best_rival = min(rivals.values()) if rivals else float("inf")
        # sub-100ms rows are process-startup noise, not solver signal
        ok = rows["wassat"] <= max(best_rival * TOLERANCE, 0.10)
        mark = "ok" if ok else "SLOW"
        if not ok:
            failures += 1
        # Dominance verdict: fastest by MARGIN on solver-bound rows, within
        # measurement noise on startup-bound ones. Informational unless
        # DOMINANCE=1 makes it gate.
        if best_rival < DOM_FLOOR:
            dom = rows["wassat"] <= best_rival + NOISE_MS
            dmark = "DOM~" if dom else "dom-miss"
        else:
            dom = rows["wassat"] * MARGIN <= best_rival
            dmark = f"DOM {best_rival / rows['wassat']:.2f}x" if dom else f"dom-miss {best_rival / rows['wassat']:.2f}x"
        if DOMINANCE and not dom:
            failures += 1
        cells = "  ".join(f"{k}={v:.2f}s" for k, v in rows.items())
        print(f"  {name}: {cells}  [{mark}] [{dmark}]")
    return failures


def survey_section(title: str, rows, root: Path, budget: float, published: bool,
                   reps: int | None = None) -> tuple[int, dict]:
    """Measure a breadth section. Correctness gates; speed is reported."""
    print(f"\n== {title} ==")
    failures = 0
    tally: dict[str, list] = defaultdict(list)
    if not rows:
        print("  (no instances pinned)")
        return 0, tally
    if not root.is_dir():
        print(f"  skipped: {root} not present "
              f"(fetch it, or point SATBENCH_EXT/SATBENCH_2026 elsewhere)")
        return 0, tally
    header = f"  {'instance':34s} {'wassat':>8s} {'cadical':>8s} {'cms5':>8s}  {'vs best':>9s}  result"
    if published:
        header += "   published field (competition hw)"
    last_family = None
    print(header)
    for row in rows:
        family, name, rel, expect = row[0], row[1], row[2], row[3]
        path = str(benchmark_path(root, rel))
        if family != last_family:
            print(f"  -- {family} --")
            last_family = family
        if not Path(path).is_file():
            print(f"  {name[:34]:34s} MISSING")
            continue
        times, verdicts = measure_row(path, budget, reps or SURVEY_REPS)
        problem = check_verdicts(name, verdicts, expect)
        if problem:
            print(f"  {name[:34]:34s} {problem}")
            failures += 1
            continue
        rivals = {k: v for k, v in times.items() if k != "wassat"}
        solved_rivals = {k: v for k, v in rivals.items() if verdicts[k] not in ("TIMEOUT", "NONE")}
        cells = "".join(
            "     n/a" if verdicts.get(k) == "NONE" else f" {times.get(k, float('nan')):8.2f}"
            for k in ("wassat", "cadical", "cms5"))
        if verdicts["wassat"] == "TIMEOUT":
            verdict = f"UNSOLVED@{budget:.0f}s"
            ratio = None
        elif solved_rivals:
            best = min(solved_rivals.values())
            ratio = best / times["wassat"]
            verdict = f"{outcome(times['wassat'], best):4s} {ratio:.2f}x"
        else:
            ratio = None
            verdict = "only wassat solved"
        line = f"  {name[:34]:34s}{cells}  {verdict}"
        if published:
            best, cad, kis = row[4], row[5], row[6]
            fmt = lambda x: "   -" if x is None else f"{x:6.1f}"
            line += f"   best={fmt(best)} cadical3={fmt(cad)} kissat={fmt(kis)}"
        print(line)
        tally[family].append((name, times.get("wassat"), ratio, verdicts["wassat"]))
    return failures, tally


def scoreboard(tally: dict) -> None:
    if not tally:
        return
    print("\n  by family:")
    print(f"    {'family':26s} {'n':>3s} {'W':>3s} {'T':>3s} {'L':>3s} {'we-lost':>8s} {'we-only':>8s}"
          f"  {'geomean vs best rival':>22s}")
    all_ratios = []
    tot = [0, 0, 0, 0, 0]
    for family in sorted(tally):
        rows = tally[family]
        ratios = [r for _n, _t, r, _v in rows if r]
        wins = sum(1 for _n, t, r, v in rows if r and outcome(t, t * r) == "WIN")
        losses = sum(1 for _n, t, r, v in rows if r and outcome(t, t * r) == "LOSS")
        ties = len(ratios) - wins - losses
        # a row splits four ways: raced (W/T/L), wassat alone could not finish,
        # or only wassat finished — the last two never enter the geomean
        unsolved = sum(1 for _n, _t, r, v in rows if v == "TIMEOUT")
        only_us = len(rows) - len(ratios) - unsolved
        all_ratios += ratios
        tot = [a + b for a, b in zip(tot, [wins, ties, losses, unsolved, only_us])]
        g = geomean(ratios)
        print(f"    {family[:26]:26s} {len(rows):3d} {wins:3d} {ties:3d} {losses:3d} "
              f"{unsolved:8d} {only_us:8d}  {fmt_geomean(g):>22s}")
    print(f"    {'TOTAL':26s} {sum(len(v) for v in tally.values()):3d} "
          f"{tot[0]:3d} {tot[1]:3d} {tot[2]:3d} {tot[3]:8d} {tot[4]:8d}  "
          f"{fmt_geomean(geomean(all_ratios)):>22s}")
    print("    (geomean > 1 means wassat is faster than the best installed rival)")


def output_model(text: str) -> set[int]:
    values: set[int] = set()
    for line in text.splitlines():
        if line.startswith("v "):
            values.update(int(token) for token in line[2:].split() if token != "0")
    return values


def dimacs_model_satisfies(path: Path, assignment: set[int]) -> bool:
    clause: list[int] = []
    for line in path.read_text().splitlines():
        if not line or line.startswith(("c", "p")):
            continue
        for token in line.split():
            literal = int(token)
            if literal == 0:
                if not any(lit in assignment for lit in clause):
                    return False
                clause.clear()
            else:
                clause.append(literal)
    return not clause


def lymphosat_section() -> int:
    """Check all twelve official GF(3) rows without 24 generic timeouts.

    `--drat path` deliberately exercises the Main-compatible path: SAT models
    are self-certifying and must leave no empty/stale proof artifact behind.
    Published times are printed only as competition-hardware context.
    """
    print("\n== SAT Competition 2026 lymphosat family (Main-compatible SAT path) ==")
    if not SC2026.is_dir():
        print(f"  skipped: {SC2026} not present")
        return 0
    failures = solved = 0
    print(f"  {'instance':12s} {'wassat':>9s} {'field best*':>12s}  result")
    with tempfile.TemporaryDirectory(prefix="wassat-lymphosat-") as directory:
        root = Path(directory)
        for name, rel, field_best in LYMPHOSAT:
            path = benchmark_path(SC2026, rel)
            if not path.is_file():
                print(f"  {name:12s} MISSING")
                continue
            times: list[float] = []
            output = ""
            proof = root / f"{name}.drat"
            for _ in range(LYMPH_REPS):
                t0 = time.perf_counter()
                try:
                    proc = subprocess.run(
                        [WASSAT, str(path), "--drat", str(proof)],
                        capture_output=True, text=True, timeout=LYMPH_BUDGET,
                        check=False,
                    )
                except subprocess.TimeoutExpired:
                    proc = None
                times.append(time.perf_counter() - t0)
                if proc is None:
                    output = ""
                    break
                output = proc.stdout
                if proc.returncode != 10 or verdict_of(output) != "SATISFIABLE":
                    break
                if proof.exists():
                    break
            model = output_model(output)
            ok = (
                len(times) == LYMPH_REPS
                and verdict_of(output) == "SATISFIABLE"
                and not proof.exists()
                and dimacs_model_satisfies(path, model)
            )
            elapsed = statistics.median(times)
            result = "verified SAT model" if ok else "FAIL"
            print(f"  {name:12s} {elapsed:8.3f}s {field_best:11.2f}s  {result}")
            if ok:
                solved += 1
            else:
                failures += 1
    print(f"  {solved}/{len(LYMPHOSAT)} official rows solved with checked models")
    print("  * published competition hardware; shown as context, not a local ratio")
    return failures


def xorshift_section() -> int:
    """Track the official xorshift-circuit SAT family with checked models.

    A timeout is performance evidence, not a correctness failure. Any emitted
    answer must still be SAT with exit 10 and satisfy the original DIMACS.
    """
    print("\n== SAT Competition 2026 xorshift family (exact circuit preimages) ==")
    if not SC2026.is_dir():
        print(f"  skipped: {SC2026} not present")
        return 0
    failures = solved = present = 0
    print(f"  {'instance':12s} {'wassat':>9s} {'field best*':>12s}  result")
    for name, rel, field_best in XORSHIFT:
        path = benchmark_path(SC2026, rel)
        if not path.is_file():
            print(f"  {name:12s} MISSING")
            continue
        present += 1
        times: list[float] = []
        output = ""
        timed_out = False
        for _ in range(XORSHIFT_REPS):
            t0 = time.perf_counter()
            try:
                proc = subprocess.run(
                    [WASSAT, str(path), "--fast"],
                    capture_output=True, text=True, timeout=XORSHIFT_BUDGET,
                    check=False,
                )
            except subprocess.TimeoutExpired:
                proc = None
            times.append(time.perf_counter() - t0)
            if proc is None:
                timed_out = True
                output = ""
                break
            output = proc.stdout
            if proc.returncode != 10 or verdict_of(output) != "SATISFIABLE":
                break
        if timed_out:
            print(f"  {name:12s} {XORSHIFT_BUDGET:8.2f}s {field_best:11.2f}s  UNSOLVED")
            continue
        model = output_model(output)
        ok = (
            len(times) == XORSHIFT_REPS
            and verdict_of(output) == "SATISFIABLE"
            and dimacs_model_satisfies(path, model)
        )
        elapsed = statistics.median(times)
        result = "verified SAT model" if ok else "FAIL"
        print(f"  {name:12s} {elapsed:8.3f}s {field_best:11.2f}s  {result}")
        if ok:
            solved += 1
        else:
            failures += 1
    print(f"  {solved}/{present} present official rows solved with checked models")
    print("  * published competition hardware; shown as context, not a local ratio")
    return failures


def tracked_section(title, instances, budget, expect=None) -> int:
    print(f"\n== {title} ==")
    failures = 0
    if not instances:
        print("  none configured (set LR5_37 and/or LR5_41)")
    for name, path in instances:
        if not Path(path).is_file():
            print(f"  {name}: missing encoder output, skipped")
            continue
        rival_t = rival_v = None
        rival_name = "none"
        if CADICAL:
            rival_name = "cadical"
            rival_t, rival_v = run([CADICAL, "-q", path], 300)
        elif CMS5:
            rival_name = "cms5"
            rival_t, rival_v = run([CMS5, path], 300)
        wt, wv = run([WASSAT, path, "--fast"], budget)
        # No verdict at all (a crash or a no-op binary) is a failure, distinct
        # from a legitimate TIMEOUT on a known-behind instance.
        if wv == "NONE":
            print(f"  {name}: NO VERDICT from wassat (broken)")
            failures += 1
            continue
        if wv not in ("TIMEOUT",) and rival_v and rival_v != "TIMEOUT" and wv != rival_v:
            print(f"  {name}: VERDICT MISMATCH wassat={wv} cadical={rival_v}")
            failures += 1
            continue
        if expect and (wv != expect or
                       (rival_v and rival_v != "TIMEOUT" and rival_v != expect)):
            print(f"  {name}: EXPECTED {expect}; wassat={wv} {rival_name}={rival_v}")
            failures += 1
            continue
        gap = (wt / rival_t) if rival_t else float("nan")
        solved = "SOLVED" if wv in ("SATISFIABLE", "UNSATISFIABLE") else f"unsolved@{budget:.0f}s"
        rival_text = "missing" if rival_t is None else f"{rival_t:.1f}s"
        # Once wassat solves a frontier instance the interesting number is
        # the speedup, not the deficit — print whichever direction holds.
        if rival_t and wv in ("SATISFIABLE", "UNSATISFIABLE"):
            verdict = f"{1.0 / gap:.1f}x FASTER" if gap < 1 else f"{gap:.1f}x behind"
        else:
            verdict = f"gap>={gap:.1f}x"
        print(f"  {name}: wassat {solved} ({wt:.1f}s)  {rival_name}={rival_text}  {verdict}")
    return failures


def frontier_section() -> int:
    return tracked_section("frontier instances (tracked, budgeted)", FRONTIER, FRONTIER_BUDGET)


def lrc13_section() -> int:
    return tracked_section(
        "LRC(13) terminal-lift reference instances (pinned UNSAT)",
        materialize_lrc13(),
        FRONTIER_BUDGET,
        "UNSATISFIABLE",
    )


def smoke_test() -> None:
    """A silently rebuilt binary is a no-op that would 'pass' every row."""
    probe = subprocess.run([WASSAT, "--version"], capture_output=True, text=True, check=False)
    if "Wassat" not in probe.stdout:
        raise SystemExit(
            f"{WASSAT} does not answer --version — it is a broken build, not a fast one.\n"
            f"Rebuild with: bin/tungsten -o bin/wassat bin/wassat.w --release"
        )


def main() -> None:
    if not Path(WASSAT).is_file():
        raise SystemExit(f"wassat not found at {WASSAT}")
    smoke_test()
    if not CADICAL and not CMS5:
        raise SystemExit("install CaDiCaL or CryptoMiniSat, or set CADICAL/CRYPTOMINISAT5")
    names = [n for n, _ in solvers()]
    print(f"[reference] REPS={REPS} TOLERANCE={TOLERANCE}x  solvers={names}")
    failures = parity_section()

    f, ext_tally = survey_section(
        "survey: breadth set (correctness gates, speed reported)", SURVEY, EXT, SURVEY_BUDGET, False)
    failures += f
    scoreboard(ext_tally)

    f, comp_tally = survey_section(
        "SAT Competition 2026 main track", COMPETITION, SC2026, COMP_BUDGET, True, COMP_REPS)
    failures += f
    scoreboard(comp_tally)
    if comp_tally:
        print("\n  published columns are the competition's own instance-wise results:")
        print("  different hardware and a 5000s budget, so they rank the field, not our clock.")

    failures += xorshift_section()
    failures += lymphosat_section()
    failures += frontier_section()
    failures += lrc13_section()

    if failures:
        raise SystemExit(f"\nFAIL: {failures} failure(s)")
    print("\nOK: parity held on every gate instance, verdicts agree across the survey")


if __name__ == "__main__":
    main()
