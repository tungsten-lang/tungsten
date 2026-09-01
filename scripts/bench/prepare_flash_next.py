#!/usr/bin/env python3
"""Prepare RadixArk/Qwen3.8-Flash-Next-NVFP4 for the Tungsten engine.

Mirrors prepare_ollama_mlx.rb's philosophy: no weight copying. Symlinks the
HF-cache snapshot into ~/.cache/tungsten/qwen38-flash-next-nvfp4/ and writes:

  index.slim.json       HF-style index holding ONLY non-expert tensors
                        (the real index has ~296K entries; ShardedSafetensors
                        would choke parsing 30MB of JSON it never looks at)
  experts_manifest.json per (layer, quarter): file + absolute byte offsets and
                        verified-uniform strides for the packed weights, the
                        fp8 group scales, and the per-expert f32 scalars
                        region, so the runner binds 4 mmap views per layer and
                        indexes experts arithmetically
  ple_manifest.json     n-gram table shard offsets + hashing constants
                        (head offsets, per-head vocab sizes, layer
                        multipliers) inlined as plain ints

Run after the `hf download` completes:
  python3 scripts/bench/prepare_flash_next.py
"""

import json
import os
import struct
import sys

REPO = "models--RadixArk--Qwen3.8-Flash-Next-NVFP4"
OUT_DIR = os.path.expanduser("~/.cache/tungsten/qwen38-flash-next-nvfp4")
N_LAYERS = 48
N_QUARTERS = 4
EXPERTS_PER_QUARTER = 128


def snapshot_dir():
    base = os.path.expanduser(f"~/.cache/huggingface/hub/{REPO}/snapshots")
    snaps = sorted(os.listdir(base))
    if not snaps:
        sys.exit("no snapshot found; run the hf download first")
    return os.path.join(base, snaps[-1])


def read_header(path):
    with open(path, "rb") as fh:
        n = struct.unpack("<Q", fh.read(8))[0]
        hdr = json.loads(fh.read(n))
    return hdr, 8 + n


def read_i64_tensor(path, info, data_start):
    off, end = info["data_offsets"]
    with open(path, "rb") as fh:
        fh.seek(data_start + off)
        raw = fh.read(end - off)
    return list(struct.unpack(f"<{len(raw) // 8}q", raw))


def e4m3_to_float(b):
    sign = -1.0 if b & 0x80 else 1.0
    exp = (b >> 3) & 0xF
    man = b & 7
    if exp == 0:
        return sign * (man / 8.0) * 2.0 ** (-6)
    if exp == 15 and man == 7:
        return float("nan")
    return sign * (1.0 + man / 8.0) * 2.0 ** (exp - 7)


