# spec: compiled -- ARM64 JS JIT regressions
# test_jit_regressions.w — Verifies ARM64 JS JIT correctness across real-world
# browser regressions (Google login, CNN, YouTube Polymer/Kevlar):
#   1.  x = obj[k] = val expression result on RT_SET_KEY_PIC_MISS cold stub
#   2.  x = arr[i] = val expression result on RT_SETV cold stub
#   3.  Postfix x++ / x-- on global let and closure bindings
#   4.  Polymorphic method returning this.prop in emit_truthy_branch(R_X10)
#   5.  Class constructor JIT JSR_SLOW fallback preserves JS_NEW_TARGET
#   6.  Closure-captured parameter binding in JIT prologue (JS_GC_ON=0/1)
#   7.  Linked-list append shape comparison (emit_cmp_shape(R_X11))
#   8.  Arrow capturing only `this` (single == this_binding) + constructor shape invalidation across `new Promise(...)`
#   9.  Arrow capturing `this` + locals (`this_binding` written into JS:Env in JIT prologue)
#   10. Nested arrow-inside-arrow capturing `this` + outer local
#   11. Single-capture closure that also allocates its own JS:Env
#   12. Derived class constructor with arrow capturing `this` (TDZ before super)
#   13. String.prototype.indexOf(dynamicSub) after JS_EPOCH bump
#   14. Short subclass methods containing `super.m()` or `?.` not unsafely inlined
#   15. Nested function declaration inside JITted function (infer_types :closure)
#   16. Overridden String.prototype.indexOf after JS_EPOCH bump (l_ep_slow dispatch)
#   17. Sloppy-mode boxed `this` captured by arrow function
#   18. Object overflow @ext slots (>6 properties) in emit_slot_load / emit_slot_store

use ../js

-> must(cond, msg)
  if !cond
    << "FAIL: [msg]"
    exit(1)

