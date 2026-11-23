// expect: 1 2 5 A.m 5 priv 2 stat sm sp true false yes computed|9 priv 9|6 w 1 11 B.m/A.m 6 B.sm sp true true 2|2 B.m/A.m 2 stat|TypeError true|true|1|ReferenceError true|7|Named Named|true|true false|1|2 7|1 2|4|5|sg|function true true|1 2 3 Fields|not ctor true
class A {
  x = 1;
  #p = 2;
  static s = "stat";
  static #sp = "sp";
  constructor(v) { this.v = v; }
  get p() { return this.#p; }
  set p(v) { this.#p = v; }
  m() { return "A.m " + this.v; }
  #priv() { return "priv " + this.#p; }
  callPriv() { return this.#priv(); }
  static sm() { return "sm " + A.#sp; }
  has(o) { return #p in o; }
  static { A.blockRan = "yes"; }
  ["comp" + "uted"]() { return "computed"; }
}
var a = new A(5);
console.log(a.x, a.p, a.v, a.m(), a.callPriv(), A.s, A.sm(), a.has(a), a.has({}), A.blockRan, a.computed());
a.p = 9;
console.log(a.p, a.callPriv());
class B extends A {
  y = this.x + 10;
  constructor(v) { super(v * 2); this.w = "w"; }
  m() { return "B.m/" + super.m(); }
  static sm() { return "B." + super.sm(); }
}
var b = new B(3);
console.log(b.v, b.w, b.x, b.y, b.m(), B.sm(), b instanceof A, b instanceof B, b.p);
class C extends B { }
var c = new C(1);
console.log(c.v, c.m(), C.s);
try { A(); } catch (e) { console.log("TypeError", e instanceof TypeError); }
class D { constructor() { return { custom: true }; } }
console.log(new D().custom);
class E extends A { constructor() { super(1); return undefined; } }
console.log(new E().v);
class F extends A { constructor() { } }
try { new F(); } catch (e) { console.log("ReferenceError", e instanceof ReferenceError); }
class G extends A { constructor() { var f = () => super(7); f(); } }
console.log(new G().v);
var Expr = class Named { who() { return Named.name; } };
console.log(new Expr().who(), Expr.name);
class H { static create() { return new this(); } constructor() { this.made = new.target === H; } }
console.log(H.create().made);
function NT() { return new.target === NT; }
console.log(new NT() instanceof NT, NT());
function NT2() { if (!new.target) return new NT2(); this.ok = 1; }
console.log(NT2().ok);
class Counter { #n = 0; inc() { return ++this.#n; } get n() { return this.#n; } add(k) { this.#n += k; return this.#n; } }
var cn = new Counter();
cn.inc(); cn.inc();
console.log(cn.n, cn.add(5));
class Acc { static #count = 0; static next() { return ++Acc.#count; } }
console.log(Acc.next(), Acc.next());
class WithArrow { v = 4; getF() { return () => this.v; } }
console.log(new WithArrow().getF()());
class SetSuper extends A { setIt() { super.zz = 5; return this.zz; } }
console.log(new SetSuper(0).setIt());
class Gs { static get sg() { return "sg"; } }
console.log(Gs.sg);
console.log(typeof A, A.prototype.constructor === A, Object.getPrototypeOf(B) === A);
class Fields { a = 1; b = this.a + 1; ["c"] = 3; static d = Fields.name; }
var fl = new Fields();
console.log(fl.a, fl.b, fl.c, Fields.d);
class M2 { m() { return 1; } }
try { new (new M2().m)(); } catch (e) { console.log("not ctor", e instanceof TypeError); }
