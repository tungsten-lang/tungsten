#!/usr/bin/env python3
"""Numpy reference for Qwen3.8-Flash-Next (qwen4_exp), text-only, greedy.

Implements the forward pass exactly per the reference implementations
(HF transformers qwen4_exp + vLLM qwen4_exp), reading the RadixArk NVFP4
checkpoint directly. Serves as the golden generator for the Tungsten engine:

  python3 scripts/bench/flash_next_ref.py                # parity fixture, 8 tokens
  python3 scripts/bench/flash_next_ref.py --tokens 16 --dump /tmp/fn_golden

Constraints: single sequence, dense attention (asserts pos < 2051 so QSA
top-k selection is provably the identity), no MTP, no vision.
"""

import argparse
import json
import mmap
import os
import time

import numpy as np

from flash_next_ckpt import CACHE, Checkpoint, Experts, E4M3

# ---- config (mirrors lib/models/qwen38_flash_next_nvfp4/config.w) ----
HIDDEN = 2560
N_LAYERS = 48
HC = 4
HC_HIDDEN = HC * HIDDEN          # 10240
HC_LOWRANK = 320
N_HEADS = 24
N_KV = 2
HEAD_DIM = 256
ROT_DIM = 64
ROPE_THETA = 1e7
HK, HV, DK, DV = 16, 48, 128, 128
CONV_K = 4
N_EXPERTS, TOP_K, MOE_FFN = 512, 10, 640
EPS = 1e-6
EOS = 248044
PLE_LAYER = 1                    # 0-based (config ple_layer_ids [2] is 1-indexed)
PLE_CONV_K, PLE_DIL = 4, 3
PLE_STATE = (PLE_CONV_K - 1) * PLE_DIL   # 9
NGRAM_SIZE = 3


def rms_norm(x, w, eps=EPS):
    """(1+w) RMSNorm over the last axis, fp32."""
    v = np.mean(np.square(x), axis=-1, keepdims=True)
    return x * (1.0 / np.sqrt(v + eps)) * (1.0 + w)


def grouped_rms_norm(x10240, w10240):
    """Per-2560-group RMSNorm with a (1+w) affine over the full 10240."""
    g = x10240.reshape(HC, HIDDEN)
    v = np.mean(np.square(g), axis=-1, keepdims=True)
    n = (g * (1.0 / np.sqrt(v + EPS))).reshape(HC_HIDDEN)
    return n * (1.0 + w10240)


def silu(x):
    return x / (1.0 + np.exp(-x))


def sigmoid(x):
    return 1.0 / (1.0 + np.exp(-x))


def softplus(x):
    return np.log1p(np.exp(-np.abs(x))) + np.maximum(x, 0.0)


def l2norm(x, eps=1e-6):
    return x * (1.0 / np.sqrt(np.sum(np.square(x), axis=-1, keepdims=True) + eps))


class HyperConn:
    def __init__(self, ck, prefix):
        self.norm = ck.get(prefix + "hc_norm.weight")
        self.down = ck.get(prefix + "input_mix_weight_down.weight")   # [320,10240]
        self.up = ck.get(prefix + "input_mix_weight_up.weight")       # [10240,320]
        try:
            self.inject = ck.get(prefix + "block_inject_weight.weight")  # [4,10240]
        except KeyError:
            self.inject = None

    def mix(self, H):
        n = grouped_rms_norm(H, self.norm)
        g = silu((self.down @ n) / HC)
        G = sigmoid(self.up @ g)
        x = np.mean((G * n).reshape(HC, HIDDEN), axis=0)
        return x, n

    def combine(self, H, n, y):
        w_inj = 2.0 * sigmoid((self.inject @ n) / HC)                 # [4]
        return H + (y[None, :] * w_inj[:, None]).reshape(HC_HIDDEN)


