#!/usr/bin/env python3
"""Check that every backticked path in a Markdown file exists.

    .venv/bin/python tools/check_doc_paths.py HANDOFF_20260929.md

A token counts as a path when it contains a slash or ends in a known extension and has no spaces
or shell syntax. It is looked up relative to bits/tungsten-robolab, then the repo root, then as an
absolute path. Glob-like tokens (`*`, `<...>`, `{a,b}`) are checked by their directory only.
"""
import os
import re
import sys

HERE = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
EXT = (".w", ".py", ".md", ".json", ".jsonl", ".txt", ".sh", ".mp4", ".png", ".gif", ".npz")


def candidates(tok):
    if tok.startswith("/"):
        return [tok]
    if tok.startswith("~/"):
        return [os.path.expanduser(tok)]
    return [os.path.join(HERE, tok), os.path.join(REPO, tok)]


def looks_like_path(tok):
    if re.search(r"\s|[=()\[\]$;|&]", tok) or tok.startswith("-") or tok.startswith("http"):
        return False
    return "/" in tok or tok.endswith(EXT)


def expand(tok):
    """Turn brace groups into alternatives; cut a glob or placeholder to its directory."""
    m = re.search(r"\{([^{}]*)\}", tok)
    if m:
        return [x for alt in m.group(1).split(",") for x in expand(tok[:m.start()] + alt + tok[m.end():])]
    if re.search(r"[*<]|\.\.\.", tok):
        head = re.split(r"[*<]|\.\.\.", tok)[0]
        return [head.rsplit("/", 1)[0] + "/" if "/" in head else "."]
    return [tok]


bad, seen = [], 0
for path in sys.argv[1:]:
    text = open(path).read()
    for tok in sorted(set(re.findall(r"`([^`\n]+)`", text))):
        if not looks_like_path(tok):
            continue
        for t in expand(tok):
            seen += 1
            if not any(os.path.exists(c) for c in candidates(t)):
                bad.append((path, tok, t))
print(f"{seen} paths checked, {len(bad)} missing")
for path, tok, t in bad:
    print(f"  {path}: `{tok}`" + (f" (looked for {t})" if t != tok else ""))
sys.exit(1 if bad else 0)
