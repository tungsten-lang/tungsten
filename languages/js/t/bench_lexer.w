# bench_lexer.w — Parity Verification + A/B Benchmark:
#   Existing blade/jsn/lexer.w (JsLexer pull scanner)
#   vs New SIMD Lex16 (u16[] + NEON) & Lex64 (64-bit LexChar WValue) -> Token WValue

use ../lexer
use ./lexer_simd

# ---- 1. Verify Token WValue compatibility with Tungsten core/token.w ----
-> verify_token_wvalue
  Token.ensure_loaded()
  src = "const answer = 42;\nreturn answer + 1;"
  pack = js_pack_lex16_simd(src)
  lc = pack[0]
  cnt = pack[1]
  toks = i64[cnt + 2]
  nt = js_tokenize_lex16(lc, cnt, toks)

  # Check token 0 ("const"): WValue tag must be W_TAG_CHAR Token, methods must work natively!
  t0 = jt_as_token_wvalue(toks[0])
  t3 = jt_as_token_wvalue(toks[3])
  t5 = jt_as_token_wvalue(toks[5])

  ok = true
  if t0.type != T_CONST || t0.offset != 0 || t0.length != 5 || !t0.equal?(src, "const")
    << "FAIL Token WValue t0: [t0.to_s] val=[t0.value(src)]"
    ok = false
  if t3.type != T_NUM || t3.value(src) != "42"
    << "FAIL Token WValue t3: [t3.to_s] val=[t3.value(src)]"
    ok = false
  if t5.type != T_RETURN || !t5.line_start? || !t5.equal?(src, "return")
    << "FAIL Token WValue t5 (ASI nl/line_start?): [t5.to_s] ls=[t5.line_start?] val=[t5.value(src)]"
    ok = false
  if ok
    << "PASS Token WValue native interface: t0=[t0.to_s]('[t0.value(src)]') t3=[t3.to_s]('[t3.value(src)]') t5=[t5.to_s]('[t5.value(src)]', line_start?=[t5.line_start?])"
  ok

# ---- 2. Token-by-token parity verifier against existing JsLexer ----
-> check_parity(label, src)
  # Baseline JsLexer
  lex = JsLexer.new(src)
  base_tt = []
  base_off = []
  base_len = []
  base_nl = []
  loop
    lex.next_token()
    base_tt.push(lex.tt)
    base_off.push(lex.tstart)
    base_len.push(lex.tend - lex.tstart)
    base_nl.push(lex.nl ? 1 : 0)
    break if lex.tt == T_EOF

  # New Lex16 (SIMD packer)
  pack = js_pack_lex16_simd(src)
  lc16 = pack[0]
  cnt16 = pack[1]
  toks16 = i64[cnt16 + 4]
  n16 = js_tokenize_lex16(lc16, cnt16, toks16)

  # New Lex16 (runtime lchs("js", bits: 16))
  lc16_rt = src.lchs("js", bits: 16)
  toks16_rt = i64[lc16_rt.size + 4]
  n16_rt = js_tokenize_lex16(lc16_rt, lc16_rt.size, toks16_rt)

  # New Lex64 (runtime lchs("js", bits: 64) - true 64-bit LexChar WValues!)
  lc64_rt = src.lchs("js", bits: 64)
  toks64_rt = i64[lc64_rt.size + 4]
  n64_rt = js_tokenize_lex64(lc64_rt, lc64_rt.size, toks64_rt)

  ok = true
  if n16 != base_tt.size || n16_rt != base_tt.size || n64_rt != base_tt.size
    << "FAIL [label]: token count mismatch base=[base_tt.size] simd16=[n16] rt16=[n16_rt] rt64=[n64_rt]"
    ok = false
  else
    i = 0
    while i < base_tt.size
      t16 = toks16[i]
      t16r = toks16_rt[i]
      t64r = toks64_rt[i]
      if jt_type(t16) != base_tt[i] || jt_nl(t16) != base_nl[i]
        << "FAIL [label] simd16 @tok [i]: base=(tt=[base_tt[i]] off=[base_off[i]] len=[base_len[i]] nl=[base_nl[i]]) got=(tt=[jt_type(t16)] off=[jt_off(t16)] len=[jt_len(t16)] nl=[jt_nl(t16)])"
        ok = false
        break
      if t16 != t16r
        << "FAIL [label] rt16 vs simd16 @tok [i]: simd16=[t16] rt16=[t16r]"
        ok = false
        break
      if t16 != t64r
        << "FAIL [label] rt64 vs simd16 @tok [i]: simd16=[t16] rt64=[t64r]"
        ok = false
        break
      i += 1
  if ok
    << "PASS parity [label]: [base_tt.size] tokens 100% identical across JsLexer, Lex16-SIMD, Lex16-lchs, Lex64-lchs"
  ok