class GDNLayer:
    def __init__(self, ck, pfx):
        self.w_qkv = ck.get(pfx + "in_proj_qkv.weight")
        self.w_z = ck.get(pfx + "in_proj_z.weight")
        self.w_a = ck.get(pfx + "in_proj_a.weight")
        self.w_b = ck.get(pfx + "in_proj_b.weight")
        self.conv = ck.get(pfx + "conv1d.weight").reshape(HC_HIDDEN, CONV_K)
        self.a_log = ck.get(pfx + "A_log")
        self.dt_bias = ck.get(pfx + "dt_bias")
        self.norm = ck.get(pfx + "norm.weight")       # plain w, NOT (1+w)
        self.w_out = ck.get(pfx + "out_proj.weight")
        self.conv_state = np.zeros((HC_HIDDEN, CONV_K - 1), dtype=np.float32)
        self.S = np.zeros((HV, DK, DV), dtype=np.float32)

    def forward(self, x):
        qkv = self.w_qkv @ x
        z = self.w_z @ x
        a = self.w_a @ x
        b = self.w_b @ x
        # depthwise causal conv (kernel 4) + silu, on packed qkv
        window = np.concatenate([self.conv_state, qkv[:, None]], axis=1)  # [10240,4]
        self.conv_state = window[:, 1:]
        qkv = silu(np.sum(window * self.conv, axis=1))
        q = qkv[:2048].reshape(HK, DK)
        k = qkv[2048:4096].reshape(HK, DK)
        v = qkv[4096:].reshape(HV, DV)
        beta = sigmoid(b)                                             # [48]
        g = -np.exp(self.a_log) * softplus(a + self.dt_bias)          # [48]
        # GVA: k-head i serves v-heads 3i..3i+2 (repeat_interleave)
        q = np.repeat(q, 3, axis=0)                                   # [48,128]
        k = np.repeat(k, 3, axis=0)
        q = l2norm(q) / np.sqrt(DK)
        k = l2norm(k)
        self.S *= np.exp(g)[:, None, None]
        kv_mem = np.einsum('hk,hkv->hv', k, self.S)
        delta = (v - kv_mem) * beta[:, None]
        self.S += k[:, :, None] * delta[:, None, :]
        o = np.einsum('hk,hkv->hv', q, self.S)                        # [48,128]
        # gated RMSNorm (plain weight) x sigmoid(z)
        o = o * (1.0 / np.sqrt(np.mean(np.square(o), axis=-1, keepdims=True) + EPS))
        o = (self.norm * o) * sigmoid(z.reshape(HV, DV))
        return self.w_out @ o.reshape(HV * DV)


class AttnLayer:
    def __init__(self, ck, pfx):
        self.w_q = ck.get(pfx + "q_proj.weight")      # [12288,2560]
        self.w_k = ck.get(pfx + "k_proj.weight")
        self.w_v = ck.get(pfx + "v_proj.weight")
        self.w_o = ck.get(pfx + "o_proj.weight")
        self.q_norm = ck.get(pfx + "q_norm.weight")
        self.k_norm = ck.get(pfx + "k_norm.weight")
        self.k_cache = []
        self.v_cache = []
        inv = ROPE_THETA ** (-np.arange(0, ROT_DIM, 2, dtype=np.float32) / ROT_DIM)
        self.inv_freq = inv                                            # [32]

    def rope(self, x, pos):
        """Neox-half partial rope on the first ROT_DIM of each head row."""
        ang = pos * self.inv_freq                                      # [32]
        cos = np.cos(ang).astype(np.float32)
        sin = np.sin(ang).astype(np.float32)
        r = x[:, :ROT_DIM].copy()
        x1, x2 = r[:, :32], r[:, 32:]
        x[:, :32] = x1 * cos - x2 * sin
        x[:, 32:ROT_DIM] = x2 * cos + x1 * sin
        return x

    def forward(self, x, pos):
        assert pos < 2051, "QSA selection no longer dense; implement the indexer"
        qg = (self.w_q @ x).reshape(N_HEADS, 2 * HEAD_DIM)
        q = qg[:, :HEAD_DIM].copy()
        gate = qg[:, HEAD_DIM:].reshape(N_HEADS * HEAD_DIM)
        k = (self.w_k @ x).reshape(N_KV, HEAD_DIM)
        v = (self.w_v @ x).reshape(N_KV, HEAD_DIM)
        q = rms_norm(q, self.q_norm)
        k = rms_norm(k, self.k_norm)
        q = self.rope(q, pos)
        k = self.rope(k, pos)
        self.k_cache.append(k)
        self.v_cache.append(v)
        K = np.stack(self.k_cache)                                     # [T,2,256]
        V = np.stack(self.v_cache)
        out = np.empty((N_HEADS, HEAD_DIM), dtype=np.float32)
        scale = 1.0 / np.sqrt(HEAD_DIM)
        for h in range(N_HEADS):
            kv = h // (N_HEADS // N_KV)
            s = (K[:, kv] @ q[h]) * scale
            s = np.exp(s - np.max(s))
            s /= np.sum(s)
            out[h] = s @ V[:, kv]
        out = out.reshape(N_HEADS * HEAD_DIM) * sigmoid(gate)
        return self.w_o @ out