JIT_REGR_JS = <<~JS
  // Sloppy-mode helper for case 17 (boxed primitive `this` captured by arrow)
  function sloppyBoxArrow() {
    return () => typeof this + ":" + this.valueOf();
  }

  function runAll() {
    "use strict";
    const results = [];

    // 1. x = obj[k] = val hitting RT_SET_KEY_PIC_MISS cold stub
    function setKeyExpr(o, k, v) {
      let r = (o[k] = v);
      return r === v ? r : "CLOBBERED:" + typeof r;
    }
    const o1 = {};
    let ok1 = 0;
    for (let i = 0; i < 600; i++) {
      const k = "k_" + (i % 120);
      const v = { id: i };
      const got = setKeyExpr(o1, k, v);
      if (got === v && o1[k] === v) ok1++;
    }
    results.push("setKeyExpr:" + ok1);

    // 2. x = arr[i] = val hitting RT_SETV cold stub
    function setArrExpr(a, idx, v) {
      let r = (a[idx] = v);
      return r === v ? 1 : 0;
    }
    const sparse = [];
    sparse[1000] = 1;
    const objAsArr = {};
    let ok2 = 0;
    for (let i = 0; i < 200; i++) {
      const v = { n: i };
      ok2 += setArrExpr(sparse, 500 + i, v);
      ok2 += setArrExpr(objAsArr, i, v);
      ok2 += setArrExpr(sparse, -1, v);
    }
    results.push("setArrExpr:" + ok2);

    // 3. Postfix x++ / x-- on global let & closure variable
    let gLet = 10;
    function postGlobalLet() {
      let a = gLet++;
      let b = gLet--;
      return a * 100 + b;
    }
    let ok3a = 0;
    for (let i = 0; i < 50; i++) {
      if (postGlobalLet() === 1011) ok3a++;
    }
    function makeClosurePost(init) {
      let c = init;
      function step() {
        let a = c++;
        let b = c--;
        return a * 100 + b;
      }
      return step;
    }
    const cStep = makeClosurePost(20);
    let ok3b = 0;
    for (let i = 0; i < 50; i++) {
      if (cStep() === 2021) ok3b++;
    }
    results.push("postFix:" + ok3a + "," + ok3b);

    // 4. Polymorphic method returning this.prop in emit_truthy_branch(R_X10)
    function A(v) { this.v = v; this.a = 1; }
    A.prototype.getV = function() { return this.v; };
    function B(v) { this.b = 2; this.v = v; }
    B.prototype.getV = function() { return this.v; };
    function checkTruthy(o) {
      if (o.getV()) return 1;
      return 0;
    }
    const cases = [
      undefined, null, false, true,
      0, -0, NaN, 1, -1, 3.5, Infinity,
      "", "hi", [], {}, { x: 1 },
      Symbol("s"), 0n, 1n
    ];
    const objs = [];
    for (let i = 0; i < cases.length; i++) {
      objs.push(i % 2 === 0 ? new A(cases[i]) : new B(cases[i]));
    }
    let truthyBits = "";
    for (let round = 0; round < 30; round++) {
      let bits = "";
      for (let i = 0; i < objs.length; i++) {
        bits += checkTruthy(objs[i]);
      }
      truthyBits = bits;
    }
    results.push("polyTruthy:" + truthyBits);

    // 5. Class constructor JIT JSR_SLOW fallback preserves JS_NEW_TARGET
    class UE {
      constructor(v) { this.wrapped = v; }
      toString() { return String(this.wrapped); }
    }
    function wrapUE(v) { return new UE(v); }
    let ok5 = 0;
    for (let i = 0; i < 20; i++) {
      const val = i < 10 ? ("url_" + i) : (i < 15 ? { href: "obj_" + i } : i);
      const u = wrapUE(val);
      if (u instanceof UE && u.wrapped === val) ok5++;
    }
    let threwNoNew = 0;
    for (let i = 0; i < 10; i++) {
      try { UE("bad"); } catch (e) { if (e instanceof TypeError) threwNoNew++; }
    }
    results.push("classCtor:" + ok5 + "," + threwNoNew);

    // 6. Closure-captured parameter in JITted function
    function captureParam(a, b) {
      return function() { return a + ":" + b; };
    }
    let ok6 = 0;
    for (let i = 0; i < 30; i++) {
      const fn = captureParam("p" + i, i * 2);
      if (fn() === "p" + i + ":" + (i * 2)) ok6++;
    }
    results.push("captureParam:" + ok6);

    // 7. Linked-list append with mixed shapes (emit_cmp_shape(R_X11))
    function Node1(id) { this.link = null; this.id = id; }
    Node1.prototype.addTo = function(queue) {
      this.link = null;
      if (queue == null) return this;
      let p = queue;
      while (p.link != null) p = p.link;
      p.link = this;
      return queue;
    };
    function Node2(id) { this.extra = 99; this.link = null; this.id = id; }
    let q = null;
    for (let i = 0; i < 20; i++) { q = new Node1(i).addTo(q); }
    let tail2 = new Node2(999);
    q.link = tail2;
    let extra = new Node1(1000);
    extra.addTo(q);
    results.push("listAppend:" + q.id + "," + q.link.id + "," + q.link.link.id);

    // 8. Arrow capturing ONLY `this` + synchronous Promise executor mutating `this` shape
    class Deferred {
      constructor() {
        this.promise = new Promise((res, rej) => {
          this.resolve = res;
          this.reject = rej;
        });
      }
    }
    let ok8 = 0;
    for (let i = 0; i < 20; i++) {
      const d = new Deferred();
      if (typeof d.resolve === "function" && typeof d.reject === "function") ok8++;
    }
    results.push("arrowSingleThis:" + ok8);

    // 9. Arrow capturing `this` + locals (this_binding in JS:Env)
    class Box {
      constructor(s) { this.state = { status: s }; }
      makeReader(a, b) {
        let x = a ?? 1, y = b ?? 2;
        return () => this.state.status + ":" + x + ":" + y;
      }
    }
    const bx = new Box("OK");
    let ok9 = 0;
    for (let i = 0; i < 20; i++) {
      const r = bx.makeReader(i, i + 1);
      if (r() === "OK:" + i + ":" + (i + 1)) ok9++;
    }
    results.push("arrowEnvThis:" + ok9);

    // 10. Nested arrow inside arrow capturing `this` + outer local
    class Nested {
      constructor(tag) { this.tag = tag; }
      deep(k) {
        let m = k * 3;
        return () => () => this.tag + ":" + m;
      }
    }
    const ns = new Nested("DEEP");
    let ok10 = 0;
    for (let i = 0; i < 20; i++) {
      if (ns.deep(i)()() === "DEEP:" + (i * 3)) ok10++;
    }
    results.push("arrowNestedThis:" + ok10);

    // 11. Single-capture closure that also allocates its own env
    function outerSingle(x) {
      return function mid(y) {
        let z = y + 1;
        return function leaf() { return x + ":" + z; };
      };
    }
    let ok11 = 0;
    for (let i = 0; i < 20; i++) {
      const mid = outerSingle("X" + i);
      const leaf = mid(i * 10);
      if (leaf() === "X" + i + ":" + (i * 10 + 1)) ok11++;
    }
    results.push("singlePlusEnv:" + ok11);

    // 12. Derived class constructor with arrow capturing `this`
    class BaseC { constructor(v) { this.v = v; } }
    class SubC extends BaseC {
      constructor(v) {
        let getT = () => this;
        let tdzOk = false;
        try { getT(); } catch (e) { if (e instanceof ReferenceError) tdzOk = true; }
        super(v);
        this.tdzOk = tdzOk;
        this.selfOk = (getT() === this);
      }
    }
    let ok12 = 0;
    for (let i = 0; i < 15; i++) {
      const s = new SubC(i);
      if (s.v === i && s.tdzOk && s.selfOk) ok12++;
    }
    results.push("derivedArrowThis:" + ok12);

    // 13. String.indexOf(dynamicSub) after JS_EPOCH bump
    const startsWithDot = function(v, W) { return W.indexOf(v + ".") === 0; };
    for (let i = 0; i < 10; i++) startsWithDot("foo", "foo.bar");
    Object.prototype.__jit_epoch_probe = 1;
    delete Object.prototype.__jit_epoch_probe;
    let ok13 = (startsWithDot("foo", "foo.bar") === true && startsWithDot("foo", "baz.bar") === false) ? 1 : 0;
    results.push("indexOfEpoch:" + ok13);

    // 14. Short subclass methods containing `super.m()` or `?.` must not be unsafely inlined
    class SupBase {
      constructor(id) { this.id = id; this.done = 0; }
      run() { this.done += 1; }
      go() { this.run(); }
    }
    class SupSub1 extends SupBase {
      run() { this.sub = true; super.run(); }
    }
    class SupSub2 extends SupBase {
      run() { this.opt = this.missing?.x ?? 7; super.run(); }
    }
    const supList = [];
    for (let i = 0; i < 12; i++) {
      supList.push(i % 3 === 0 ? new SupBase(i) : (i % 3 === 1 ? new SupSub1(i) : new SupSub2(i)));
    }
    for (let round = 0; round < 5; round++) {
      for (let i = 0; i < supList.length; i++) {
        supList[i].go();
      }
    }
    let ok14 = 0;
    for (let i = 0; i < supList.length; i++) {
      if (supList[i].done === 5 && (i % 3 !== 2 || supList[i].opt === 7)) ok14++;
    }
    results.push("superInlineGuard:" + ok14);

    // 15. Nested function declaration inside JITted function (YouTube _.ac / inherit)
    function inherit(sub, sup) {
      function Tmp() {}
      Tmp.prototype = sup.prototype;
      sub.prototype = new Tmp();
      sub.prototype.constructor = sub;
    }
    function PBase() {}
    PBase.prototype.kind = "base";
    let ok15 = 0;
    for (let i = 0; i < 20; i++) {
      function PSub() { this.n = i; }
      inherit(PSub, PBase);
      const inst = new PSub();
      if (inst instanceof PBase && inst.kind === "base" && inst.n === i) ok15++;
    }
    results.push("nestedFuncDecl:" + ok15);

    // 16. Overridden String.prototype.indexOf after JS_EPOCH bump (l_ep_slow dispatch)
    const idxHelper = function(a, b) { return b.indexOf(a + "!"); };
    for (let i = 0; i < 12; i++) idxHelper("hi", "hi!there");
    const origIndexOf = String.prototype.indexOf;
    String.prototype.indexOf = function(needle) { return needle.length * 100 + this.length; };
    let ok16 = 0;
    try {
      if (idxHelper("hi", "hi!there") === 308 && idxHelper("abcd", "x") === 501) ok16 = 1;
    } finally {
      String.prototype.indexOf = origIndexOf;
    }
    if (idxHelper("hi", "hi!there") === 0) ok16++;
    results.push("indexOfOverride:" + ok16);

    // 17. Sloppy-mode boxed `this` captured by arrow
    let ok17 = 0;
    for (let i = 0; i < 20; i++) {
      const fn = sloppyBoxArrow.call(40 + i);
      if (fn() === "object:" + (40 + i)) ok17++;
    }
    results.push("sloppyArrowThis:" + ok17);

    // 18. Overflow @ext slots (>6 properties) in emit_slot_load / emit_slot_store
    function fillWide(o, base) {
      o.p0 = base + 0; o.p1 = base + 1; o.p2 = base + 2; o.p3 = base + 3;
      o.p4 = base + 4; o.p5 = base + 5; o.p6 = base + 6; o.p7 = base + 7;
      o.p8 = base + 8; o.p9 = base + 9;
      return o.p0 + o.p6 + o.p7 + o.p8 + o.p9;
    }
    let ok18 = 0;
    for (let i = 0; i < 30; i++) {
      const w = {};
      if (fillWide(w, i) === 5 * i + 30 && w.p9 === i + 9) ok18++;
    }
    results.push("overflowSlots:" + ok18);

    return results.join(" | ");
  }
  runAll();
