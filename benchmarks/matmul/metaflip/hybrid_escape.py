"""Run a staged C3-quotient -> symmetry-break -> ordinary metaflip search.

This is deliberately a thin coordinator: both hot loops are generated
Tungsten executables.  The first stage uses ``sym_gen2_anyaxis`` and therefore
keeps every mutation C3-closed.  Its exact result is then thawed with a fixed
cube split and handed to the bucketed full flip-graph walker.  A separate
``metal`` command runs any portfolio slot through a one-round generated Metal
relay, which makes mixed-family A/B experiments reproducible without changing
the long-running FlipFleet coordinator.

Examples:

  python3 hybrid_escape.py run bank.jsonl out/hybrid --slots 3 --c3-moves 200000
  python3 hybrid_escape.py metal bank.jsonl out/metal --slot 7 --steps 10000
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
ZOO = HERE.parent / "zoo"
if str(ZOO) not in sys.path:
    sys.path.insert(0, str(ZOO))

from bench_decomp import verify as independent_verify
from bucket_gen import gen as bucket_gen
from escape_portfolio import (
    EscapeMove,
    PortfolioEntry,
    apply_move,
    canonical,
    emit_bare,
    enumerate_moves,
    read_bank,
    profile_scheme,
    scheme_digest,
    validate_scheme_masks,
    verify_bank,
    write_bank,
)
from gpu_cal2zone_gen import gen as gpu_cal2zone_gen
from sym_escape import is_c3_closed
from sym_gen2_anyaxis import gen as c3_gen


def emit_r(scheme, path: Path) -> None:
    with path.open("w", encoding="utf-8") as stream:
        for u, v, w in canonical(scheme):
            stream.write(f"R {u} {v} {w}\n")


def parse_final_scheme(output: str) -> tuple[int, tuple]:
    """Parse the final verified R block emitted by either Tungsten walker."""
    matches = list(re.finditer(r"^DONE best=(\d+) verify=(\d+)\s*$", output, re.M))
    if not matches:
        raise ValueError("walker output has no DONE line")
    done = matches[-1]
    rank, verified = int(done.group(1)), int(done.group(2))
    if verified != 1:
        raise ValueError("walker's final probabilistic verification failed")
    terms = []
    for line in output[done.end():].splitlines():
        match = re.match(r"^R (\d+) (\d+) (\d+)$", line.strip())
        if match:
            terms.append(tuple(int(value) for value in match.groups()))
            if len(terms) == rank:
                break
    if len(terms) != rank:
        raise ValueError(f"walker emitted {len(terms)} final terms, expected {rank}")
    terms = canonical(terms)
    if len(terms) != rank:
        raise ValueError("walker final block contains parity duplicates")
    return rank, terms


def compile_tungsten(source: Path, binary: Path, env=None) -> float:
    started = time.monotonic()
    result = subprocess.run(
        [str(ROOT / "bin" / "tungsten"), "-o", str(binary), str(source),
         "--release", "--native", "--fast", "--lto"],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
        timeout=1200,
    )
    if result.returncode:
        raise RuntimeError("Tungsten compile failed:\n" + result.stdout + result.stderr)
    return time.monotonic() - started


def run_binary(argv: list[str], log: Path, timeout: int = 1200) -> tuple[str, float]:
    started = time.monotonic()
    result = subprocess.run(
        argv, cwd=ROOT, capture_output=True, text=True, timeout=timeout
    )
    output = result.stdout + result.stderr
    log.write_text(output, encoding="utf-8")
    if result.returncode:
        raise RuntimeError(f"{argv[0]} exited {result.returncode}; see {log}")
    return output, time.monotonic() - started


def run_c3_stage(entry, n: int, moves: int, salt: int, work: Path):
    if not is_c3_closed(entry.scheme, n):
        raise ValueError("C3 stage requires a C3-closed portfolio slot")
    seed_path = work / f"c3_seed_{salt}.txt"
    source = work / f"c3_{salt}.w"
    binary = work / f"c3_{salt}"
    emit_r(entry.scheme, seed_path)
    source.write_text(
        c3_gen(n, max(1, entry.profile["rank"] - 1), str(seed_path),
               cap=moves, plusper=200, band=15),
        encoding="utf-8",
    )
    compile_seconds = compile_tungsten(source, binary)
    output, run_seconds = run_binary(
        [str(binary), str(1009 + salt)], work / f"c3_{salt}.log"
    )
    rank, scheme = parse_final_scheme(output)
    validate_scheme_masks(scheme, n, "C3 native result")
    if rank != len(scheme) or not independent_verify(scheme, n, n, n):
        raise AssertionError("C3 native result failed independent tensor verification")
    if not is_c3_closed(scheme, n):
        raise AssertionError("C3 native walker lost symmetry closure")
    return scheme, compile_seconds, run_seconds


def run_full_stage(
    scheme, n: int, moves: int, salt: int, source: Path, binary: Path, work: Path
):
    seed_path = work / f"full_seed_{salt}.txt"
    emit_bare(scheme, str(seed_path))
    output, seconds = run_binary(
        [str(binary), str(7001 + salt), "", "", "", str(seed_path)],
        work / f"full_{salt}.log",
    )
    rank, final = parse_final_scheme(output)
    validate_scheme_masks(final, n, "full native result")
    if rank != len(final) or not independent_verify(final, n, n, n):
        raise AssertionError("full native result failed independent tensor verification")
    return final, seconds


def select_c3_slots(reports, entries, slots: int, include_base: bool = True):
    """Select an exact number of C3 inputs, including slot zero as the control."""
    if not isinstance(slots, int) or slots <= 0:
        raise ValueError("slots must be positive")
    if len(reports) != len(entries):
        raise ValueError("bank reports and entries have different lengths")
    eligible = [
        (report, entry) for report, entry in zip(reports, entries)
        if report["c3"] and (include_base or entry.recipe)
    ]
    if slots > len(eligible):
        control = "including" if include_base else "excluding"
        raise ValueError(
            f"requested {slots} slots, but only {len(eligible)} C3 slots are "
            f"available {control} the base control"
        )
    return eligible[:slots]


def choose_symmetry_break(scheme, n: int, salt: str):
    """Prefer a fixed-cube break, then use any ordinary split that leaves C3."""
    if not is_c3_closed(scheme, n):
        raise ValueError("symmetry-break stage requires a C3-closed scheme")
    for kind in ("break", "split"):
        for move in enumerate_moves(scheme, n, kind, limit=256, salt=salt):
            output = apply_move(scheme, n, move)
            if not is_c3_closed(output, n):
                return move, output
    raise RuntimeError("quotient result has no ordinary symmetry-breaking split")


def run_hybrid(
    bank: str,
    outdir: str,
    slots: int,
    c3_moves: int,
    full_moves: int,
    include_base: bool = True,
):
    if not isinstance(slots, int) or slots <= 0:
        raise ValueError("slots must be positive")
    if not isinstance(c3_moves, int) or c3_moves <= 0:
        raise ValueError("c3_moves must be positive")
    if not isinstance(full_moves, int) or full_moves <= 0:
        raise ValueError("full_moves must be positive")
    reports = verify_bank(bank)
    header, entries = read_bank(bank)
    n = int(header["n"])
    work = Path(outdir).resolve()
    work.mkdir(parents=True, exist_ok=True)
    closed = select_c3_slots(reports, entries, slots, include_base)

    # Compile the ordinary bucketed hot loop once.  Runtime seed loading lets
    # every quotient result take a different exact break without recompilation.
    full_source = work / "full_walker.w"
    full_binary = work / "full_walker"
    max_rank = max(report["rank"] for report, _ in closed) + 16
    full_source.write_text(
        bucket_gen(
            n, n, n, max(1, entries[0].profile["rank"] - 1),
            arr=max_rank + 80, cap=full_moves, runtime_seed=True,
            band=8, plusper=200, plus_axes="any",
        ),
        encoding="utf-8",
    )
    full_compile = compile_tungsten(full_source, full_binary)

    base = set(entries[0].scheme)
    results = []
    for sequence, (report, entry) in enumerate(closed):
        quotient, c3_compile, c3_seconds = run_c3_stage(
            entry, n, c3_moves, sequence, work
        )
        break_move, thawed = choose_symmetry_break(
            quotient, n, f"hybrid:{sequence}"
        )
        if not independent_verify(thawed, n, n, n):
            raise AssertionError("thaw identity failed independent tensor verification")
        final, full_seconds = run_full_stage(
            thawed, n, full_moves, sequence, full_source, full_binary, work
        )
        profile = profile_scheme(canonical(final), base, n)
        base_digest = scheme_digest(base)
        entry_digest = scheme_digest(entry.scheme)
        quotient_digest = scheme_digest(quotient)
        thawed_digest = scheme_digest(thawed)
        final_digest = scheme_digest(final)
        provenance = {
            "mode": "staged",
            "replayable": False,
            "base_sha256": base_digest,
            "result_sha256": final_digest,
            "stages": [
                {
                    "kind": "source-slot",
                    "source_slot": report["id"],
                    "input_sha256": base_digest,
                    "output_sha256": entry_digest,
                    "replayable": False,
                },
                {
                    "kind": "c3-walk",
                    "input_sha256": entry_digest,
                    "output_sha256": quotient_digest,
                    "replayable": False,
                },
                {
                    "kind": break_move.kind,
                    "input_sha256": quotient_digest,
                    "output_sha256": thawed_digest,
                    "replayable": True,
                    "move": break_move.as_json(),
                    "input_terms": [list(term) for term in canonical(quotient)],
                },
                {
                    "kind": "full-walk",
                    "input_sha256": thawed_digest,
                    "output_sha256": final_digest,
                    "replayable": False,
                },
            ],
        }
        result = PortfolioEntry(
            canonical(final),
            entry.recipe + ("c3-walk", break_move.kind, "full-walk"),
            (),
            profile,
            provenance,
        )
        results.append(result)
        print(
            f"slot={report['id']} c3 {report['rank']}->{len(quotient)} "
            f"thaw->{len(thawed)} full->{len(final)} density={profile['density']} "
            f"c3_compile={c3_compile:.3f}s c3_run={c3_seconds:.3f}s "
            f"full_run={full_seconds:.3f}s"
        )
    result_path = work / "hybrid_results.jsonl"
    result_entries = [
        PortfolioEntry(canonical(base), (), (), profile_scheme(base, base, n))
    ] + results
    write_bank(str(result_path), result_entries, n, os.path.basename(bank))
    verify_bank(str(result_path))
    print(f"full_compile={full_compile:.3f}s; wrote {result_path}")
    return result_path


def run_metal(
    bank: str, outdir: str, slot: int, steps: int, walkers: int, escapes: int
):
    for name, value in (("steps", steps), ("walkers", walkers),
                        ("escapes", escapes)):
        if not isinstance(value, int) or value <= 0:
            raise ValueError(f"{name} must be positive")
    reports = verify_bank(bank)
    header, entries = read_bank(bank)
    n = int(header["n"])
    if not 0 <= slot < len(entries):
        raise ValueError(f"slot must be in [0,{len(entries)})")
    work = Path(outdir).resolve()
    work.mkdir(parents=True, exist_ok=True)
    seed = work / f"metal_seed_{slot}.txt"
    emit_bare(entries[slot].scheme, str(seed))
    cap = reports[slot]["rank"] + 32
    mask_bytes = 8 if n * n > 30 else 4
    wpg = 16
    while cap * wpg * mask_bytes * 3 > 32768:
        wpg //= 2
    walkers -= walkers % wpg
    if walkers <= 0:
        walkers = wpg
    source = work / "metal_relay.w"
    llpath = work / "metal_relay.ll"
    binary = work / "metal_relay"
    output_seed = work / "metal_best.txt"
    # The relay may legitimately produce no result file.  Never reinterpret a
    # previous invocation's best as the output of this launch.
    output_seed.unlink(missing_ok=True)
    src, shared = gpu_cal2zone_gen(
        n, n, n, cap, wpg, cap, str(llpath), nw=walkers,
        steps=steps, rounds=1,
    )
    source.write_text(src, encoding="utf-8")
    env = dict(os.environ, TUNGSTEN_LL_PATH=str(llpath))
    compile_seconds = compile_tungsten(source, binary, env)
    argv = [
        str(binary), str(seed), str(output_seed), str(n), str(n), str(n),
        "x", "0", str(steps), "1", "4", "150000", "60000", "7",
        str(walkers), "", str(escapes),
    ]
    output, run_seconds = run_binary(argv, work / "metal.log")
    print(
        f"Metal slot={slot} recipe={'+'.join(entries[slot].recipe) or 'base'} "
        f"rank={reports[slot]['rank']} density={reports[slot]['density']} "
        f"walkers={walkers} WPG={wpg} shared={shared}/32768 "
        f"compile={compile_seconds:.3f}s run={run_seconds:.3f}s"
    )
    for line in output.splitlines():
        if line.startswith(("GPU cfg:", "round ", "GPU-CAL2ZONE")):
            print(line)
    if output_seed.exists() and output_seed.stat().st_size:
        lines = output_seed.read_text(encoding="utf-8").splitlines()
        head = [int(value) for value in lines[0].split()]
        if len(head) != 2:
            raise ValueError("Metal result header must be 'rank density'")
        result_rank, reported_density = head
        result = canonical(
            tuple(tuple(int(value) for value in line.split()) for line in lines[1:])
        )
        validate_scheme_masks(result, n, "Metal result")
        if len(result) != result_rank:
            raise ValueError("Metal result rank does not match its normalized terms")
        if not independent_verify(result, n, n, n):
            raise AssertionError("Metal result failed independent tensor reconstruction")
        profile = profile_scheme(result, entries[0].scheme, n)
        if profile["density"] != reported_density:
            raise ValueError("Metal result density header mismatch")
        print(
            f"independent exact=1 rank={profile['rank']} density={profile['density']} "
            f"c3={int(profile['c3'])} fixed={profile['fixed']} "
            f"flip_pairs={profile['flip_pairs']}"
        )


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    run = sub.add_parser("run", help="run C3, thaw, and ordinary native stages")
    run.add_argument("bank")
    run.add_argument("outdir")
    run.add_argument("--slots", type=int, default=1)
    run.add_argument("--c3-moves", type=int, default=200000)
    run.add_argument("--full-moves", type=int, default=200000)
    run.add_argument(
        "--exclude-base", action="store_true",
        help="exclude slot zero instead of running it as the control",
    )
    metal = sub.add_parser("metal", help="benchmark a bank slot on real Metal")
    metal.add_argument("bank")
    metal.add_argument("outdir")
    metal.add_argument("--slot", type=int, default=0)
    metal.add_argument("--steps", type=int, default=10000)
    metal.add_argument("--walkers", type=int, default=256)
    metal.add_argument("--escapes", type=int, default=1)
    args = parser.parse_args(argv)
    if args.command == "run":
        run_hybrid(
            args.bank, args.outdir, args.slots, args.c3_moves, args.full_moves,
            not args.exclude_base,
        )
    else:
        run_metal(args.bank, args.outdir, args.slot, args.steps,
                  args.walkers, args.escapes)


if __name__ == "__main__":
    main()
