#!/usr/bin/env python3
"""Weight-only NVFP4 self-quantization of Qwen3.8-Flash-Next's bf16 matvec
stack (GDN in/out, attention q/k/v/o, HC mixers, shared experts, lm_head —
~8.3 GB/token of decode stream -> ~2.3 GB).

Follows the ModelOpt NVFP4 recipe the routed experts already use, emitted in
the MLX naming convention the engine's nvfp4 kernels consume
(<name> packed u8 / <name>.scale fp8-e4m3 / <name>.global_scale f32):

  scale_2      = amax(W) / (448 * 6)
  block_scale  = e4m3( amax(block16) / (6 * scale_2) )
  code         = round_to_e2m1( w / (block_scale * scale_2) )

Community quality data (see model README): experts-only 4-bit is eval-parity;
the attention/GDN stack tolerates 4-bit except the OUTERMOST layers — so
layers 0, 1, 46, 47 are SKIPPED (stay bf16) by default.

  python3 scripts/bench/quantize_flash_next.py          # writes selfquant.safetensors
"""

import json
import os
import struct

import numpy as np

from flash_next_ckpt import CACHE, Checkpoint

OUT = os.path.join(CACHE, "selfquant.safetensors")
SKIP_LAYERS = {0, 1, 46, 47}

E2M1_VALUES = np.array([0.0, 0.5, 1.0, 1.5, 2.0, 3.0, 4.0, 6.0], dtype=np.float32)


def f32_to_e4m3(x):
    """Round positive f32 scales to the nearest E4M3 code (no sign, sat 448)."""
    x = np.clip(x, 0.0, 448.0)
    codes = np.zeros(x.shape, dtype=np.uint8)
    # build the 127-entry positive e4m3 value table once
    vals = np.zeros(128, dtype=np.float32)
    for b in range(128):
        e = (b >> 3) & 0xF
        m = b & 7
        vals[b] = (m / 8.0) * 2.0 ** (-6) if e == 0 else (1.0 + m / 8.0) * 2.0 ** (e - 7)
    vals[127] = np.inf   # nan code; never chosen after clip
    idx = np.searchsorted(vals, x)
    idx = np.clip(idx, 1, 126)
    lo, hi = vals[idx - 1], vals[idx]
    codes = np.where(np.abs(x - lo) <= np.abs(hi - x), idx - 1, idx).astype(np.uint8)
    return codes, vals[codes]


def quantize_tensor(w):
    """[rows, k] f32 -> (packed u8 [rows, k/2], scales u8 [rows, k/16], scale2 f32)."""
    rows, k = w.shape
    amax = np.abs(w).max()
    scale2 = np.float32(amax / (448.0 * 6.0)) if amax > 0 else np.float32(1.0)
    blocks = np.abs(w).reshape(rows, k // 16, 16).max(axis=2)
    scodes, svals = f32_to_e4m3(blocks / (6.0 * scale2))
    denom = np.where(svals > 0, svals * scale2, 1.0)
    scaled = w.reshape(rows, k // 16, 16) / denom[:, :, None]
    # nearest E2M1: quantize |x| against the 8 magnitudes, keep sign
    mag = np.abs(scaled).reshape(rows, k)
    idx = np.searchsorted(E2M1_VALUES, mag)
    idx = np.clip(idx, 1, 7)
    lo, hi = E2M1_VALUES[idx - 1], E2M1_VALUES[idx]
    codes = np.where(np.abs(mag - lo) <= np.abs(hi - mag), idx - 1, idx).astype(np.uint8)
    codes = np.where(np.signbit(scaled.reshape(rows, k)), codes | 8, codes)
    packed = (codes[:, 0::2] | (codes[:, 1::2] << 4)).astype(np.uint8)
    return packed, scodes, scale2


def target_tensors():
    L = "model.language_model.layers."
    names = ["lm_head.weight"]
    for li in range(48):
        if li in SKIP_LAYERS:
            continue
        p = f"{L}{li}."
        if (li + 1) % 4 == 0:
            for t in ("q_proj", "k_proj", "v_proj", "o_proj"):
                names.append(p + f"self_attn.{t}.weight")
        else:
            for t in ("in_proj_qkv", "in_proj_z", "out_proj"):
                names.append(p + f"linear_attn.{t}.weight")
        for hc in ("attn_hyper_connection", "mlp_hyper_connection"):
            for t in ("input_mix_weight_down", "input_mix_weight_up"):
                names.append(p + f"{hc}.{t}.weight")
        for t in ("gate_proj", "up_proj", "down_proj"):
            names.append(p + f"mlp.shared_expert.{t}.weight")
    return names


def main():
    ck = Checkpoint()
    tensors = {}   # name -> (dtype, shape, bytes)
    total_in = total_out = 0
    for i, name in enumerate(target_tensors()):
        w = ck.get(name)
        packed, scodes, scale2 = quantize_tensor(w)
        tensors[name] = ("U8", list(packed.shape), packed.tobytes())
        tensors[name + ".scale"] = ("F8_E4M3", list(scodes.shape), scodes.tobytes())
        tensors[name + ".global_scale"] = ("F32", [], struct.pack("<f", scale2))
        total_in += w.nbytes // 2
        total_out += packed.nbytes + scodes.nbytes + 4
        if i % 50 == 0:
            print(f"  {i}: {name} {w.shape}")
    print(f"quantized {len(tensors) // 3} tensors: {total_in / 1e9:.2f} GB bf16 "
          f"-> {total_out / 1e9:.2f} GB nvfp4")

    # write a single safetensors file, header padded to 8 bytes
    header = {}
    off = 0
    for name, (dt, shape, data) in tensors.items():
        header[name] = {"dtype": dt, "shape": shape,
                        "data_offsets": [off, off + len(data)]}
        off += len(data)
    hjson = json.dumps(header).encode()
    pad = (8 - (8 + len(hjson)) % 8) % 8
    with open(OUT, "wb") as fh:
        fh.write(struct.pack("<Q", len(hjson) + pad))
        fh.write(hjson + b" " * pad)
        for _, (_, _, data) in tensors.items():
            fh.write(data)
    print(f"wrote {OUT} ({os.path.getsize(OUT) / 1e9:.2f} GB)")


if __name__ == "__main__":
    main()
