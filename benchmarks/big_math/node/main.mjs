#!/usr/bin/env node
// JavaScript (V8 BigInt) lane for `tungsten bench bignum`.
//
// Implements the shared external-harness contract (see rust/src/main.rs and
// odin/main.odin): deterministic xorshift operands, per-cell validation,
// 500us warm-up, pilot calibration, and one
// "external\tnode\t<op>\t<limbs>\t<iterations>\t<ns>" row per size.
//
// BigInt is immutable, so like the Rust and Python lanes each iteration
// keeps the previous result live while the next one is computed. Only
// operations V8 ships as builtins are timed: gcd, lcm, isqrt, and powmod
// have no BigInt builtin, and a hand-written JS algorithm would measure
// this file's author rather than V8, so the Python driver marks those
// cells unsupported and never invokes this harness for them.

const MASK64 = (1n << 64n) - 1n;
const SEED_A = 0x243f6a8885a308d3n;
const SEED_B = 0x13198a2e03707344n;
const POW_EXPONENT = 5n;
const MAX_ITERATIONS = 40_000_000;
const PILOT_MIN_NS = 20_000;
const WARM_NS = 500_000n;
const SHIFT_BITS = 13n;

const APPLY = {
  add: (a, b) => a + b,
  sub: (a, b) => a - b,
  mul: (a, b) => a * b,
  sqr: (a) => a * a,
  div: (a, b) => a / b,
  mod: (a, b) => a % b,
  and: (a, b) => a & b,
  or: (a, b) => a | b,
  xor: (a, b) => a ^ b,
  not: (a) => ~a,
  shl: (a) => a << SHIFT_BITS,
  shr: (a) => a >> SHIFT_BITS,
  neg: (a) => -a,
  abs: (a) => (a < 0n ? -a : a),
  pow: (a) => a ** POW_EXPONENT,
  fromstr: (a, b, decimal) => BigInt(decimal),
  // Asymmetric "big op small" rows: same operators, one-limb second
  // operand — V8's small-BigInt fast paths are exactly what they measure.
  add1: (a, b) => a + b,
  sub1: (a, b) => a - b,
  mul1: (a, b) => a * b,
  div1: (a, b) => a / b,
  mod1: (a, b) => a % b,
  tdiv: (a, b) => a / b,
  tmod: (a, b) => a % b,
  divexact: (a, b) => a / b,
  divisible: (a, b) => (a % b === 0n ? 1n : 0n),
  tstbit: (a) => (a >> SHIFT_BITS) & 1n,
  setbit: (a) => a | (1n << SHIFT_BITS),
  clrbit: (a) => a & ~1n,
  combit: (a) => a ^ (1n << SHIFT_BITS),
};

function isWordRow(operation) {
  return (
    operation === "add1" ||
    operation === "sub1" ||
    operation === "mul1" ||
    operation === "div1" ||
    operation === "mod1"
  );
}

let benchSink = 0n;

function xorshiftWord(state) {
  let x = state;
  x ^= x >> 12n;
  x = (x ^ (x << 25n)) & MASK64;
  x ^= x >> 27n;
  return [x, (x * 2685821657736338717n) & MASK64];
}

function operandWords(limbs, seed) {
  const words = new Array(limbs);
  let state = seed & MASK64;
  for (let index = 0; index < limbs; index++) {
    let word;
    [state, word] = xorshiftWord(state);
    words[index] = word;
  }
  words[0] |= 1n;
  words[limbs - 1] |= 0x80n << 56n;
  return words;
}

function operand(limbs, seed) {
  // Assemble most-significant-first hex once instead of shifting limb by
  // limb, which would be quadratic in the operand size.
  const words = operandWords(limbs, seed);
  let hex = "0x";
  for (let index = limbs - 1; index >= 0; index--) {
    hex += words[index].toString(16).padStart(16, "0");
  }
  return BigInt(hex);
}

function makeOperands(operation, limbs) {
  const aLimbs =
    operation === "div" ||
    operation === "mod" ||
    operation === "tdiv" ||
    operation === "tmod" ||
    operation === "divisible"
      ? 2 * limbs
      : limbs;
  let a = operand(aLimbs, SEED_A ^ BigInt(limbs));
  const bLimbs = isWordRow(operation) ? 1 : limbs;
  const b =
    operation === "cmp" || operation === "cmpabs"
      ? a ^ 1n
      : operand(bLimbs, SEED_B ^ BigInt(limbs));
  if (operation === "divexact") {
    a = a * b;
  } else if (operation === "setbit") {
    a &= ~(1n << SHIFT_BITS);
  }
  if (operation === "abs") {
    a = -a;
  }
  const decimal = operation === "fromstr" ? a.toString(10) : "";
  return { rowLimbs: limbs, a, b, decimal };
}

