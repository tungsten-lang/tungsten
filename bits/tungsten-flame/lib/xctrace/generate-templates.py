#!/usr/bin/env python3
"""Generate xctrace .tracetemplate files for tungsten-flame.

Reads flame-counters.tracetemplate (a human-authored base template, set up
once in Instruments to give us the right outer structure) and produces the
templates that swap the captured Apple Silicon PMC event set — including
flame-counters.tracetemplate itself, whose event list is regenerated in
place (only the counters configuration changes; the outer structure is
preserved).

The structure we exploit:
  base.tracetemplate is an NSKeyedArchiver binary plist. Inside its $objects
  array, exactly one entry is a bytes blob holding a JSON document. That
  JSON's "allEventsAndFormulas" field is a list of base64-encoded inner
  NSKeyedArchiver bplists — one per captured PMC event. To produce a
  template we (a) rebuild that inner-bplist list with our chosen events,
  (b) re-emit the JSON, (c) re-emit the outer plist.

Chip-aware event selection: Apple's kpep database names differ per core
generation (as3/M3 has no PL2_* L2-cache events, no LD_SRC_MEMSYS_* and no
ARM_STALL_*; as5/M5 has them all), so each metric lists candidate events in
preference order and the generator keeps the first one the running
machine's kpep defines that also fits a PMC slot. Events carry a
counters_mask restricting which physical counters they may occupy; a
greedy scarcest-first assignment keeps every template inside the chip's
configurable-PMC budget so the kernel never time-multiplexes event sets.

Each template gets a sibling `.events` manifest — one "label<TAB>event"
line per slot, in slot order — which Sampler.counter_labels reads at
runtime so the metric labels always match the template's slot order.

Run with:  /usr/bin/python3 generate-templates.py
"""

import base64
import io
import json
import plistlib
import re
import subprocess
from pathlib import Path

HERE = Path(__file__).parent
BASE = HERE / "flame-counters.tracetemplate"

# Sample every N occurrences of the first event (PMI) rather than on a wall
# timer: time-based windows (~1ms) span whole phase cycles of the profiled
# program, smearing every metric toward the time distribution (measured:
# identical per-function miss rates to two decimals). 250K instructions is
# well under typical inner-phase lengths.
PMI_THRESHOLD = 250000

