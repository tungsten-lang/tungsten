"""insert_readme.py: (re)insert scratchpad/hazard/README_round11.md into README.md right before '### Locomotion on the myoLeg (chase-tag)' (after the Soccer round 9 section); idempotent."""
import re
H = "/Users/erik/tungsten/bits/tungsten-robolab/"
readme = open(H + "README.md").read()
sec = open(H + "scratchpad/hazard/README_round11.md").read().rstrip() + "\n\n"
title = "#### Soccer round 11: a hold that avoids the wrap tangent"
anchor = "### Locomotion on the myoLeg (chase-tag)"
if title in readme:                       # replace the earlier insertion
    i = readme.index(title)
    j = readme.index(anchor, i)
    readme = readme[:i] + sec + readme[j:]
else:
    assert anchor in readme
    i = readme.index(anchor)
    readme = readme[:i] + sec + readme[i:]
open(H + "README.md", "w").write(readme)
print("README.md updated:", readme.count("Soccer round 11"), "mentions;", len(sec.splitlines()), "lines inserted")
