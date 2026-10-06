"""Params with stage K = a copy of stage S's table (the stage-2 table for the right hand's second stroke), plus overrides.
    scratchpad/btl5/py scratchpad/btl5/mkcopy.py base.txt out.txt K S [key=value ...]"""
import sys
sys.path.insert(0, "scratchpad/btl5")
import fit3 as F

base, out, K, S = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
extra = {k: float(v) for k, v in (kv.split("=") for kv in sys.argv[5:])}
B, nom, sc = F.parse_stage(base, S, 3)
F.write_stage(base, out, K, B, nom, sc, f"{base} + stage {K} = a copy of stage {S}", extra=extra)
print("wrote", out)