# Per template: (label, [candidate events best-first], explanation).
# Labels are what the sampler reports (and what counter_rates.w keys on);
# a metric whose candidates are all absent on this chip drops its slot.
METRICS = {
    # Default sampling path (Sampler.profile_macos): stacks paired with
    # cumulative per-core counter snapshots. Slot 0 is also the PMI trigger.
    "flame-counters.tracetemplate": [
        ("branches",              ["INST_BRANCH"],                                 "Retired branch instructions including calls and returns"),
        ("branch-misses",         ["BRANCH_MISPRED_NONSPEC", "ARM_BR_MIS_PRED"],   "Mispredicted branches"),
        ("L1-dcache-load-misses", ["L1D_CACHE_MISS_LD"],                           "Loads that missed the L1 data cache"),
        ("LLC-load-misses",       ["PL2_CACHE_MISS_LD", "MMU_TABLE_WALK_DATA"],    "L2 cache load misses (page-walk proxy where PL2_* is absent)"),
        ("L1d-long-latency",      ["ARM_L1D_CACHE_LMISS_RD", "LDST_UNIT_WAITING_OLD_L1D_CACHE_MISS"], "Long-latency L1 data misses (cycles waiting on an L1D miss where the ARM event is absent)"),
        ("dTLB-load-misses",      ["L1D_TLB_MISS"],                                "Loads and stores that missed the L1 data TLB"),
        ("L1-icache-load-misses", ["L1I_CACHE_MISS_DEMAND"],                       "L1 instruction cache demand misses"),
        ("L2-TLB-data-misses",    ["L2_TLB_MISS_DATA"],                            "Loads and stores that missed the L2 TLB"),
    ],
    # `flame --counters` default set: instructions + cycles alongside the
    # dominant miss families, so the analyzer can print per-function IPC
    # and misses-per-kilo-instruction (MPKI) rather than raw event counts.
    # L1D_CACHE_MISS_LD/ST are the speculative counters on purpose — they
    # count the cache traffic that actually happened, which is what
    # prefetch/blocking work needs; INST_ALL (retired) is the denominator.
    "flame-counters-rates.tracetemplate": [
        ("instructions",           ["INST_ALL"],                                   "All retired instructions"),
        ("cycles",                 ["CORE_ACTIVE_CYCLE"],                          "Cycles while the core was active"),
        ("L1-dcache-load-misses",  ["L1D_CACHE_MISS_LD"],                          "Loads that missed the L1 data cache"),
        ("L1-dcache-store-misses", ["L1D_CACHE_MISS_ST"],                          "Stores that missed the L1 data cache"),
        ("LLC-load-misses",        ["PL2_CACHE_MISS_LD", "MMU_TABLE_WALK_DATA"],   "Load requests that missed the L2 cache (page-walk proxy where PL2_* is absent)"),
        ("memsys-loads",           ["LD_SRC_MEMSYS_NONSPEC"],                      "Retired loads sourced from the memory system (SLC or DRAM)"),
        ("dTLB-misses",            ["L1D_TLB_MISS"],                               "Loads and stores that missed the L1 data TLB"),
        ("L2-TLB-data-misses",     ["L2_TLB_MISS_DATA"],                           "Loads and stores that missed the L2 TLB"),
    ],
    "flame-counters-cache.tracetemplate": [
        ("branches",              ["INST_BRANCH"],                                 "Retired branch instructions including calls and returns"),
        ("branch-misses",         ["BRANCH_MISPRED_NONSPEC", "ARM_BR_MIS_PRED"],   "Mispredicted branches"),
        ("L1-dcache-load-misses", ["L1D_CACHE_MISS_LD_NONSPEC", "L1D_CACHE_MISS_LD"], "L1 data cache load misses"),
        ("L1-icache-misses",      ["L1I_CACHE_MISS_DEMAND"],                       "L1 instruction cache demand misses"),
        ("LLC-load-misses",       ["PL2_CACHE_MISS_LD", "MMU_TABLE_WALK_DATA"],    "L2 cache load misses (page-walk proxy where PL2_* is absent)"),
        ("dTLB-misses",           ["L1D_TLB_MISS_NONSPEC", "L1D_TLB_MISS"],        "L1 data TLB misses"),
        ("iTLB-misses",           ["L1I_TLB_MISS_DEMAND"],                         "L1 instruction TLB demand misses"),
        ("L2-TLB-data-misses",    ["L2_TLB_MISS_DATA"],                            "L2 TLB data misses"),
    ],
    "flame-counters-stalls.tracetemplate": [
        ("frontend-stall-cycles", ["ARM_STALL_FRONTEND", "MAP_DISPATCH_BUBBLE"],   "Stalled cycles in the frontend (instruction delivery / dispatch bubbles)"),
        ("backend-stall-cycles",  ["ARM_STALL_BACKEND", "MAP_STALL"],              "Stalled cycles in the backend (execution and data / map stalls)"),
        ("L2-TLB-instr-misses",   ["L2_TLB_MISS_INSTRUCTION"],                     "L2 TLB instruction misses"),
    ],
}


def chip_kpep() -> tuple[dict, int]:
    """The running chip's kpep event table and its configurable-counter
    mask (which physical PMC bits a mask-less event may occupy)."""
    brand = subprocess.run(["sysctl", "-n", "machdep.cpu.brand_string"],
                           capture_output=True, text=True).stdout.strip()
    m = re.search(r"Apple M(\d+)", brand)
    name = f"as{m.group(1)}" if m else "as5"
    path = Path(f"/usr/share/kpep/{name}.plist")
    if not path.exists():
        path = sorted(Path("/usr/share/kpep").glob("as*.plist"))[-1]
    with open(path, "rb") as f:
        db = plistlib.load(f)
    cpu = db.get("system", {}).get("cpu", {})
    events = db.get("events") or cpu.get("events", {})
    config_mask = cpu.get("config_counters", 0xFF)
    print(f"kpep: {path.name} ({brand}, {len(events)} events, "
          f"{bin(config_mask).count('1')} configurable PMCs)")
    return events, config_mask


def schedulable(chosen, events, config_mask):
    """Greedy PMC assignment: events carry a counters_mask restricting which
    physical counters they may occupy (absent mask = any configurable one).
    Assign scarcest-first; return (kept in metric order, dropped labels)."""
    ranked = []
    for pos, (label, ev, expl) in enumerate(chosen):
        m = events[ev].get("counters_mask") or config_mask
        m &= config_mask
        ranked.append((bin(m).count("1"), pos, m, (label, ev, expl)))
    used = 0
    keep = []
    dropped = []
    for _, pos, m, item in sorted(ranked):
        free = m & ~used
        if free:
            used |= free & -free
            keep.append((pos, item))
        else:
            dropped.append(item[0])
    return [item for _, item in sorted(keep)], dropped


