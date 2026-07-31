#!/usr/bin/env python3
"""Benchmark a live Koala forest against its generated Tungsten source.

The script generates a deterministic 50-tree classifier artifact, compiles
that exact source into a native probe, and compares single-row label and
probability latency with the live model. Run from anywhere:

    python bits/tungsten-koala/benchmarks/compare_random_forest_export.py

This is intentionally a single-row deployment benchmark. The ordinary
decision_tree_speed.w benchmark covers high-throughput batch prediction.
"""

from __future__ import annotations

import subprocess
import tempfile
from pathlib import Path
from statistics import median


ROOT = Path(__file__).resolve().parents[3]
TUNGSTEN = ROOT / "bin" / "tungsten"

FIXTURE = r"""
-> export_benchmark_rows(n, width)
  rows = []
  labels = []
  i = 0
  while i < n
    row = []
    j = 0
    while j < width
      row.push((i * (37 + j * 2) + j * 101 + i * j * 3) % 1009)
      j += 1
    signal = row[0] + row[3] - row[5]
    label = 0
    label = 1 if signal > 450
    label = 2 if row[7] < 200 && row[1] > 600
    rows.push(row)
    labels.push(label)
    i += 1
  { rows: rows, labels: labels }
"""

GENERATOR = (
    "use koala\n"
    + FIXTURE
    + r"""
fixture = export_benchmark_rows(1200, 12)
model = RandomForestClassifier.new(50, :sqrt, 8, 2, 42)
model.fit(fixture[:rows], fixture[:labels])
artifact = RandomForestExport.export(
  model,
  [:x0, :x1, :x2, :x3, :x4, :x5, :x6, :x7, :x8, :x9, :x10, :x11],
  :deployed_forest
)
compact = RandomForestExport.export_compact(
  model,
  [:x0, :x1, :x2, :x3, :x4, :x5, :x6, :x7, :x8, :x9, :x10, :x11],
  :compact_forest
)
<< artifact[:source]
<< "KOALA_COMPACT_ARTIFACT"
<< compact[:source]
"""
)

RUNNER = (
    FIXTURE
    + r"""
fixture = export_benchmark_rows(1200, 12)
rows = fixture[:rows]
labels = fixture[:labels]
model = RandomForestClassifier.new(50, :sqrt, 8, 2, 42)
model.fit(rows, labels)
schema = 2137080493
compact_schema = 2137080493

live_labels = model.predict(rows)
exported_labels = []
compact_labels = []
live_probabilities = model.predict_proba(rows)
exported_probabilities = []
compact_probabilities = []
rows.each -> (row)
  exported_labels.push(deployed_forest(row, schema))
  exported_probabilities.push(deployed_forest_predict_proba(row, schema))
  compact_labels.push(compact_forest(row, compact_schema))
  compact_probabilities.push(compact_forest_predict_proba(row, compact_schema))

label_parity = live_labels.to_s == exported_labels.to_s && live_labels.to_s == compact_labels.to_s
probability_parity = live_probabilities.to_s == exported_probabilities.to_s && live_probabilities.to_s == compact_probabilities.to_s

# Warm both paths before the measured loops.
model.predict([rows[0]])
model.predict_proba([rows[0]])
deployed_forest(rows[0], schema)
deployed_forest_predict_proba(rows[0], schema)
compact_forest(rows[0], compact_schema)
compact_forest_predict_proba(rows[0], compact_schema)

repeats = 10
started = ccall("__w_clock_ms")
live_label_checksum = 0
repeats.times -> (repeat)
  rows.each -> (row)
    live_label_checksum += model.predict([row])[0]
live_label_ms = ccall("__w_clock_ms") - started

started = ccall("__w_clock_ms")
export_label_checksum = 0
repeats.times -> (repeat)
  rows.each -> (row)
    export_label_checksum += deployed_forest(row, schema)
export_label_ms = ccall("__w_clock_ms") - started

started = ccall("__w_clock_ms")
live_probability_checksum = 0.to_f
repeats.times -> (repeat)
  rows.each -> (row)
    probability = model.predict_proba([row])[0]
    probability.each_with_index -> (value, c)
      live_probability_checksum += value * (c + 1).to_f
live_probability_ms = ccall("__w_clock_ms") - started

started = ccall("__w_clock_ms")
export_probability_checksum = 0.to_f
repeats.times -> (repeat)
  rows.each -> (row)
    probability = deployed_forest_predict_proba(row, schema)
    probability.each_with_index -> (value, c)
      export_probability_checksum += value * (c + 1).to_f
export_probability_ms = ccall("__w_clock_ms") - started

started = ccall("__w_clock_ms")
compact_label_checksum = 0
repeats.times -> (repeat)
  rows.each -> (row)
    compact_label_checksum += compact_forest(row, compact_schema)
compact_label_ms = ccall("__w_clock_ms") - started

started = ccall("__w_clock_ms")
compact_probability_checksum = 0.to_f
repeats.times -> (repeat)
  rows.each -> (row)
    probability = compact_forest_predict_proba(row, compact_schema)
    probability.each_with_index -> (value, c)
      compact_probability_checksum += value * (c + 1).to_f
compact_probability_ms = ccall("__w_clock_ms") - started

nodes = 0
model.trees.each -> (tree)
  nodes += DecisionTree.node_count(tree)
<< "forest_trees," + model.tree_count.to_s
<< "forest_nodes," + nodes.to_s
<< "implementation,label_ms_12000_rows,probability_ms_12000_rows,label_checksum,probability_checksum"
<< "live," + live_label_ms.to_s + "," + live_probability_ms.to_s + "," + live_label_checksum.to_s + "," + live_probability_checksum.to_s
<< "exported," + export_label_ms.to_s + "," + export_probability_ms.to_s + "," + export_label_checksum.to_s + "," + export_probability_checksum.to_s
<< "compact," + compact_label_ms.to_s + "," + compact_probability_ms.to_s + "," + compact_label_checksum.to_s + "," + compact_probability_checksum.to_s
<< "label_parity_gate," + (label_parity ? "PASS" : "FAIL")
<< "probability_parity_gate," + (probability_parity ? "PASS" : "FAIL")
"""
)


