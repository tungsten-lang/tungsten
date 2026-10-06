"""Write a deployable params file from a chain-fit checkpoint (fitchain.py npz with the absolute table): G (or --base) + the stage's table, nominal, spread, clock and lead.
    scratchpad/btl6/py scratchpad/btl6/make_params.py ckpt.npz out.txt [base_params] [extra key=value ...]"""
import sys
sys.path.insert(0, "scratchpad/btl6")
import numpy as np
import tabio
z = np.load(sys.argv[1])
base = sys.argv[3] if len(sys.argv) > 3 and "=" not in sys.argv[3] else "scratchpad/btl5/params/final_g.txt"
extra = dict((kv.split("=")[0], float(kv.split("=")[1])) for kv in sys.argv[3:] if "=" in kv)
st = int(z["stage"])
extra.update({f"pg_acd{st}": float(z["acd"]), f"pg_lead{st}": float(z["lead"])})
if bool(z["energy"]):
    extra.update({"pg_vn": 1.0, f"pgvk{st}": float(z["vk"]), f"pgvs{st}": float(z["vs"])})
    if "vsel" in z.files and int(z["vsel"]):
        extra[f"pg_vsel{st}"] = 1.0
    if "kap" in z.files and abs(float(z["kap"])) > 0:
        extra[f"pg_vts{st}"] = float(z["kap"])
tabio.write_table(base, sys.argv[2], st, z["B"], f"chain fit {sys.argv[1]} stage {st} (gen {int(z['gen'])}, train V {float(z['train_V']):.4f}, validation V {float(z['val_V']):.4f})", z["nom"], z["sc"], extra)
print("wrote", sys.argv[2], "stage", st, "acd", float(z["acd"]), "lead", float(z["lead"]))
