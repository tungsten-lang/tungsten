#!/usr/bin/env python3
# Bridge ollama's per-tensor MLX blobs -> an HF sharded-safetensors layout
# (model.safetensors.index.json + symlinked shards) that verify_qwen36.w's
# ShardedSafetensors can read. Also reports coverage vs the harness's names.
import json, os, struct, glob, sys, re

HOME = os.path.expanduser("~")
BLOBS = f"{HOME}/.ollama/models/blobs"
STAGE = f"{HOME}/.cache/tungsten/qwen36-mlx"          # ephemeral, regenerable
HARNESS = "/Users/erik/tungsten/scripts/bench/verify_qwen36.w"

def find_manifest():
    for p in glob.glob(f"{HOME}/.ollama/models/manifests/**/*", recursive=True):
        if os.path.isfile(p) and "qwen3.6" in p and ("mlx" in p or "35b" in p):
            try:
                d = json.load(open(p))
                if any("tensor" in l.get("mediaType","") for l in d.get("layers",[])):
                    return p
            except Exception: pass
    return None

def blob_path(digest): return f"{BLOBS}/sha256-{digest.split(':')[1]}"

def read_st_header(path):
    with open(path, "rb") as f:
        n = struct.unpack("<Q", f.read(8))[0]
        return json.loads(f.read(n))

mf = find_manifest()
print("manifest:", mf)
man = json.load(open(mf))
layers = [l for l in man["layers"] if "name" in l and "tensor" in l.get("mediaType","")]
print(f"tensor blobs: {len(layers)}")

os.makedirs(STAGE, exist_ok=True)
# clear old symlinks/index
for f in glob.glob(f"{STAGE}/*.safetensors") + glob.glob(f"{STAGE}/*.json"):
    os.remove(f)

weight_map = {}
n_internal = 0
for l in layers:
    bp = blob_path(l["digest"])
    if not os.path.exists(bp): continue
    shard = f"blob-{l['digest'].split(':')[1][:16]}.safetensors"
    link = f"{STAGE}/{shard}"
    if not os.path.lexists(link): os.symlink(bp, link)
    try:
        hdr = read_st_header(bp)
    except Exception as e:
        print("  header fail", l["name"], e); continue
    for tname in hdr:
        if tname == "__metadata__": continue
        weight_map[tname] = shard
        n_internal += 1

print(f"internal tensors mapped: {n_internal}")
index = {"metadata": {"total_size": sum(l["size"] for l in layers)}, "weight_map": weight_map}
json.dump(index, open(f"{STAGE}/model.safetensors.index.json","w"))
print("wrote", f"{STAGE}/model.safetensors.index.json")

# ---- coverage vs harness ----
src = open(HARNESS).read()
# concrete quoted tensor names + prefix+suffix constructions
quoted = set(re.findall(r'"(language_model[^"]*)"', src))
concrete = {q for q in quoted if not q.endswith(".") and "layers." not in q or re.search(r'layers\.\d', q)}
avail = set(weight_map)
print("\n=== sample availability ===")
for probe in ["language_model.model.embed_tokens.weight",
              "language_model.model.embed_tokens.scales",
              "language_model.model.embed_tokens.weight.scale",
              "language_model.lm_head.weight", "language_model.lm_head.scales",
              "language_model.model.norm.weight",
              "language_model.model.layers.0.mlp.switch_mlp.down_proj.weight",
              "language_model.model.layers.0.mlp.switch_mlp.down_proj.weight.scale",
              "language_model.model.layers.0.mlp.switch_mlp.down_proj.scales"]:
    print(f"  {'OK ' if probe in avail else 'MISS'} {probe}")
scales_names = sorted(n for n in avail if n.endswith(".scales"))
wscale_names = sorted(n for n in avail if n.endswith(".weight.scale"))
print(f"\navailable '.scales': {len(scales_names)}  |  '.weight.scale': {len(wscale_names)}")
print("layer0 available:", sorted(n[len('language_model.model.layers.0.'):] for n in avail if n.startswith('language_model.model.layers.0.'))[:20])
