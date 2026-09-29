#!/usr/bin/env node
// profile.mjs — sample a Tungsten wasm program under V8's CPU profiler and
// emit folded stacks for `tungsten flame --folded`.
//
//   node wasm/scripts/profile.mjs PROGRAM.wasm [--stdin FILE] [--sidemap FILE]
//        [--out prof.folded] [--keep-profile DIR] [--fs tungsten.fs] [-- script args…]
//
//   node wasm/scripts/profile.mjs --convert PROFILE.cpuprofile|trace.json
//        [--sidemap FILE] [--out prof.folded]
//
// The first form re-executes itself under `node --cpu-prof`, runs the module
// through wasi_shim.js (an AOT-compiled program needs no bundle; pass --fs for
// the interpreter image), and converts the resulting .cpuprofile. The second
// form converts a profile captured elsewhere: a `.cpuprofile` from node or the
// Chrome DevTools JavaScript Profiler, or a DevTools Performance trace (.json,
// whose ProfileChunk events carry the same node/sample tables). wasm frames
// come out as their name-section symbols; a compiler sidemap (written next to
// the emitted IR) maps `__wy_<hash>` back to `Class.method`.
import { readFileSync, writeFileSync, readdirSync, mkdtempSync, statSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const argv = process.argv.slice(2);
const opt = { convert: null, program: null, stdin: null, sidemap: null, out: null, keep: null, fs: null, args: [] };
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a === "--") { opt.args = argv.slice(i + 1); break; }
  else if (a === "--convert") opt.convert = argv[++i];
  else if (a === "--stdin") opt.stdin = argv[++i];
  else if (a === "--sidemap") opt.sidemap = argv[++i];
  else if (a === "--out" || a === "-o") opt.out = argv[++i];
  else if (a === "--keep-profile") opt.keep = argv[++i];
  else if (a === "--fs") opt.fs = argv[++i];
  else if (a === "--child") { opt.child = true; }
  else if (!opt.program) opt.program = a;
  else opt.args.push(a);
}

function loadSidemap(path) {
  if (!path) return {};
  const sm = JSON.parse(readFileSync(path, "utf8"));
  const names = {};
  for (const rec of Object.values(sm.hashes || {})) {
    const orig = (rec.originals || []).map((o) => (o.class ? o.class + "." : "") + (o.method || o.symbol));
    if (rec.symbol && orig.length) names[rec.symbol] = orig.join("|");
  }
  return names;
}

/** Turn a cpuprofile object ({nodes, samples, timeDeltas}) into folded text. */
function fold(profile, names) {
  const byId = new Map(profile.nodes.map((n) => [n.id, n]));
  const parent = new Map();
  for (const n of profile.nodes) for (const c of n.children || []) parent.set(c, n.id);
  const frameName = (n) => {
    const cf = n.callFrame || {};
    let fn = cf.functionName || "(anonymous)";
    const url = cf.url || "";
    if (url.startsWith("wasm://") || url.includes(".wasm")) { if (names[fn]) fn = names[fn]; return "wasm:" + fn; }
    if (fn === "(program)" || fn === "(idle)" || fn === "(garbage collector)" || fn === "(root)") return fn;
    return fn + (url ? " " + url.split("/").pop() : "");
  };
  const stackCache = new Map();
  const stackOf = (id) => {
    if (stackCache.has(id)) return stackCache.get(id);
    const frames = [];
    for (let cur = id; cur != null; cur = parent.get(cur)) { const n = byId.get(cur); if (!n) break; const f = frameName(n); if (f !== "(root)") frames.push(f); }
    frames.reverse();
    const s = frames.join(";");
    stackCache.set(id, s);
    return s;
  };
  const weights = new Map();
  const deltas = profile.timeDeltas || [];
  for (let i = 0; i < profile.samples.length; i++) {
    const w = Math.max(0, deltas[i + 1] ?? deltas[i] ?? 0);   // microseconds attributed to sample i
    const s = stackOf(profile.samples[i]);
    if (!s) continue;
    weights.set(s, (weights.get(s) || 0) + w);
  }
  return [...weights.entries()].filter(([, w]) => w > 0).map(([s, w]) => `${s} ${Math.round(w)}`).sort().join("\n") + "\n";
}