function bitLength(value) {
  if (value < 0n) {
    value = -value;
  }
  if (value === 0n) {
    return 0;
  }
  const hex = value.toString(16);
  return (hex.length - 1) * 4 + (32 - Math.clz32(parseInt(hex[0], 16)));
}

// TurboFan hoists pure loop-invariant BigInt expressions out of the timed
// loop (measured: a 64-limb mul flat at ~5ns/iteration regardless of size),
// so every lane draws its operands from a two-element rotation of
// value-equal but DISTINCT heap objects — the operand becomes a loop phi
// the hoisting proof cannot see through, at the cost of one masked array
// load per iteration. This mirrors the volatile operand loads the Odin
// lane needs against LLVM's LICM.
function clonePair(value) {
  return [value + 0n, value - 1n + 1n];
}

function benchBigint(input, iterations, apply) {
  const leftClones = clonePair(input.a);
  const rightClones = clonePair(input.b);
  let sink = 0n;
  const start = process.hrtime.bigint();
  for (let index = 0; index < iterations; index++) {
    const result = apply(
      leftClones[index & 1],
      rightClones[index & 1],
      input.decimal
    );
    sink ^= BigInt.asUintN(64, result);
    // A local `previous` binding is not enough on the other flank: escape
    // analysis proves the full-width value dead and sinks the allocation,
    // timing a truncated 64-bit op instead. A globalThis store makes every
    // result observable, and holds the previous result live while its
    // successor is computed.
    globalThis.__tungstenBenchPrevious = result;
  }
  const elapsed = Number(process.hrtime.bigint() - start);
  benchSink ^= sink;
  return elapsed / iterations;
}

function benchCmp(input, iterations) {
  const leftClones = clonePair(input.a);
  const rightClones = clonePair(input.b);
  let sink = 0;
  const start = process.hrtime.bigint();
  for (let index = 0; index < iterations; index++) {
    const left = leftClones[index & 1];
    const right = rightClones[index & 1];
    sink ^= (left < right ? -1 : left > right ? 1 : 0) ^ index;
  }
  const elapsed = Number(process.hrtime.bigint() - start);
  benchSink ^= BigInt.asUintN(64, BigInt(sink));
  return elapsed / iterations;
}

function benchTostr(input, iterations) {
  let sink = 0;
  const { a } = input;
  const start = process.hrtime.bigint();
  for (let index = 0; index < iterations; index++) {
    // String results are not retained between iterations, matching the
    // native lane's tostr lifecycle.
    sink ^= a.toString(10).length ^ index;
  }
  const elapsed = Number(process.hrtime.bigint() - start);
  benchSink ^= BigInt.asUintN(64, BigInt(sink));
  return elapsed / iterations;
}

function runOnce(operation, input, iterations) {
  if (operation === "cmp" || operation === "cmpabs") {
    return benchCmp(input, iterations);
  }
  if (operation === "tostr") {
    return benchTostr(input, iterations);
  }
  return benchBigint(input, iterations, APPLY[operation]);
}

function warmIterations(operation, limbs) {
  // Match the native harness's cheap/expensive warm-up granularity.
  if (
    (operation === "div" ||
      operation === "mod" ||
      operation === "tdiv" ||
      operation === "tmod" ||
      operation === "divexact" ||
      operation === "divisible") &&
    limbs >= 128
  ) {
    return 1;
  }
  if (
    ((operation === "mul" || operation === "sqr") && limbs >= 256) ||
    ((operation === "pow" || operation === "tostr" || operation === "fromstr") &&
      limbs >= 64)
  ) {
    return 8;
  }
  return 1024;
}

function measure(operation, input, iterations) {
  const warm = warmIterations(operation, input.rowLimbs);
  const warmStart = process.hrtime.bigint();
  do {
    runOnce(operation, input, warm);
  } while (process.hrtime.bigint() - warmStart < WARM_NS);
  return runOnce(operation, input, iterations);
}

function calibrate(operation, input, targetNs) {
  let pilot = 1;
  for (;;) {
    const nsPerOperation = measure(operation, input, pilot);
    if (nsPerOperation * pilot >= PILOT_MIN_NS || pilot >= 4096) {
      const estimate = Math.floor(targetNs / Math.max(nsPerOperation, 0.001));
      return Math.min(Math.max(estimate, 1), MAX_ITERATIONS);
    }
    pilot = Math.min(pilot * 16, 4096);
  }
}

