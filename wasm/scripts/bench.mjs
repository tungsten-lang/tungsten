// Compare builds: median warm wall/CPU per run for a few representative programs.
//   node wasm/scripts/bench.mjs a.wasm b.wasm …
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { run, loadBundle } from "../wasi_shim.js";

const here = dirname(fileURLToPath(import.meta.url));
const bundle = loadBundle(readFileSync(join(here, "../tungsten.fs")));
const PROGRAMS = {
  add: `<< 1 + 1\n`,
  map: `squares = [1, 2, 3].map -> (x) x * x\n<< squares\n<< squares.sum\n`,
  class: `+ Vec\n  -> new(@x, @y)\n  -> +(other)\n    Vec.new(@x + other.x, @y + other.y)\n  -> x\n    @x\n  -> y\n    @y\na = Vec.new(1, 2) + Vec.new(3, 4)\n<< "[a.x] [a.y]"\n`,
  loop: `total = 0\n(1..20000).each -> (i)\n  total += i * i % 7\n<< total\n`,
  fib: `-> fib(n)\n  if n < 2\n    return n\n  fib(n - 1) + fib(n - 2)\n<< fib(18)\n`,
};
const median = (v) => [...v].sort((a, b) => a - b)[Math.floor(v.length / 2)];

for (const path of process.argv.slice(2)) {
  const bytes = readFileSync(path);
  const t0 = performance.now();
  const module = new WebAssembly.Module(bytes);
  const compileMs = performance.now() - t0;
  const cells = [];
  for (const [name, source] of Object.entries(PROGRAMS)) {
    const walls = [];
    const cpus = [];
    let out = "";
    for (let i = 0; i < 60; i++) {
      const c0 = process.cpuUsage();
      const w0 = performance.now();
      const result = run(module, { args: ["tungsten", "/work/main.w"], files: [new Map([["/work/main.w", source]]), bundle] });
      const wall = performance.now() - w0;
      const cpu = process.cpuUsage(c0);
      if (i >= 45) { walls.push(wall); cpus.push((cpu.user + cpu.system) / 1000); }
      out = result.exitCode === 0 ? "" : ` EXIT ${result.exitCode}`;
    }
    cells.push(`${name} ${median(walls).toFixed(1)}/${median(cpus).toFixed(1)}${out}`);
  }
  console.log(`${path.split("/").pop().padEnd(18)} ${(bytes.length / 1e6).toFixed(2)} MB  compile ${compileMs.toFixed(0)} ms | wall/cpu ms: ${cells.join("  ")}`);
}