class MoE:
    def __init__(self, ck, ex, layer, pfx):
        self.ex = ex
        self.layer = layer
        self.w_router = ck.get(pfx + "gate.weight")                    # [512,2560]
        self.w_sg = ck.get(pfx + "shared_expert.gate_proj.weight")
        self.w_su = ck.get(pfx + "shared_expert.up_proj.weight")
        self.w_sd = ck.get(pfx + "shared_expert.down_proj.weight")
        self.w_seg = ck.get(pfx + "shared_expert_gate.weight").reshape(HIDDEN)

    def forward(self, x):
        logits = self.w_router @ x
        p = np.exp(logits - np.max(logits))
        p /= np.sum(p)
        idx = np.argsort(-p)[:TOP_K]
        w = p[idx] / np.sum(p[idx])
        routed = np.zeros(HIDDEN, dtype=np.float32)
        for wi, e in zip(w, idx):
            g = self.ex.weight(self.layer, int(e), "gate_proj") @ x
            u = self.ex.weight(self.layer, int(e), "up_proj") @ x
            routed += wi * (self.ex.weight(self.layer, int(e), "down_proj") @ (silu(g) * u))
        shared = self.w_sd @ (silu(self.w_sg @ x) * (self.w_su @ x))
        return routed + sigmoid(self.w_seg @ x) * shared


class PLE:
    def __init__(self, ck, pfx):
        man = json.load(open(os.path.join(CACHE, "ple_manifest.json")))
        self.mult = man["layer_multipliers"]
        self.sizes = np.array(man["ngram_heads_vocab_sizes"], dtype=np.int64)
        self.offsets = np.array(man["ngram_heads_offsets"], dtype=np.int64)
        ws = man["weight_scale"]
        self.scale = np.float32(ws[0] if isinstance(ws, list) else 1.0)
        self.shards = man["shards"]
        self.shard_rows = self.shards[0]["shape"][0]
        self.head_dim = self.shards[0]["shape"][1]
        self._mmaps = {}
        self.w_key = ck.get(pfx + "key_proj.weight")                   # [10240,2560]
        self.w_val = ck.get(pfx + "value_proj.weight")                 # [2560,2560]
        self.n_key = ck.get(pfx + "norm_key.weight")
        self.n_query = ck.get(pfx + "norm_query.weight")
        self.n_conv = ck.get(pfx + "norm_conv.weight")
        self.conv = ck.get(pfx + "conv1d.weight").reshape(HC_HIDDEN, PLE_CONV_K)
        self.conv_state = np.zeros((HC_HIDDEN, PLE_STATE), dtype=np.float32)
        self.ctx = [EOS, EOS]      # previous 2 token ids (eos-seeded)

    def _row(self, rid):
        s, r = divmod(int(rid), self.shard_rows)
        sh = self.shards[s]
        if s not in self._mmaps:
            fh = open(os.path.join(CACHE, sh["file"]), "rb")
            self._mmaps[s] = mmap.mmap(fh.fileno(), 0, access=mmap.ACCESS_READ)
        raw = np.frombuffer(self._mmaps[s], dtype=np.uint8, count=self.head_dim,
                            offset=sh["offset"] + r * self.head_dim)
        return E4M3[raw] * self.scale

    def embed(self, tok):
        t0 = np.int64(tok)
        t1, t2 = np.int64(self.ctx[-1]), np.int64(self.ctx[-2])
        out = np.empty(HIDDEN, dtype=np.float32)
        for order in (2, 3):
            mixed = t0 * self.mult[0] ^ t1 * self.mult[1]
            if order == 3:
                mixed = mixed ^ t2 * self.mult[2]
            base = (order - 2) * 8
            for h in range(8):
                rid = int(mixed) % int(self.sizes[base + h]) + int(self.offsets[base + h])
                out[(base + h) * self.head_dim:(base + h + 1) * self.head_dim] = self._row(rid)
        # advance context; an eos token resets the segment
        self.ctx = [self.ctx[-1], tok]
        if tok == EOS:
            self.ctx = [EOS, EOS]
        return out

    def forward(self, H, tok):
        e = self.embed(tok)
        kn = grouped_rms_norm(self.w_key @ e, self.n_key).reshape(HC, HIDDEN)
        v = self.w_val @ e
        qn = grouped_rms_norm(H, self.n_query).reshape(HC, HIDDEN)
        gate = np.sum(kn * qn, axis=-1, keepdims=True) / np.sqrt(HIDDEN)   # [4,1]
        gate = sigmoid(np.sign(gate) * np.sqrt(np.maximum(np.abs(gate), 1e-6)))
        gv = (gate * v[None, :]).reshape(HC_HIDDEN)
        nc = grouped_rms_norm(gv, self.n_conv)
        window = np.concatenate([self.conv_state, nc[:, None]], axis=1)   # [10240,10]
        self.conv_state = window[:, 1:]
        taps = window[:, [0, 3, 6, 9]]                                    # t-9,t-6,t-3,t
        co = silu(np.sum(taps * self.conv, axis=1))
        return H + gv + co


