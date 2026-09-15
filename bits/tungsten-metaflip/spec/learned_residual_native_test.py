#!/usr/bin/env python3
"""Independent exact algebra, model parity, and hostile-model tests of native arm."""
import importlib.util
import itertools
import json
from pathlib import Path
import random
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("oracle", ROOT / "tools/learned_residual_completion.py")
oracle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(oracle)
spec = importlib.util.spec_from_file_location("exporter", ROOT / "tools/export_learned_residual.py")
exporter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(exporter)


def main():
    binary = str(Path(sys.argv[1]).resolve())
    model_path = ROOT / "tools/learned_residual/model-v1.mfl"
    native = model_path.read_text().splitlines()
    numbers = list(map(float, native[1:]))
    model = oracle.ValueModel(numbers[:18], numbers[18:36],
                              oracle.np.array(numbers[36:468]).reshape(18, 24),
                              numbers[468:492], oracle.np.array(numbers[492:516]).reshape(24, 1),
                              numbers[516:])
    # Exact BFS recipes for every 2x2x2 tensor, independent of the beam/model.
    alphabet = list(itertools.product(range(1, 4), repeat=3))
    recipes = {0: []}
    while len(recipes) < 256:
        before = len(recipes)
        for target, recipe in list(recipes.items()):
            for term in alphabet:
                recipes.setdefault(target ^ oracle.outer(term, (2, 2, 2)), recipe + [term])
        assert len(recipes) > before
    cases = [((2, 2, 2), terms, max(1, len(terms)), 12000) for terms in recipes.values()]
    rng = random.Random(140926)
    for _ in range(80):
        widths = tuple(rng.choice((4, 7, 13, 63)) for _ in range(3))
        bases = [oracle.basis(rng.randrange(1, 1 << width) for _ in range(4))[0] for width in widths]
        small = [tuple(rng.randrange(1, 1 << len(b)) for b in bases) for _ in range(rng.randrange(3, 7))]
        terms = oracle.lift(small, bases)
        cases.append((widths, terms, len(terms), 12000))
    cases += [((4, 4, 4), [(1 << i,) * 3 for i in range(4)], 4, 12000),
              ((4, 4, 4), [(1 << i,) * 3 for i in range(4)], 4, 1),
              ((5, 5, 5), [(1 << i,) * 3 for i in range(5)], 5, 12000),
              ((2, 2, 2), [(3, 3, 3)] * 2, 1, 12000)]
    with tempfile.TemporaryDirectory(prefix="metaflip-native-parity-") as tmp:
        tmp = Path(tmp)
        inputs = tmp / "cases.txt"
        inputs.write_text("".join(" ".join(map(str, (*dims, len(terms), limit, budget,
                             *(x for term in terms for x in term)))) + "\n"
                                 for dims, terms, limit, budget in cases))
        run = subprocess.run([binary, str(model_path), str(inputs)], capture_output=True, text=True, timeout=90)
        assert run.returncode == 0, (run.returncode, run.stderr, run.stdout)
        lines = run.stdout.splitlines()
        assert len(lines) == len(cases), (len(lines), len(cases), run.stdout[-2000:])
        completed_count = 0
        high_bit = False
        for (widths, terms, limit, budget), line in zip(cases, lines):
            target = oracle.tensor(terms, widths)
            compressed, expected_dims, _ = oracle.compress_residual(target, widths)
            if line == "UNSUPPORTED":
                assert max(expected_dims) > 4
                continue
            fields = line.split()
            assert fields[0] == "CASE", line
            dims = tuple(map(int, fields[1:4]))
            core = int(fields[4]) & ((1 << 64)-1)
            high_bit |= core >= 1 << 63
            score = float(fields[5])
            actual_features = list(map(float, fields[6:24]))
            expected_features = oracle.features(compressed, expected_dims) if target else [0.] * 18
            assert dims == expected_dims
            assert max(abs(a-b) for a, b in zip(actual_features, expected_features)) < 1e-8
            assert abs(score - float(model.predict([expected_features])[0])) < 1e-7
            bases = [list(map(int, fields[24+4*a:28+4*a])) for a in range(3)]
            singles = [(1 << (i//(dims[1]*dims[2])), 1 << (i//dims[2]%dims[1]), 1 << (i%dims[2]))
                       for i in oracle.bits(core)]
            assert oracle.tensor(oracle.lift(singles, bases), widths) == target, "compression/lift mismatch"
            count, checks, reason = map(int, fields[36:39])
            assert 0 <= checks <= budget
            if count >= 0:
                values = list(map(int, fields[39:]))
                assert len(values) == 3*count and count <= limit and reason == 1
                result = [tuple(values[i:i+3]) for i in range(0, len(values), 3)]
                assert oracle.tensor(result, widths) == target
                completed_count += 1
            else:
                assert count == -1 and reason in (2, 4, 5, 6)
            if target == 0 or max(oracle.flatten_ranks(compressed, expected_dims)) <= 1:
                assert count >= 0, "exact rank-one tail must be recognized"
        assert high_bit, "missing signed-high-bit coverage"
        for mutation in ("NaN", "inf", "1garbage", "1e9999", "", "1.0.0"):
            bad = native.copy()
            bad[40] = mutation
            path = tmp / "bad.mfl"
            path.write_text("\n".join(bad) + "\n")
            run = subprocess.run([binary, str(path), str(inputs)], capture_output=True, text=True, timeout=5)
            assert run.returncode == 2, mutation
        for position, value in ((0, "MFLR2 sorted-slice-ranks 18 24 1"), (19, "0"), (19, "-1")):
            bad = native.copy()
            bad[position] = value
            path.write_text("\n".join(bad) + "\n")
            assert subprocess.run([binary, str(path), str(inputs)], capture_output=True, timeout=5).returncode == 2
        assert exporter.export(dict(schema=oracle.SCHEMA, features=oracle.FEATURES,
                                   arrays={k: v.tolist() for k, v in model.arrays().items()})) == model_path.read_text()
        print(json.dumps(dict(cases=len(cases), exact_completions=completed_count,
                              high_bit=high_bit, feature_model_parity=True, invalid_models_rejected=9)))


if __name__ == "__main__":
    main()
