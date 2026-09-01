"""Checkpoint access layer for the Qwen3.8-Flash-Next numpy reference.

Reads the RadixArk NVFP4 checkpoint directly (mmap, no torch): bf16 -> f32,
fp8 E4M3 via LUT, NVFP4 (E2M1 nibbles x fp8 group scale x f32 tensor scale)
dequant matching the semantics of lib/kernels/nvfp4/*.metal:
  first weight = LOW nibble; scale byte decoded as ((b & 127) << 7) half * 256.
"""

import json
import mmap
import os
import struct

import numpy as np

CACHE = os.path.expanduser("~/.cache/tungsten/qwen38-flash-next-nvfp4")

# E2M1 magnitude table (nibble & 7): 0, .5, 1, 1.5, 2, 3, 4, 6
_NVFP4_MAG = np.array([0.0, 0.5, 1.0, 1.5, 2.0, 3.0, 4.0, 6.0], dtype=np.float32)
_NVFP4_LUT = np.concatenate([_NVFP4_MAG, -_NVFP4_MAG]).astype(np.float32)


def _e4m3_lut():
    lut = np.zeros(256, dtype=np.float32)
    for b in range(256):
        s = -1.0 if b & 0x80 else 1.0
        e = (b >> 3) & 0xF
        m = b & 7
        if e == 0:
            v = (m / 8.0) * 2.0 ** (-6)
        elif e == 15 and m == 7:
            v = float("nan")
        else:
            v = (1.0 + m / 8.0) * 2.0 ** (e - 7)
        lut[b] = s * v
    return lut


E4M3 = _e4m3_lut()


class Checkpoint:
    def __init__(self, cache=CACHE):
        self.cache = cache
        idx = json.load(open(os.path.join(cache, "index.slim.json")))
        self.weight_map = idx["weight_map"]
        self._headers = {}
        self._mmaps = {}

    def _file(self, fname):
        if fname not in self._headers:
            path = os.path.join(self.cache, fname)
            fh = open(path, "rb")
            n = struct.unpack("<Q", fh.read(8))[0]
            hdr = json.loads(fh.read(n))
            mm = mmap.mmap(fh.fileno(), 0, access=mmap.ACCESS_READ)
            self._headers[fname] = (hdr, 8 + n)
            self._mmaps[fname] = mm
        return self._headers[fname], self._mmaps[fname]

    def info(self, name):
        fname = self.weight_map[name]
        (hdr, data_start), mm = self._file(fname)
        return hdr[name], data_start, mm

    def raw(self, name):
        info, data_start, mm = self.info(name)
        o0, o1 = info["data_offsets"]
        buf = np.frombuffer(mm, dtype=np.uint8,
                            count=o1 - o0, offset=data_start + o0)
        return buf, info["dtype"], info["shape"]

    def get(self, name):
        """Tensor as f32 (or i64 for int tensors)."""
        buf, dtype, shape = self.raw(name)
        if dtype == "BF16":
            u16 = buf.view(np.uint16).astype(np.uint32) << 16
            return u16.view(np.float32).reshape(shape).copy()
        if dtype == "F32":
            return buf.view(np.float32).reshape(shape).copy()
        if dtype == "F8_E4M3":
            return E4M3[buf].reshape(shape)
        if dtype == "I64":
            return buf.view(np.int64).reshape(shape).copy()
        if dtype == "U8":
            return buf.reshape(shape).copy()
        raise ValueError(f"{name}: unhandled dtype {dtype}")


def nvfp4_dequant(packed_u8, scales_u8, global_scale, k):
    """packed [R, k/2] u8, scales [R, k/16] u8 -> [R, k] f32."""
    r = packed_u8.shape[0]
    lo = packed_u8 & 0xF
    hi = packed_u8 >> 4
    w = np.empty((r, k), dtype=np.float32)
    w[:, 0::2] = _NVFP4_LUT[lo]
    w[:, 1::2] = _NVFP4_LUT[hi]
    s = E4M3[scales_u8].astype(np.float32)          # [R, k/16]
    w = w.reshape(r, k // 16, 16) * s[:, :, None]
    return (w.reshape(r, k) * np.float32(global_scale)).astype(np.float32)


class Experts:
    """Routed-expert access through experts_manifest.json."""

    def __init__(self, cache=CACHE):
        self.cache = cache
        man = json.load(open(os.path.join(cache, "experts_manifest.json")))
        self.by_lq = {(e["layer"], e["quarter"]): e for e in man["files"]}
        self._mmaps = {}

    def _mm(self, fname):
        if fname not in self._mmaps:
            fh = open(os.path.join(self.cache, fname), "rb")
            self._mmaps[fname] = mmap.mmap(fh.fileno(), 0,
                                           access=mmap.ACCESS_READ)
        return self._mmaps[fname]

    def weight(self, layer, expert, mat):
        """Dequantized [rows, k] f32 for one routed expert matrix
        (mat in gate_proj/up_proj/down_proj)."""
        q, e = expert // 128, expert % 128
        entry = self.by_lq[(layer, q)]
        mm = self._mm(entry["file"])
        slot = entry["slot_map"][e]
        m = entry[mat]
        ds = entry["data_start"]
        rows, k = (2560, 640) if mat == "down_proj" else (640, 2560)
        w = np.frombuffer(mm, dtype=np.uint8, count=rows * k // 2,
                          offset=ds + m["w0"] + slot * m["w_stride"]).reshape(rows, k // 2)
        s = np.frombuffer(mm, dtype=np.uint8, count=rows * k // 16,
                          offset=ds + m["s0"] + slot * m["s_stride"]).reshape(rows, k // 16)
        gs = np.frombuffer(mm, dtype=np.float32, count=1,
                           offset=ds + m["g0"] + slot * m["g_stride"])[0]
        return nvfp4_dequant(w, s, gs, k)