class Model:
    def __init__(self):
        t0 = time.time()
        ck = Checkpoint()
        ex = Experts()
        self.ck = ck
        self.embed = None   # lazy row lookup
        self.lm_head = ck.get("lm_head.weight")
        pfx = "model.language_model."
        self.mixer = HyperConn(ck, pfx + "hyper_connection_mixer.")
        self.layers = []
        for li in range(N_LAYERS):
            lp = f"{pfx}layers.{li}."
            full = (li + 1) % 4 == 0
            self.layers.append({
                "attn_hc": HyperConn(ck, lp + "attn_hyper_connection."),
                "mlp_hc": HyperConn(ck, lp + "mlp_hyper_connection."),
                "core": AttnLayer(ck, lp + "self_attn.") if full
                        else GDNLayer(ck, lp + "linear_attn."),
                "moe": MoE(ck, ex, li, lp + "mlp."),
                "ple": PLE(ck, lp + "ple.") if li == PLE_LAYER else None,
            })
            if li % 8 == 0:
                print(f"  loaded layer {li} ({time.time() - t0:.0f}s)")
        print(f"model loaded in {time.time() - t0:.0f}s")

    def embed_row(self, tok):
        buf, dtype, shape = self.ck.raw("model.language_model.embed_tokens.weight")
        row = buf.view(np.uint16)[tok * HIDDEN:(tok + 1) * HIDDEN]
        return (row.astype(np.uint32) << 16).view(np.float32).astype(np.float32)

    def forward(self, tok, pos, dump=None):
        h = self.embed_row(tok)
        H = np.tile(h, HC)                                             # replicate x4
        for li, L in enumerate(self.layers):
            if L["ple"] is not None:
                H = L["ple"].forward(H, tok)
            x, n = L["attn_hc"].mix(H)
            y = L["core"].forward(x, pos) if isinstance(L["core"], AttnLayer) \
                else L["core"].forward(x)
            H = L["attn_hc"].combine(H, n, y)
            x, n = L["mlp_hc"].mix(H)
            y = L["moe"].forward(x)
            H = L["mlp_hc"].combine(H, n, y)
            if dump is not None:
                dump[f"h_pos{pos}_layer{li}"] = H.copy()
        x, _ = self.mixer.mix(H)
        logits = self.lm_head @ x
        if dump is not None:
            dump[f"final_pos{pos}"] = x.copy()
            dump[f"logits_pos{pos}"] = logits.copy()
        return logits


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tokens", type=int, default=8)
    ap.add_argument("--prompt-ids", type=str, default="760,6511,314,9338,369")
    ap.add_argument("--dump", type=str, default=None)
    args = ap.parse_args()

    prompt = [int(t) for t in args.prompt_ids.split(",")]
    model = Model()
    dump = {} if args.dump else None

    logits = None
    for i, tok in enumerate(prompt):
        t0 = time.time()
        logits = model.forward(tok, i, dump)
        print(f"prefill pos {i} tok {tok}: {time.time() - t0:.1f}s")
    ids = [int(np.argmax(logits))]
    print(f"first prediction: {ids[0]}")
    pos = len(prompt)
    while len(ids) < args.tokens:
        t0 = time.time()
        logits = model.forward(ids[-1], pos, dump)
        ids.append(int(np.argmax(logits)))
        pos += 1
        print(f"decode pos {pos - 1}: tok {ids[-1]} ({time.time() - t0:.1f}s)")
    print("ids:", ids)
    if dump is not None:
        np.savez(args.dump, **dump)
        print(f"goldens -> {args.dump}.npz ({len(dump)} arrays)")


if __name__ == "__main__":
    main()
