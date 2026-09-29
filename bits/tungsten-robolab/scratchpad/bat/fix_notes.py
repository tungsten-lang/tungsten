"""Correct the `note` text of arena entries (champions.json and history.jsonl), under the arena lock, as the handoff describes:
take the fcntl lock, replace the text on exactly those records, check every parsed record differs only in `note`, os.replace.

    .venv/bin/python scratchpad/bat/fix_notes.py notes.json
notes.json: [{"trial": "...", "time": "YYYY-MM-DD HH:MM:SS", "note": "new text"}, ...]   (an entry is found by trial + its `time`)
"""
import json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "playground"))
import arena

fixes = {(f["trial"], f["time"]): f["note"] for f in json.load(open(sys.argv[1]))}
with arena.locked():
    # history.jsonl
    lines = open(arena.HISTORY).read().splitlines()
    out, hits = [], 0
    for l in lines:
        rec = json.loads(l)
        key = (rec.get("trial"), rec.get("time"))
        if key in fixes:
            new = dict(rec, note=fixes[key])
            assert {k: v for k, v in new.items() if k != "note"} == {k: v for k, v in rec.items() if k != "note"}
            l = json.dumps(new)
            hits += 1
        out.append(l)
    tmp = arena.HISTORY + f".{os.getpid()}"
    open(tmp, "w").write("\n".join(out) + "\n")
    os.replace(tmp, arena.HISTORY)
    # champions.json
    champs = arena.load_json(arena.CHAMPS, {})
    ch = 0
    for name, e in champs.items():
        key = (name, e.get("time"))
        if key in fixes:
            e["note"] = fixes[key]
            ch += 1
    arena.save_json(arena.CHAMPS, champs)
print(f"history records fixed: {hits}; champions fixed: {ch}")