def choose_events(metrics, events, config_mask):
    """Pick one event per metric: the best available candidate that still
    fits a PMC slot next to the others. A metric whose candidate cannot be
    scheduled falls through to its next candidate; out of candidates, its
    slot is dropped."""
    avail = {label: [c for c in cands if c in events] for label, cands, _ in metrics}
    for label, cands, _ in metrics:
        if not avail[label]:
            print(f"    no event for {label} ({', '.join(cands)}) — slot dropped")
    next_cand = {label: 0 for label, _, _ in metrics}
    while True:
        chosen = []
        for label, _, expl in metrics:
            i = next_cand[label]
            if i < len(avail[label]):
                chosen.append((label, avail[label][i], expl))
        kept, dropped = schedulable(chosen, events, config_mask)
        if not dropped:
            return kept
        for label in dropped:
            ev = avail[label][next_cand[label]]
            next_cand[label] += 1
            more = next_cand[label] < len(avail[label])
            print(f"    {ev} ({label}) unschedulable — "
                  + (f"trying {avail[label][next_cand[label]]}" if more else "slot dropped"))


def event_b64(mnemonic: str, explanation: str) -> str:
    """Build the inner NSKeyedArchiver bplist for one PMC event entry,
    return its base64 string ready to drop into allEventsAndFormulas."""
    inner = {
        "$version": 100000,
        "$archiver": "NSKeyedArchiver",
        "$top": {"root": plistlib.UID(1)},
        "$objects": [
            "$null",
            {
                "$class": plistlib.UID(4),
                "_aliasOrMnemonic": plistlib.UID(2),
                "_beingEdited": False,
                "_displayName": plistlib.UID(2),
                "_explanation": plistlib.UID(3),
                "_formulaEvaluator": plistlib.UID(0),
                "_formulaText": plistlib.UID(0),
                "_mnemonic": plistlib.UID(2),
            },
            mnemonic,
            explanation,
            {
                "$classes": ["XRCountersSetupEventOrFormula", "NSObject"],
                "$classname": "XRCountersSetupEventOrFormula",
            },
        ],
    }
    buf = io.BytesIO()
    plistlib.dump(inner, buf, fmt=plistlib.FMT_BINARY)
    return base64.b64encode(buf.getvalue()).decode("ascii")


def find_json_blob_index(objects: list) -> int:
    for i, obj in enumerate(objects):
        if isinstance(obj, bytes) and obj.startswith(b'{"'):
            return i
    raise SystemExit("No JSON blob in $objects (expected NSData starting with `{\"`)")


def generate(out_path: Path, base: dict, events: list[tuple[str, str]]) -> None:
    outer = plistlib.loads(plistlib.dumps(base, fmt=plistlib.FMT_BINARY))  # deep copy
    blob_idx = find_json_blob_index(outer["$objects"])
    cfg = json.loads(outer["$objects"][blob_idx])
    cfg["allEventsAndFormulas"] = [event_b64(m, e) for m, e in events]
    # The PMI trigger is the first event in our list so the sampling
    # cadence follows something we're capturing rather than the base
    # template's leftover.
    cfg["pmiEventAliasOrMnemonic"] = events[0][0]
    cfg["sampleByTime"] = False
    cfg["pmiThreshold"] = PMI_THRESHOLD
    outer["$objects"][blob_idx] = json.dumps(cfg).encode("utf-8")

    with open(out_path, "wb") as f:
        plistlib.dump(outer, f, fmt=plistlib.FMT_BINARY)

    print(f"  {out_path.name}  ({len(events)} events, {out_path.stat().st_size} bytes)")


if __name__ == "__main__":
    print(f"Base: {BASE.name}")
    with open(BASE, "rb") as f:
        base = plistlib.load(f)
    events, config_mask = chip_kpep()
    for name, metrics in METRICS.items():
        print(f"  {name}:")
        chosen = choose_events(metrics, events, config_mask)
        if not chosen:
            print("    nothing available, skipped")
            continue
        generate(HERE / name, base, [(ev, expl) for _, ev, expl in chosen])
        manifest = (HERE / name).with_suffix(".events")
        manifest.write_text("".join(f"{label}\t{ev}\n" for label, ev, _ in chosen))
        print(f"  {manifest.name}: " + ", ".join(ev for _, ev, _ in chosen))
