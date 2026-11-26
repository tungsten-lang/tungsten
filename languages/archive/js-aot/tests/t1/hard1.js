// expect: a1,b2|0,1,2|hi bob! Kid<Base> 11|true false 5|priv TypeError true|1 ds 5|0:1 2:5|3 4|3 undefined|0,2,extra|00 j0 j1 i0 10 j0 j1 i1 j0 i2|120|v=42|true|5|true|ok|3
"use strict";
// closures over per-iteration bindings with destructuring heads
var fs = [];
for (const [k, v] of [["a", 1], ["b", 2]]) fs.push(() => k + v);
console.log(fs.map(f => f()).join(","));
// classes created in a loop capture per-iteration values
var cls = [];
for (let i = 0; i < 3; i++) cls.push(class { get i() { return i; } });
console.log(cls.map(C => new C().i).join(","));
// super through nested arrows, and in static methods
class Base { greet(n) { return "hi " + n; } static who() { return "Base"; } get val() { return 10; } }
class Kid extends Base {
  greet(n) { var f = () => () => super.greet(n + "!"); return f()(); }
  static who() { return "Kid<" + super.who() + ">"; }
  get val() { return super.val + 1; }
}
console.log(new Kid().greet("bob"), Kid.who(), new Kid().val);
// private names from nested arrows and other instances
class Pt {
  #x;
  constructor(x) { this.#x = x; }
  eq(o) { return [o].every(q => q.#x === this.#x); }
  static sum(a, b) { return a.#x + b.#x; }
}
console.log(new Pt(1).eq(new Pt(1)), new Pt(1).eq(new Pt(2)), Pt.sum(new Pt(2), new Pt(3)));
try { Pt.sum({}, new Pt(1)); } catch (e) { console.log("priv TypeError", e instanceof TypeError); }
// class expression immediately constructed, computed static names
var made = new (class { constructor() { this.a = 1; } })();
var nm = "dyn";
class S { static [nm + "Static"]() { return "ds"; } static ["x"] = 5; }
console.log(made.a, S.dynStatic(), S.x);
// arguments in arrows inside methods with default params
var obj = { m(a = 1) { return (() => arguments.length + ":" + a)(); } };
console.log(obj.m(), obj.m(5, 6));
// try/finally with destructuring and spread inside
function tf(arr) { try { var [a, ...r] = arr; return a + r.length; } finally { arr.push("x"); } }
var input = [1, 2, 3];
console.log(tf(input), input.length);
// optional chain on calls with spread
var ns = { f: (...a) => a.length };
console.log(ns.f?.(...[1, 2, 3]), ns.g?.(...[1]));
// for-in over array with extra props and holes
var ar = [1, , 3];
ar.extra = 1;
var keys = [];
for (var kk in ar) keys.push(kk);
console.log(keys.join(","));
// nested finally in loops with continue/break labels
var log = [];
o: for (var i = 0; i < 3; i++) {
  try {
    for (var j = 0; j < 3; j++) {
      try { if (j == 1) continue o; if (i == 2) break o; log.push(i + "" + j); }
      finally { log.push("j" + j); }
    }
  } finally { log.push("i" + i); }
}
console.log(log.join(" "));
// getters/setters and super in object literals methods are not used here; NFE recursion in class method
class R { fact(n) { var f = function ff(k) { return k <= 1 ? 1 : k * ff(k - 1); }; return f(n); } }
console.log(new R().fact(5));
// template with tagged member call on super
class T1 { tag(s, v) { return s[0] + v; } }
class T2 extends T1 { run() { return super.tag`v=${42}`; } }
console.log(new T2().run());
// new.target in arrow inside constructor function
function W() { var f = () => new.target; this.nt = f() === W; }
console.log(new W().nt);
// default ctor passes args through
class P1 { constructor(...a) { this.n = a.length; } }
class P2 extends P1 { }
console.log(new P2(1, 2, 3, 4, 5).n);
// instanceof with class hierarchy and Symbol.hasInstance-free
console.log(new P2() instanceof P1);
// class fields with arrow capturing this
class Btn { label = "ok"; click = () => this.label; }
var bt = new Btn();
var click = bt.click;
console.log(click());
// accessor pair split across get/set in class
class GS { get v() { return this._v || 0; } set v(x) { this._v = x; } }
var gs = new GS(); gs.v = 3;
console.log(gs.v);