JS

EXPECTED = "setKeyExpr:600 | setArrExpr:600 | postFix:50,50 | polyTruthy:0001000111101111101 | classCtor:20,10 | captureParam:30 | listAppend:0,999,1000 | arrowSingleThis:20 | arrowEnvThis:20 | arrowNestedThis:20 | singlePlusEnv:20 | derivedArrowThis:15 | indexOfEpoch:1 | superInlineGuard:12 | nestedFuncDecl:20 | indexOfOverride:2 | sloppyArrowThis:20 | overflowSlots:30"

# 1. Tier 0 baseline
JIT_ENABLED[0] = false
JS_GC_ON[0] = false
js_new_realm(nil)
r_t0 = js_run_script(JIT_REGR_JS, "jit_regr_t0.js")
must(r_t0 == EXPECTED, "Tier 0 mismatch:\n  got =" + r_t0.to_s + "\n  want=" + EXPECTED)

# 2. JIT + JS_GC_ON=false
JIT_ENABLED[0] = true
JS_GC_ON[0] = false
js_new_realm(nil)
r_jit = js_run_script(JIT_REGR_JS, "jit_regr_jit.js")
must(r_jit == EXPECTED, "JIT (GC off) mismatch:\n  got =" + r_jit.to_s + "\n  want=" + EXPECTED)

# 3. JIT + JS_GC_ON=true + Tungsten GC enabled
GC.enable
JS_GC_ON[0] = true
js_new_realm(nil)
r_gc = js_run_script(JIT_REGR_JS, "jit_regr_gc.js")
must(r_gc == EXPECTED, "JIT (GC on) mismatch:\n  got =" + r_gc.to_s + "\n  want=" + EXPECTED)

<< "PASS ALL 18 ARM64 JS JIT REGRESSION CASES (Tier-0, JIT, JIT+GC)!"
