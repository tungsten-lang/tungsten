// Dev runner: execute a wasm build against the REAL checkout on disk (no
// bundle), logging every path the guest opens. This is how the contents of
// tungsten.fs were discovered.
//
//   node wasm/scripts/dev_run.mjs [--wasm file] [--trace] (-e 'code' | file.w) [args…]
import { readFileSync, statSync, readdirSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { run } from "../wasi_shim.js";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const argv = process.argv.slice(2);
let wasmPath = join(root, "wasm/build/tungsten.raw.wasm");
let trace = false;
let source = null;
const rest = [];
for (let i = 0; i < argv.length; i++) {
  if (argv[i] === "--wasm") wasmPath = argv[++i];
  else if (argv[i] === "--trace") trace = true;
  else if (argv[i] === "-e") source = argv[++i] + "\n";
  else if (source === null && rest.length === 0 && !argv[i].startsWith("-")) source = readFileSync(argv[i], "utf8");
  else rest.push(argv[i]);
}

const disk = {
  get(path) {
    try {
      const full = join(root, path);
      return statSync(full).isFile() ? readFileSync(full) : undefined;
    } catch { return undefined; }
  },
  isDir(path) {
    try { return statSync(join(root, path)).isDirectory(); } catch { return false; }
  },
  list(path) {
    try { return readdirSync(join(root, path)); } catch { return undefined; }
  },
};

const opened = [];
const t0 = performance.now();
const module = new WebAssembly.Module(readFileSync(wasmPath));
const t1 = performance.now();
const result = run(module, {
  args: ["tungsten", "/work/main.w", ...rest],
  files: [new Map([["/work/main.w", source ?? ""]]), disk],
  onOpen: (path) => opened.push(path),
  debug: true,
});
const t2 = performance.now();
process.stdout.write(result.stdout);
process.stderr.write(result.stderr);
console.error(`[exit ${result.exitCode}] compile ${(t1 - t0).toFixed(1)} ms, run ${(t2 - t1).toFixed(1)} ms`);
if (trace) console.error(opened.map((p) => "  open " + p).join("\n"));
