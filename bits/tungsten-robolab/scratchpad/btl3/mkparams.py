"""mkparams.py base.txt out.txt k=v,k=v [note]  -- copy a params file with overrides applied (keys added when absent)."""
import sys
sys.path.insert(0, "scratchpad/btl2")
from common import load, parse_over, write_params
base, out, ov = sys.argv[1], sys.argv[2], sys.argv[3]
note = sys.argv[4] if len(sys.argv) > 4 else f"{base} + {ov}"
p = load(base)
p.update(parse_over(ov))
write_params(out, p, note)
print("wrote", out, len(p), "keys")