def run(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        cwd=ROOT,
        check=True,
        text=True,
        capture_output=True,
    )


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="koala-forest-export-") as tmp:
        temporary = Path(tmp)
        generator = temporary / "generate.w"
        generator.write_text(GENERATOR)
        generator_executable = temporary / "generate"
        run(
            str(TUNGSTEN),
            "compile",
            str(generator),
            "--out",
            str(generator_executable),
        )
        generated = run(str(generator_executable)).stdout
        marker = "KOALA_COMPACT_ARTIFACT\n"
        if marker not in generated:
            raise RuntimeError("forest exporter did not produce both source layouts")
        source, compact_source = generated.split(marker, 1)
        if not source.startswith("# Generated by Koala RandomForestExport"):
            raise RuntimeError("forest exporter did not produce a source artifact")
        if not compact_source.startswith("# Generated by Koala RandomForestExport"):
            raise RuntimeError("compact forest exporter did not produce a source artifact")

        checksum_line = next(
            line for line in source.splitlines() if line.startswith("# schema-checksum:")
        )
        checksum = checksum_line.rsplit(" ", 1)[1]
        compact_checksum_line = next(
            line
            for line in compact_source.splitlines()
            if line.startswith("# schema-checksum:")
        )
        compact_checksum = compact_checksum_line.rsplit(" ", 1)[1]
        runner_body = RUNNER.replace(
            "schema = 2137080493", f"schema = {checksum}", 1
        ).replace(
            "compact_schema = 2137080493",
            f"compact_schema = {compact_checksum}",
            1,
        )
        runner_source = (
            "use koala\n\n" + source + "\n" + compact_source + "\n" + runner_body
        )
        runner = temporary / "benchmark.w"
        runner.write_text(runner_source)
        executable = temporary / "benchmark"
        run(str(TUNGSTEN), "compile", str(runner), "--out", str(executable))
        outputs = [run(str(executable)).stdout for _ in range(5)]

        def values(prefix: str) -> list[list[str]]:
            rows = []
            for output in outputs:
                line = next(
                    line for line in output.splitlines() if line.startswith(prefix + ",")
                )
                rows.append(line.split(","))
            return rows

        live = values("live")
        exported = values("exported")
        compact = values("compact")
        if any("label_parity_gate,PASS" not in output for output in outputs):
            raise RuntimeError("generated label predictions diverged from the live forest")
        if any("probability_parity_gate,PASS" not in output for output in outputs):
            raise RuntimeError("generated probabilities diverged from the live forest")

        print(f"unrolled_artifact_bytes,{len(source.encode())}")
        print(f"unrolled_artifact_lines,{len(source.splitlines())}")
        print(f"compact_artifact_bytes,{len(compact_source.encode())}")
        print(f"compact_artifact_lines,{len(compact_source.splitlines())}")
        first_lines = outputs[0].splitlines()
        print(next(line for line in first_lines if line.startswith("forest_trees,")))
        print(next(line for line in first_lines if line.startswith("forest_nodes,")))
        print("benchmark_runs,5")
        print("live_label_ms_samples," + ",".join(row[1] for row in live))
        print("exported_label_ms_samples," + ",".join(row[1] for row in exported))
        print("compact_label_ms_samples," + ",".join(row[1] for row in compact))
        print("live_probability_ms_samples," + ",".join(row[2] for row in live))
        print("exported_probability_ms_samples," + ",".join(row[2] for row in exported))
        print(
            "compact_probability_ms_samples," + ",".join(row[2] for row in compact)
        )
        print(
            "implementation,median_label_ms_12000_rows,"
            "median_probability_ms_12000_rows,label_checksum,probability_checksum"
        )
        print(
            f"live,{median(int(row[1]) for row in live):g},"
            f"{median(int(row[2]) for row in live):g},{live[0][3]},{live[0][4]}"
        )
        print(
            f"exported,{median(int(row[1]) for row in exported):g},"
            f"{median(int(row[2]) for row in exported):g},"
            f"{exported[0][3]},{exported[0][4]}"
        )
        print(
            f"compact,{median(int(row[1]) for row in compact):g},"
            f"{median(int(row[2]) for row in compact):g},"
            f"{compact[0][3]},{compact[0][4]}"
        )
        print("label_parity_gate,PASS")
        print("probability_parity_gate,PASS")


if __name__ == "__main__":
    main()
