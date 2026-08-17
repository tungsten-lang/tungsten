#!/usr/bin/env python3
"""Matched serial-decode baseline using the actual MLX/MLX-LM runtime.

The Ollama MLX export uses ModelOpt companion names (`weight.scale` plus a
separate `weight.global_scale`) rather than MLX-LM's native `scales` field.
This loader maps those names and applies the global scale inside each
QuantizedLinear call. It deliberately drops the inline MTP head: this is the
ordinary one-token target-model baseline, not speculative decoding.
"""

from __future__ import annotations

import argparse
import json
import statistics
import time
from pathlib import Path

import mlx.core as mx
import mlx.nn as nn
from mlx_lm.models.qwen3_5 import Model, ModelArgs


DEFAULT_MODEL = Path.home() / ".cache/tungsten/qwen3.8-27b-mlx"
PROMPT_IDS = [760, 6511, 314, 9338, 369]
EXPECTED_FIRST = 11751


def load_raw_weights(model_dir: Path) -> dict[str, mx.array]:
    index = json.loads((model_dir / "model.safetensors.index.json").read_text())
    weights: dict[str, mx.array] = {}
    for shard in sorted(set(index["weight_map"].values())):
        weights.update(mx.load(str(model_dir / shard)))
    return weights


def build_model(model_dir: Path) -> Model:
    config = json.loads((model_dir / "config.json").read_text())
    model = Model(ModelArgs.from_dict(config))
    weights = model.sanitize(load_raw_weights(model_dir))

    mapped: dict[str, mx.array] = {}
    global_scales: dict[str, mx.array] = {}
    for name, value in weights.items():
        if name.endswith(".weight.scale"):
            mapped[name.removesuffix(".weight.scale") + ".scales"] = value
        elif name.endswith(".weight.global_scale"):
            module_path = name.removesuffix(".weight.global_scale")
            global_scales[module_path] = value
            mapped[module_path + ".global_scale"] = value
        else:
            mapped[name] = value
    weights = mapped

    nn.quantize(
        model,
        group_size=16,
        bits=4,
        mode="nvfp4",
        class_predicate=lambda path, _: path + ".scales" in weights,
    )
    modules = dict(model.named_modules())
    for path, scale in global_scales.items():
        modules[path].global_scale = scale

    original_call = nn.QuantizedLinear.__call__

    def scaled_call(layer: nn.QuantizedLinear, inputs: mx.array) -> mx.array:
        if "global_scale" in layer:
            inputs = inputs * layer.global_scale
        return original_call(layer, inputs)

    nn.QuantizedLinear.__call__ = scaled_call
    model.load_weights(list(weights.items()), strict=True)
    model.eval()
    return model


def decode(model: Model, token_count: int) -> tuple[float, list[int]]:
    cache = model.make_cache()
    logits = model(mx.array([PROMPT_IDS]), cache=cache)
    token = mx.argmax(logits[0, -1])
    mx.eval(token)
    ids = [token.item()]
    if ids[0] != EXPECTED_FIRST:
        raise RuntimeError(f"parity failure: expected {EXPECTED_FIRST}, got {ids[0]}")

    begin = time.perf_counter()
    for _ in range(token_count):
        logits = model(token.reshape(1, 1), cache=cache)
        token = mx.argmax(logits[0, -1])
        mx.eval(token)
        ids.append(token.item())
    elapsed = time.perf_counter() - begin
    return token_count / elapsed, ids


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", type=Path, default=DEFAULT_MODEL)
    parser.add_argument("--tokens", type=int, default=48)
    parser.add_argument("--warmup-tokens", type=int, default=12)
    parser.add_argument("--runs", type=int, default=5)
    args = parser.parse_args()

    if args.tokens <= 0 or args.warmup_tokens <= 0 or args.runs <= 0:
        parser.error("tokens, warmup-tokens, and runs must be positive")

    model = build_model(args.model)
    warm_rate, warm_ids = decode(model, args.warmup_tokens)
    print(
        f"MLX-LM serial warmup: {warm_rate:.3f} tok/s, "
        f"first={warm_ids[0]}"
    )

    rates: list[float] = []
    final_ids: list[int] = []
    for index in range(args.runs):
        rate, final_ids = decode(model, args.tokens)
        rates.append(rate)
        print(f"MLX-LM serial run {index + 1}/{args.runs}: {rate:.3f} tok/s")

    print(
        "MLX-LM serial summary: "
        f"median={statistics.median(rates):.3f} tok/s "
        f"min={min(rates):.3f} max={max(rates):.3f}"
    )
    print("generated ids:", final_ids)


if __name__ == "__main__":
    main()
