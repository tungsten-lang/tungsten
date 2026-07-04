#!/usr/bin/env python3
"""Generate xctrace .tracetemplate files for tungsten-flame.

Reads flame-counters.tracetemplate (a human-authored base template, set up
once in Instruments to give us the right outer structure) and produces
sibling templates that swap the captured Apple Silicon PMC event set.

The structure we exploit:
  base.tracetemplate is an NSKeyedArchiver binary plist. Inside its $objects
  array, exactly one entry is a bytes blob holding a JSON document. That
  JSON's "allEventsAndFormulas" field is a list of base64-encoded inner
  NSKeyedArchiver bplists — one per captured PMC event. To produce a sibling
  template we (a) rebuild that inner-bplist list with our chosen events,
  (b) re-emit the JSON, (c) re-emit the outer plist.

Each output template stays inside Apple Silicon's 8-PMC P-core budget so the
kernel doesn't time-multiplex.

Run with:  /usr/bin/python3 generate-templates.py
"""

import base64
import io
import json
import plistlib
from pathlib import Path

HERE = Path(__file__).parent
BASE = HERE / "flame-counters.tracetemplate"

# Event mnemonic + human explanation. Mnemonics validated against
# /usr/share/kpep/as5.plist (Apple M5).
TEMPLATES = {
    "flame-counters-cache.tracetemplate": [
        ("INST_BRANCH",                "Retired branch instructions including calls and returns"),
        ("BRANCH_MISPRED_NONSPEC",     "Mispredicted branches (non-speculative)"),
        ("L1D_CACHE_MISS_LD_NONSPEC",  "L1 data cache load misses (non-speculative)"),
        ("L1I_CACHE_MISS_DEMAND",      "L1 instruction cache demand misses"),
        ("PL2_CACHE_MISS_LD",          "L2 cache load misses (LLC proxy on Apple Silicon)"),
        ("L1D_TLB_MISS_NONSPEC",       "L1 data TLB misses (non-speculative)"),
        ("L1I_TLB_MISS_DEMAND",        "L1 instruction TLB demand misses"),
        ("L2_TLB_MISS_DATA",           "L2 TLB data misses"),
    ],
    "flame-counters-stalls.tracetemplate": [
        ("ARM_STALL_FRONTEND",         "Stalled cycles in the frontend (instruction delivery)"),
        ("ARM_STALL_BACKEND",          "Stalled cycles in the backend (execution and data)"),
        ("L2_TLB_MISS_INSTRUCTION",    "L2 TLB instruction misses"),
    ],
}


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


def generate(out_path: Path, events: list[tuple[str, str]]) -> None:
    with open(BASE, "rb") as f:
        outer = plistlib.load(f)

    blob_idx = find_json_blob_index(outer["$objects"])
    cfg = json.loads(outer["$objects"][blob_idx])
    cfg["allEventsAndFormulas"] = [event_b64(m, e) for m, e in events]
    # Point the PMI fallback at the first event in our list so the trigger
    # event is one we're capturing rather than the base template's leftover.
    cfg["pmiEventAliasOrMnemonic"] = events[0][0]
    outer["$objects"][blob_idx] = json.dumps(cfg).encode("utf-8")

    with open(out_path, "wb") as f:
        plistlib.dump(outer, f, fmt=plistlib.FMT_BINARY)

    print(f"  {out_path.name}  ({len(events)} events, {out_path.stat().st_size} bytes)")


if __name__ == "__main__":
    print(f"Base: {BASE.name}")
    for name, events in TEMPLATES.items():
        generate(HERE / name, events)