def main():
    snap = snapshot_dir()
    os.makedirs(OUT_DIR, exist_ok=True)

    linked = 0
    for name in sorted(os.listdir(snap)):
        if not (name.endswith(".safetensors") or name.endswith(".json")
                or name.endswith(".jinja") or name.endswith(".txt")):
            continue
        dst = os.path.join(OUT_DIR, name)
        if os.path.islink(dst):
            os.remove(dst)
        elif os.path.exists(dst):
            continue    # an already-materialized (alignment-fixed) copy wins
        os.symlink(os.path.realpath(os.path.join(snap, name)), dst)
        linked += 1
    print(f"symlinked {linked} files into {OUT_DIR}")

    # ---- header-alignment fix ----
    # RadixArk wrote some shards without padding the JSON header, leaving the
    # data section at an odd byte offset; a bf16 tensor bound at an odd offset
    # gives undefined GPU ushort loads (bit us as NaNs from layer 0). Pad the
    # header with spaces (spec-legal) so data starts 8-aligned, materializing
    # a fixed copy in OUT_DIR in place of the symlink.
    for name in sorted(os.listdir(OUT_DIR)):
        if not name.endswith(".safetensors"):
            continue
        dst = os.path.join(OUT_DIR, name)
        with open(dst, "rb") as fh:
            n = struct.unpack("<Q", fh.read(8))[0]
        if (8 + n) % 8 == 0:
            continue
        pad = 8 - (8 + n) % 8
        src = os.path.realpath(dst)
        print(f"  aligning {name}: header {n} -> +{pad} pad "
              f"({os.path.getsize(src) / 1e9:.2f} GB rewrite)")
        tmp = dst + ".aligned"
        with open(src, "rb") as fin, open(tmp, "wb") as fout:
            fin.seek(8)
            hdr = fin.read(n)
            fout.write(struct.pack("<Q", n + pad))
            fout.write(hdr + b" " * pad)
            while True:
                chunk = fin.read(1 << 24)
                if not chunk:
                    break
                fout.write(chunk)
        os.remove(dst)
        os.rename(tmp, dst)

    # ---- slim index: everything except routed-expert tensors ----
    idx_path = os.path.join(snap, "model.safetensors.index.json")
    if not os.path.exists(idx_path):
        # hf download fetches large files first; fall back to a pre-fetched copy
        for alt in sys.argv[1:]:
            if os.path.exists(alt):
                idx_path = alt
                break
        else:
            sys.exit("model.safetensors.index.json not downloaded yet "
                     "(pass a fallback path as argv[1])")
    full = json.load(open(idx_path))
    slim = {k: v for k, v in full["weight_map"].items()
            if ".mlp.experts." not in k or k.startswith("mtp.")}
    with open(os.path.join(OUT_DIR, "index.slim.json"), "w") as fh:
        json.dump({"metadata": full.get("metadata", {}), "weight_map": slim}, fh)
    print(f"index.slim.json: {len(slim)} tensors (of {len(full['weight_map'])})")

    # ---- experts manifest ----
    mats = ["gate_proj", "up_proj", "down_proj"]
    manifest = {"n_layers": N_LAYERS, "n_quarters": N_QUARTERS,
                "experts_per_quarter": EXPERTS_PER_QUARTER, "files": []}
    strides = None
    missing = 0
    for layer in range(N_LAYERS):
        for q in range(N_QUARTERS):
            lo, hi = q * 128, q * 128 + 127
            fname = f"layer-{layer:05d}-experts-{lo:04d}-{hi:04d}.safetensors"
            path = os.path.join(OUT_DIR, fname)
            if not os.path.exists(path):
                missing += 1
                continue
            hdr, data_start = read_header(path)
            pfx = f"model.language_model.layers.{layer}.mlp.experts."

            def offs(e, suffix):
                return hdr[f"{pfx}{lo + e}.{suffix}"]["data_offsets"][0]

            # Expert regions are laid out in STRING-sorted global-id order
            # ("0","1","10","100",...), so files whose id range mixes digit
            # counts (only quarter 0) carry a non-identity expert->slot map.
            order = sorted(range(EXPERTS_PER_QUARTER), key=lambda e: str(lo + e))
            slot = [0] * EXPERTS_PER_QUARTER
            for rank, e in enumerate(order):
                slot[e] = rank
            entry = {"layer": layer, "quarter": q, "file": fname,
                     "data_start": data_start,
                     "file_size": os.path.getsize(os.path.realpath(path)),
                     "slot_map": slot}
            this = {}
            for m in mats:
                w0 = min(offs(e, f"{m}.weight") for e in range(EXPERTS_PER_QUARTER))
                s0 = min(offs(e, f"{m}.weight_scale") for e in range(EXPERTS_PER_QUARTER))
                g0 = min(offs(e, f"{m}.weight_scale_2") for e in range(EXPERTS_PER_QUARTER))
                ws = offs(order[1], f"{m}.weight") - w0
                ss = offs(order[1], f"{m}.weight_scale") - s0
                gs = offs(order[1], f"{m}.weight_scale_2") - g0
                for e in range(EXPERTS_PER_QUARTER):
                    r = slot[e]
                    assert offs(e, f"{m}.weight") == w0 + r * ws, (fname, m, e)
                    assert offs(e, f"{m}.weight_scale") == s0 + r * ss, (fname, m, e)
                    assert offs(e, f"{m}.weight_scale_2") == g0 + r * gs, (fname, m, e)
                entry[m] = {"w0": w0, "w_stride": ws, "s0": s0,
                            "s_stride": ss, "g0": g0, "g_stride": gs}
                this[m] = (ws, ss, gs,
                           hdr[f"{pfx}{lo}.{m}.weight"]["shape"],
                           hdr[f"{pfx}{lo}.{m}.weight_scale"]["shape"])
            if strides is None:
                strides = this
                print("expert layout:", json.dumps(this))
            elif strides != this:
                sys.exit(f"non-uniform expert layout in {fname}: {this}")
            manifest["files"].append(entry)
    with open(os.path.join(OUT_DIR, "experts_manifest.json"), "w") as fh:
        json.dump(manifest, fh)
    print(f"experts_manifest.json: {len(manifest['files'])} shard entries"
          + (f" ({missing} MISSING - download incomplete)" if missing else ""))

    # ---- PLE manifest ----
    # ple_layer_ids in config.json is ONE-indexed; discover the actual prefix.
    ple = {"shards": []}
    pfx = None
    for k in full["weight_map"]:
        if ".ple.ple_embedding." in k:
            pfx = k.split("ple_embedding.")[0] + "ple_embedding."
            break
    if pfx is None:
        sys.exit("no ple_embedding tensors found in index")
    print(f"ple prefix: {pfx}")
    by_file = {}
    for k, f in full["weight_map"].items():
        if k.startswith(pfx):
            by_file.setdefault(f, []).append(k)
    for f in sorted(by_file):
        path = os.path.join(OUT_DIR, f)
        if not os.path.exists(path):
            print(f"  ple shard file {f} missing; rerun after download")
            continue
        hdr, data_start = read_header(path)
        for k in by_file[f]:
            if k not in hdr:
                continue
            info = hdr[k]
            if k.endswith("layer_multipliers"):
                ple["layer_multipliers"] = read_i64_tensor(path, info, data_start)
            elif k.endswith("ngram_heads_offsets"):
                ple["ngram_heads_offsets"] = read_i64_tensor(path, info, data_start)
            elif k.endswith("ngram_heads_vocab_sizes"):
                ple["ngram_heads_vocab_sizes"] = read_i64_tensor(path, info, data_start)
            elif k.endswith(".weight_scale"):
                off = info["data_offsets"]
                with open(path, "rb") as fh:
                    fh.seek(data_start + off[0])
                    raw = fh.read(off[1] - off[0])
                ple["weight_scale_shape"] = info["shape"]
                ple["weight_scale_dtype"] = info["dtype"]
                if info["dtype"] == "F8_E4M3" and len(raw) <= 256:
                    ple["weight_scale"] = [e4m3_to_float(b) for b in raw]
                elif info["dtype"] == "BF16" and len(raw) <= 512:
                    ple["weight_scale"] = [
                        struct.unpack("<f", bytes([0, 0, raw[i], raw[i + 1]]))[0]
                        for i in range(0, len(raw), 2)]
                elif info["dtype"] == "F32" and len(raw) <= 1024:
                    ple["weight_scale"] = list(struct.unpack(f"<{len(raw) // 4}f", raw))
                else:
                    ple["weight_scale"] = f"{len(raw)} bytes {info['dtype']}; not inlined"
            elif ".ngram_embedding.shard_" in k:
                s = int(k.split(".shard_")[1].split(".")[0])
                ple["shards"].append({"shard": s, "file": f,
                                      "offset": data_start + info["data_offsets"][0],
                                      "shape": info["shape"],
                                      "dtype": info["dtype"]})
    # bf16 tensors for offsets/multipliers live in bf16 shards, not ple files
    for f in ("model-bf16-00001.safetensors", "model-bf16-00010.safetensors"):
        path = os.path.join(OUT_DIR, f)
        if not os.path.exists(path):
            continue
        hdr, data_start = read_header(path)
        for k, info in hdr.items():
            if k == "__metadata__" or not k.startswith(pfx):
                continue
            if k.endswith("layer_multipliers"):
                ple["layer_multipliers"] = read_i64_tensor(path, info, data_start)
            elif k.endswith("ngram_heads_offsets"):
                ple["ngram_heads_offsets"] = read_i64_tensor(path, info, data_start)
            elif k.endswith("ngram_heads_vocab_sizes"):
                ple["ngram_heads_vocab_sizes"] = read_i64_tensor(path, info, data_start)
    ple["shards"].sort(key=lambda s: s["shard"])
    with open(os.path.join(OUT_DIR, "ple_manifest.json"), "w") as fh:
        json.dump(ple, fh, indent=1)
    print(f"ple_manifest.json: {len(ple['shards'])} table shards; "
          f"multipliers={ple.get('layer_multipliers')} "
          f"offsets[0:4]={ple.get('ngram_heads_offsets', [])[:4]} "
          f"vocab[0:4]={ple.get('ngram_heads_vocab_sizes', [])[:4]}")


if __name__ == "__main__":
    main()