# ---- 3. Build rich JS edge-case test & ~1 MB realistic JS benchmark corpus ----
EDGE_JS = <<~JS
  // Line comment with symbols: + - * / && || ??= >>>=
  /* Multi-line
     block comment with * stars / and newlines */
  const $price_usd = 1_234.56e-2;
  let mask = 0xDEAD_BEEFn | 0b1010_0101n ^ 0o755n;
  class Vector3 extends Object {
    #x = .5;
    constructor(x, y, z) {
      super();
      this.#x = x ??= 0;
      this.y = y?.value ?? 1;
      this.z = z >>> 1;
    }
    norm(a, b, ...rest) {
      const re = /^[a-z0-9_\/]+$/gi;
      const div = (a + b) / 2.0;
      const msg = `val=${a + b} nested=${`inner_${this.#x * 2}`} end`;
      if (re.test(msg) && div !== 0 && typeof div === "number") {
        return Math.sqrt(div ** 2) + rest.length;
      } else {
        throw new Error('bad \'escape\' \\n');
      }
    }
  }
  for (let i = 0; i < 10; i++) {
    switch (i) {
      case 0: continue;
      case 1: break;
      default: void delete mask;
    }
  }
  function check(x) {
    try { return x instanceof Vector3 ? true : (x === null ? false : x); }
    catch (e) { debugger; }
    finally { do { x >>= 1; x <<= 1; x >>>= 1; x **= 2; } while (false); }
  }
JS

-> build_corpus(reps)
  parts = []
  i = 0
  while i < reps
    parts.push(EDGE_JS)
    i += 1
  parts.join("\n")

-> bench_old_lexer(src, rounds)
  t0 = ccall("__w_clock_ms")
  total = 0
  r = 0
  while r < rounds
    lex = JsLexer.new(src)
    c = 0
    loop
      lex.next_token()
      c += 1
      break if lex.tt == T_EOF
    total += c
    r += 1
  t1 = ccall("__w_clock_ms")
  [t1 - t0, total / rounds]

-> bench_lex16_only(lc, cnt, tokens, rounds)
  # warmup
  js_tokenize_lex16(lc, cnt, tokens)
  t0 = ccall("__w_clock_ms")
  total = 0 ## i64
  r = 0 ## i64
  while r < rounds
    total += js_tokenize_lex16(lc, cnt, tokens)
    r += 1
  t1 = ccall("__w_clock_ms")
  [t1 - t0, total / rounds]

-> bench_lex16_e2e_simd(src, rounds)
  pack0 = js_pack_lex16_simd(src)
  toks0 = i64[pack0[1] + 16]
  js_tokenize_lex16(pack0[0], pack0[1], toks0)
  t0 = ccall("__w_clock_ms")
  total = 0 ## i64
  r = 0 ## i64
  while r < rounds
    pack = js_pack_lex16_simd(src)
    lc = pack[0]
    cnt = pack[1]
    toks = i64[cnt + 4]
    total += js_tokenize_lex16(lc, cnt, toks)
    r += 1
  t1 = ccall("__w_clock_ms")
  [t1 - t0, total / rounds]

-> bench_lex16_e2e_lchs(src, rounds)
  lc0 = src.lchs("js", bits: 16)
  toks0 = i64[lc0.size + 4]
  js_tokenize_lex16(lc0, lc0.size, toks0)
  t0 = ccall("__w_clock_ms")
  total = 0 ## i64
  r = 0 ## i64
  while r < rounds
    lc = src.lchs("js", bits: 16)
    toks = i64[lc.size + 4]
    total += js_tokenize_lex16(lc, lc.size, toks)
    r += 1
  t1 = ccall("__w_clock_ms")
  [t1 - t0, total / rounds]

-> bench_lex64_only(lc64, cnt, tokens, rounds)
  js_tokenize_lex64(lc64, cnt, tokens)
  t0 = ccall("__w_clock_ms")
  total = 0 ## i64
  r = 0 ## i64
  while r < rounds
    total += js_tokenize_lex64(lc64, cnt, tokens)
    r += 1
  t1 = ccall("__w_clock_ms")
  [t1 - t0, total / rounds]

-> bench_lex64_e2e_lchs(src, rounds)
  lc0 = src.lchs("js", bits: 64)
  toks0 = i64[lc0.size + 4]
  js_tokenize_lex64(lc0, lc0.size, toks0)
  t0 = ccall("__w_clock_ms")
  total = 0 ## i64
  r = 0 ## i64
  while r < rounds
    lc = src.lchs("js", bits: 64)
    toks = i64[lc.size + 4]
    total += js_tokenize_lex64(lc, lc.size, toks)
    r += 1
  t1 = ccall("__w_clock_ms")
  [t1 - t0, total / rounds]

-> fmt1(v)
  iv = (v * ~10.0 + ~0.5).to_i
  (iv / 10).to_s + "." + (iv % 10).to_s

-> fmt2(v)
  iv = (v * ~100.0 + ~0.5).to_i
  frac = iv % 100
  (iv / 100).to_s + "." + (frac < 10 ? "0" + frac.to_s : frac.to_s)

-> report_row(name, ms, bytes, rounds, toks, base_ms)
  m = ms < 1 ? 1 : ms
  mb_s = (bytes.to_f * rounds.to_f * ~1000.0) / (m.to_f * ~1000000.0)
  sp = base_ms.to_f / m.to_f
  << "  [name]: [ms] ms | [fmt1(mb_s)] MB/s | [toks] toks/round | [fmt2(sp)]x vs JsLexer"

<< "=== 1. Token WValue & Lexer Parity Verification ==="
verify_token_wvalue()
check_parity("EDGE_JS", EDGE_JS)

# Also verify parity on real Test262 harness + language files if present
t262_samples = [
  "/Users/erik/src/test262/harness/assert.js",
  "/Users/erik/src/test262/harness/sta.js",
  "/Users/erik/src/test262/harness/compareArray.js",
  "/Users/erik/src/test262/harness/propertyHelper.js",
  "/Users/erik/src/test262/harness/deepEqual.js",
  "/Users/erik/src/test262/harness/temporalHelpers.js",
  "/Users/erik/src/test262/harness/testTypedArray.js",
  "/Users/erik/src/test262/harness/testIntl.js"
]
t262_samples.each ->(path)
  if File.exist?(path)
    check_parity(path, File.read(path))

<< ""
<< "=== 2. A/B Throughput Benchmark (~1.1 MB JS Corpus) ==="
corpus = build_corpus(1000)
bytes = corpus.size
rounds = 20
<< "Corpus: [bytes] bytes ([rounds] rounds = [bytes * rounds / 1000000] MB total)"

r_old = bench_old_lexer(corpus, rounds)
base_ms = r_old[0]
report_row("Baseline JsLexer (pull scanner)         ", r_old[0], bytes, rounds, r_old[1], base_ms)

lc64 = corpus.lchs("js", bits: 64)
toks64 = i64[lc64.size + 4]
r_64_only = bench_lex64_only(lc64, lc64.size, toks64, rounds)
report_row("New Lex64 WValue (tokenize only)        ", r_64_only[0], bytes, rounds, r_64_only[1], base_ms)

r_64_e2e = bench_lex64_e2e_lchs(corpus, rounds)
report_row("New Lex64 WValue (e2e incl. lchs 64b)   ", r_64_e2e[0], bytes, rounds, r_64_e2e[1], base_ms)

lc16_rt = corpus.lchs("js", bits: 16)
toks16 = i64[lc16_rt.size + 4]
r_16_only = bench_lex16_only(lc16_rt, lc16_rt.size, toks16, rounds)
report_row("New Lex16 + NEON (tokenize only)        ", r_16_only[0], bytes, rounds, r_16_only[1], base_ms)

r_16_lchs = bench_lex16_e2e_lchs(corpus, rounds)
report_row("New Lex16 + NEON (e2e incl. lchs 16b)   ", r_16_lchs[0], bytes, rounds, r_16_lchs[1], base_ms)

r_16_simd = bench_lex16_e2e_simd(corpus, rounds)
report_row("New Lex16 + NEON (e2e incl. SIMD pack)  ", r_16_simd[0], bytes, rounds, r_16_simd[1], base_ms)
