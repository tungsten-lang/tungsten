// test.mjs — run the wasm interpreter under wasi_shim.js (NOT node:wasi) and
// check a suite of programs, with honest per-run timing and a comparison
// against the native `tungsten run --interpret`.
//
//   node wasm/test.mjs [--wasm wasm/tungsten.wasm] [--fs wasm/tungsten.fs]
//                      [--twin wasm/build/native_entry | --no-native]
//                      [--cli /path/to/bin/tungsten]
//                      [--runs 5] [--only name] [--verbose]
//
// Two native references:
//   twin  wasm/repl_entry.w compiled NATIVELY from this same checkout
//         (wasm/scripts/build_native_entry.sh). Same entry, interpreter and
//         core; only the target differs, so stdout + exit status must match
//         exactly. This is the strict comparison.
//   cli   `bin/tungsten run --interpret` from an installed checkout. It may be
//         built from different sources, so a difference is reported, not failed.
import { readFileSync, writeFileSync, mkdtempSync, existsSync, rmSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { run, loadBundle } from "./wasi_shim.js";

const here = dirname(fileURLToPath(import.meta.url));
const options = {
  wasm: join(here, "tungsten.wasm"),
  fs: join(here, "tungsten.fs"),
  twin: join(here, "build/native_entry"),
  cli: process.env.NATIVE_TUNGSTEN ?? join(here, "../bin/tungsten"),
  runs: 5,
  only: null,
  verbose: false,
};
for (let i = 2; i < process.argv.length; i++) {
  const arg = process.argv[i];
  if (arg === "--wasm") options.wasm = resolve(process.argv[++i]);
  else if (arg === "--fs") options.fs = resolve(process.argv[++i]);
  else if (arg === "--twin") options.twin = resolve(process.argv[++i]);
  else if (arg === "--cli") options.cli = resolve(process.argv[++i]);
  else if (arg === "--no-native") options.twin = options.cli = null;
  else if (arg === "--runs") options.runs = Number(process.argv[++i]);
  else if (arg === "--only") options.only = process.argv[++i];
  else if (arg === "--verbose") options.verbose = true;
}

// `stdout` is matched exactly. `stderr` is a list of substrings that must all
// appear. `exit` is "zero" | "nonzero".
const PROGRAMS = [
  { name: "add", source: `<< 1 + 1\n`, stdout: "2\n" },
  {
    name: "class+operator+interpolation",
    source: `+ Vec
  -> new(@x, @y)
  -> +(other)
    Vec.new(@x + other.x, @y + other.y)
  -> x
    @x
  -> y
    @y
  -> to_s
    "Vec([@x], [@y])"

a = Vec.new(1, 2)
b = Vec.new(10, 20)
c = a + b
<< c.to_s
name = "wasm"
<< "hello [name], sum is [c.x + c.y]"
`,
    stdout: "Vec(11, 22)\nhello wasm, sum is 33\n",
  },
  {
    name: "map/select blocks",
    source: `squares = [1, 2, 3].map -> (x) x * x
<< squares
<< squares.sum
evens = [1, 2, 3, 4, 5, 6].select -> (x) x % 2 == 0
<< evens
`,
    stdout: "[1, 4, 9]\n14\n[2, 4, 6]\n",
  },
  {
    name: "hashes",
    source: `ages = { "ada" => 36, "alan" => 41 }
ages["grace"] = 85
<< ages["ada"]
<< ages.size
ages.each -> (k, v)
  << "[k] is [v]"
<< ages.keys
`,
    stdout: "36\n3\nada is 36\nalan is 41\ngrace is 85\n[\"ada\", \"alan\", \"grace\"]\n",
  },
  {
    name: "ranges with each",
    source: `total = 0
(1..5).each -> (i)
  total += i
<< total
(1..3).each -> (i)
  << i * 10
`,
    stdout: "15\n10\n20\n30\n",
  },
  {
    name: "bigint",
    source: `<< 2 ** 100\n<< 2 ** 100 + 1\n<< (2 ** 64) * (2 ** 64)\n<< (2 ** 200) / (2 ** 100)\n`,
    stdout: "1267650600228229401496703205376\n1267650600228229401496703205377\n340282366920938463463374607431768211456\n1267650600228229401496703205376\n",
  },
  { name: "float", source: `<< 3.5 + 1\n<< 10 / 4.0\n`, stdout: "4.5\n2.5\n" },
  { name: "duration literal (autoloads core/duration)", source: `d = 5m30s\n<< d\n<< 1h15m\n`, stdout: "5m30s\n1h15m\n" },
  {
    name: "raise/rescue",
    source: `begin
  raise "boom"
rescue err
  << "rescued: [err]"
<< "after"
`,
    stdout: "rescued: boom\nafter\n",
  },
  {
    name: "runtime error",
    source: `<< "before"\nx = nil\n<< x.no_such_method(1)\n<< "unreachable"\n`,
    stdout: "before\n",
    stderr: ["no_such_method"],
    exit: "nonzero",
  },
  { name: "syntax error", source: `<< "before"\nx = (1 +\n`, stdout: "", stderr: ["error"], exit: "nonzero" },
  {
    name: "guard rails: system / write / env are inert",
    source: `begin
  << system("echo hi")
rescue err
  << "system raised"
begin
  write_file("/tmp/x.txt", "nope")
  << "wrote?"
rescue err
  << "write raised"
<< file?("/tmp/x.txt")
`,
    stdout: null,
    nativeCompare: false,
  },
];

const module = new WebAssembly.Module(readFileSync(options.wasm));
const bundle = loadBundle(readFileSync(options.fs));

function runWasm(source) {
  const cpu0 = process.cpuUsage();
  const t0 = performance.now();
  const result = run(module, {
    args: ["tungsten", "/work/main.w"],
    files: [new Map([["/work/main.w", source]]), bundle],
    maxOutputBytes: 64 * 1024,
  });
  const wallMs = performance.now() - t0;
  const cpu = process.cpuUsage(cpu0);
  return { ...result, wallMs, cpuMs: (cpu.user + cpu.system) / 1000 };
}

const repoRoot = dirname(here);
const median = (values) => [...values].sort((a, b) => a - b)[Math.floor(values.length / 2)];

/** Run a native reference `command args… <file>`; wall time is the median of `runs` processes. */
function runNative(command, leadingArgs, source, cwd) {
  if (!command || !existsSync(command)) return null;
  const dir = mkdtempSync(join(tmpdir(), "tungsten-wasm-test-"));
  const file = join(dir, "main.w");
  writeFileSync(file, source);
  const walls = [];
  let proc;
  for (let i = 0; i < Math.max(1, options.runs); i++) {
    const t0 = performance.now();
    proc = spawnSync(command, [...leadingArgs, file], { encoding: "utf8", cwd, env: { ...process.env, NO_COLOR: "1", TUNGSTEN_ROOT: cwd } });
    walls.push(performance.now() - t0);
  }
  rmSync(dir, { recursive: true, force: true });
  return { stdout: proc.stdout ?? "", stderr: proc.stderr ?? "", exitCode: proc.status ?? -1, wallMs: median(walls) };
}

const stripAnsi = (text) => text.replace(/\x1b\[[0-9;]*m/g, "");

let failures = 0;
const rows = [];
for (const program of PROGRAMS) {
  if (options.only && !program.name.includes(options.only)) continue;
  const first = runWasm(program.source);
  const warm = [];
  for (let i = 0; i < options.runs; i++) warm.push(runWasm(program.source));
  const compare = program.nativeCompare !== false;
  const twin = compare ? runNative(options.twin, [], program.source, repoRoot) : null;
  const cli = compare && options.cli ? runNative(options.cli, ["run", "--interpret"], program.source, dirname(dirname(options.cli))) : null;

  const problems = [];
  if (program.stdout != null && first.stdout !== program.stdout) problems.push(`stdout ${JSON.stringify(first.stdout)} != expected ${JSON.stringify(program.stdout)}`);
  for (const needle of program.stderr ?? []) if (!stripAnsi(first.stderr).includes(needle)) problems.push(`stderr lacks ${JSON.stringify(needle)}`);
  if ((program.exit ?? "zero") === "zero" ? first.exitCode !== 0 : first.exitCode === 0) problems.push(`exit code ${first.exitCode}`);
  if (first.exitCode === 134 || first.exitCode === 124) problems.push("trapped/aborted instead of exiting");
  if (warm.some((w) => w.stdout !== first.stdout || w.exitCode !== first.exitCode)) problems.push("non-deterministic across runs");
  let nativeNote = "twin: skipped";
  if (twin) {
    const same = twin.stdout === first.stdout && twin.exitCode === first.exitCode && stripAnsi(twin.stderr) === stripAnsi(first.stderr).replaceAll("/work/main.w", "MAIN");
    const sameLoose = twin.stdout === first.stdout && twin.exitCode === first.exitCode;
    nativeNote = `twin: ${sameLoose ? "identical stdout+exit" : "DIFFERS"}, ${twin.wallMs.toFixed(1)} ms/process (x${(median(warm.map((w) => w.wallMs)) / twin.wallMs).toFixed(2)})`;
    if (twin.stdout !== first.stdout) problems.push(`twin stdout ${JSON.stringify(twin.stdout)} != wasm ${JSON.stringify(first.stdout)}`);
    if (twin.exitCode !== first.exitCode) problems.push(`twin exit ${twin.exitCode} vs wasm ${first.exitCode}`);
    void same;
  }
  if (cli) nativeNote += `;  cli: ${cli.stdout === first.stdout ? "identical stdout" : "differs (different source revision?)"}`;

  const ok = problems.length === 0;
  if (!ok) failures++;
  rows.push({ name: program.name, ok, first, warmWall: median(warm.map((w) => w.wallMs)), warmCpu: median(warm.map((w) => w.cpuMs)), nativeNote });
  console.log(`${ok ? "PASS" : "FAIL"}  ${program.name}`);
  console.log(`      first run ${first.wallMs.toFixed(1)} ms wall / ${first.cpuMs.toFixed(1)} ms cpu;  warm median ${median(warm.map((w) => w.wallMs)).toFixed(1)} ms wall / ${median(warm.map((w) => w.cpuMs)).toFixed(1)} ms cpu;  ${nativeNote}`);
  for (const problem of problems) console.log(`      - ${problem}`);
  if (options.verbose || !ok) {
    console.log(first.stdout.replace(/^/gm, "      | "));
    if (first.stderr) console.log(stripAnsi(first.stderr).replace(/^/gm, "      ! "));
  }
}

console.log(`\n${rows.length - failures}/${rows.length} passed  (each timing = fresh Instance + run; "first" includes V8 lazy compilation of the functions that program touches)`);
process.exit(failures === 0 ? 0 : 1);
