"""Assemble the README's "Table tennis round 10" section from scratchpad/tt/README_r10_*.md and insert it (once) before the Relocate section.

    python3 scratchpad/tt/assemble_readme.py RESULT_FILE ARENA_FILE [--dry]
"""
import os, sys

ROOT = "/Users/erik/tungsten/bits/tungsten-robolab"
H = "### Table tennis: where P2 is lost, a bounce-tick artifact, and a screening design (round 10)"
ANCHOR = "### Relocate: controlled transport, hold-inside placement, far-side arm control (round 5)"


def rd(p):
    return open(os.path.join(ROOT, p)).read().rstrip() + "\n"


def main():
    result = open(sys.argv[1]).read().strip()
    arena = open(sys.argv[2]).read().strip()
    head = rd("scratchpad/tt/README_r10_draft.md").split("TODO_RESULT")[0]
    tools = "**Tools**" + rd("scratchpad/tt/README_r10_draft.md").split("**Tools**")[1].split("TODO_BODY")[0]
    parts = [head.rstrip() + "\n", result + "\n", tools.rstrip() + "\n"]
    for i in (1, 2, 3, 4, 5):
        parts.append(rd(f"scratchpad/tt/README_r10_body{i}.md"))
    text = "\n".join(parts).replace("TODO_ARENA", arena)
    assert "TODO" not in text, [l for l in text.splitlines() if "TODO" in l][:3]
    if "--dry" in sys.argv:
        open(os.path.join(ROOT, "scratchpad/tt/README_r10_final.md"), "w").write(text)
        print("dry run: wrote scratchpad/tt/README_r10_final.md,", len(text.splitlines()), "lines")
        return
    p = os.path.join(ROOT, "README.md")
    s = open(p).read()
    assert s.count(ANCHOR) == 1
    if H in s:
        # replace the section written by an earlier run of this script
        i = s.index(H)
        j = s.index(ANCHOR)
        assert i < j
        s = s[:i] + text.rstrip() + "\n\n" + s[j:]
        print("replaced the earlier section with", len(text.splitlines()), "lines")
    else:
        s = s.replace(ANCHOR, text.rstrip() + "\n\n" + ANCHOR, 1)
        print("inserted", len(text.splitlines()), "lines before the Relocate section")
    open(p, "w").write(s)


main()