/** Accept a .cpuprofile or a DevTools Performance trace (.json with ProfileChunk events). */
function loadProfile(path) {
  const doc = JSON.parse(readFileSync(path, "utf8"));
  if (doc.nodes && doc.samples) return doc;
  const events = Array.isArray(doc) ? doc : doc.traceEvents || [];
  const nodes = [], samples = [], timeDeltas = [];
  let start = null;
  for (const e of events) {
    if (e.name === "Profile" && e.args?.data?.startTime != null) start = e.args.data.startTime;
    if (e.name === "ProfileChunk" && e.args?.data) {
      const d = e.args.data;
      if (d.cpuProfile?.nodes) nodes.push(...d.cpuProfile.nodes);
      if (d.cpuProfile?.samples) samples.push(...d.cpuProfile.samples);
      if (d.timeDeltas) timeDeltas.push(...d.timeDeltas);
    }
  }
  if (!nodes.length) throw new Error("no cpuprofile nodes found in " + path);
  // chunked nodes carry parent ids rather than children lists
  const byId = new Map(nodes.map((n) => [n.id, n]));
  for (const n of nodes) if (n.parent != null) { const p = byId.get(n.parent); if (p) (p.children ??= []).push(n.id); }
  return { nodes, samples, timeDeltas, startTime: start };
}

const names = loadSidemap(opt.sidemap);
if (opt.convert) {
  const folded = fold(loadProfile(opt.convert), names);
  if (opt.out) { writeFileSync(opt.out, folded); console.error(`wrote folded stacks: ${opt.out}`); } else process.stdout.write(folded);
  process.exit(0);
}
if (!opt.program) { console.error("usage: profile.mjs PROGRAM.wasm [--stdin FILE] [--sidemap FILE] [--out prof.folded] [-- args…]  |  --convert PROFILE"); process.exit(2); }

if (!opt.child) {
  // parent: run the child under --cpu-prof, then convert its profile
  const dir = opt.keep || mkdtempSync(join(tmpdir(), "tungsten-wasm-prof-"));
  const self = fileURLToPath(import.meta.url);
  const childArgs = ["--cpu-prof", `--cpu-prof-dir=${dir}`, self, "--child", opt.program];
  if (opt.stdin) childArgs.push("--stdin", opt.stdin);
  if (opt.fs) childArgs.push("--fs", opt.fs);
  childArgs.push("--", ...opt.args);
  const r = spawnSync(process.execPath, childArgs, { stdio: ["inherit", "inherit", "inherit"] });
  const files = readdirSync(dir).filter((f) => f.endsWith(".cpuprofile")).map((f) => join(dir, f)).sort((a, b) => statSync(b).mtimeMs - statSync(a).mtimeMs);
  if (!files.length) { console.error("no .cpuprofile written under " + dir); process.exit(1); }
  const folded = fold(loadProfile(files[0]), names);
  const out = opt.out || resolve(opt.program.replace(/\.wasm$/, "") + ".folded");
  writeFileSync(out, folded);
  console.error(`wrote folded stacks: ${out}  (profile: ${files[0]})`);
  process.exit(r.status ?? 0);
}

// child: execute the module once under the sampler
const shimPath = join(dirname(fileURLToPath(import.meta.url)), "..", "wasi_shim.js");
const { run, loadBundle } = await import(shimPath);
const module = new WebAssembly.Module(readFileSync(opt.program));
const files = [new Map()];
if (opt.fs) files.push(loadBundle(readFileSync(opt.fs)));
const stdin = opt.stdin ? readFileSync(opt.stdin) : "";
const result = run(module, { args: [opt.program.split("/").pop(), ...opt.args], stdin, files, maxOutputBytes: 256 << 20 });
process.stdout.write(result.stdout);
process.stderr.write(result.stderr);
process.exitCode = result.exitCode;