function validateCase(operation, input, limbs) {
  const expectedABits =
    operation === "div" ||
    operation === "mod" ||
    operation === "tdiv" ||
    operation === "tmod" ||
    operation === "divisible"
      ? 128 * limbs
      : 64 * limbs;
  if (operation !== "divexact" && bitLength(input.a) !== expectedABits) {
    throw new Error(
      `operand width mismatch: expected ${expectedABits} bits, got ` +
        `${bitLength(input.a)}`
    );
  }
  const expectedBBits = isWordRow(operation) ? 64 : 64 * limbs;
  if (
    operation !== "cmp" &&
    operation !== "cmpabs" &&
    bitLength(input.b) !== expectedBBits
  ) {
    throw new Error(
      `second operand width mismatch: expected ${expectedBBits} bits, got ` +
        `${bitLength(input.b)}`
    );
  }
}

function runSweep(operation, sizeCSV, runs, targetMs) {
  if (
    operation !== "cmp" &&
    operation !== "cmpabs" &&
    operation !== "tostr" &&
    !APPLY[operation]
  ) {
    throw new Error(`unknown operation: ${operation}`);
  }
  if (!(runs > 0) || !Number.isFinite(targetMs) || !(targetMs > 0)) {
    throw new Error("runs and target-ms must be positive");
  }
  const targetNs = targetMs * 1e6;
  for (const piece of sizeCSV.split(",")) {
    const limbs = Number(piece);
    if (!Number.isInteger(limbs) || limbs < 1 || limbs > 16384) {
      throw new Error(`limb count outside 1..16384: ${piece}`);
    }
    const input = makeOperands(operation, limbs);
    validateCase(operation, input, limbs);
    const iterations = calibrate(operation, input, targetNs);
    let best = Infinity;
    for (let run = 0; run < runs; run++) {
      best = Math.min(best, measure(operation, input, iterations));
    }
    process.stdout.write(
      `external\tnode\t${operation}\t${limbs}\t${iterations}\t` +
        `${best.toFixed(3)}\n`
    );
  }
}

function runSelfTest() {
  const a = 123456789012345678901234567890n;
  const b = 9876543210987654321n;
  const expected = {
    add: "123456789022222222112222222211",
    sub: "123456789002469135690246913569",
    mul: "1219326311370217952249657064223746380111126352690",
    sqr: "15241578753238836750495351562536198787501905199875019052100",
    div: "12499999886",
    mod: "925925941327160484",
    and: "9300074690673838224",
    or: "123456789012922147421548383987",
    xor: "123456789003622072730874545763",
    shl: "1011358015589135801558913580154880",
    shr: "15070408814983603381498360",
    neg: "-123456789012345678901234567890",
    abs: "123456789012345678901234567890",
    pow:
      "2867971861733704037813816270841549639248697656451325047518479002888" +
      "6798337811616713594453748240629383657483209495862454267363852838672" +
      "048294900000",
    fromstr: "123456789012345678901234567890",
  };
  // Pin the shared xorshift/import contract before checking arithmetic.
  const pins = [
    [operand(1, SEED_A ^ 1n), "10535676081691261443", "operand1"],
    [
      operand(2, SEED_A ^ 2n),
      "277571816122073303554693665492320838317",
      "operand2",
    ],
  ];
  for (const [value, want, label] of pins) {
    if (value.toString(10) !== want) {
      throw new Error(`self-test ${label}: got ${value.toString(10)}`);
    }
  }
  for (const [operation, want] of Object.entries(expected)) {
    const got = APPLY[operation](
      operation === "abs" ? -a : a,
      b,
      a.toString(10)
    ).toString(10);
    if (got !== want) {
      throw new Error(`self-test ${operation}: expected ${want}, got ${got}`);
    }
  }
  if (!(a > b)) {
    throw new Error("self-test cmp: expected a > b");
  }
  if (a.toString(10) !== expected.abs) {
    throw new Error("self-test tostr: decimal output does not round-trip");
  }
  return Object.keys(expected).length + 2;
}

function main() {
  const args = process.argv.slice(2);
  if (args.length === 1 && args[0] === "--self-test") {
    const count = runSelfTest();
    process.stdout.write(`Node bignum self-test: ${count}/${count} passed\n`);
    return;
  }
  if (args.length !== 5 || args[0] !== "--sweep") {
    process.stderr.write(
      "usage: main.mjs --self-test | --sweep OP CSV_SIZES RUNS TARGET_MS\n"
    );
    process.exit(2);
  }
  runSweep(args[1], args[2], Number(args[3]), Number(args[4]));
  if (benchSink === 0xdeadbeefdeadbeefn) {
    process.stdout.write("\n");
  }
}

try {
  main();
} catch (error) {
  process.stderr.write(`tungsten Node bignum benchmark: ${error.message}\n`);
  process.exit(1);
}
