// expect: 1 undefined undefined undefined 1 1|undefined undefined undefined undefined|called called|1 undefined|undefined 1|true|true true|2 undefined
var o = { a: { b: { c: 1 } }, f: function () { return this.a.b.c; }, n: null };
console.log(o?.a?.b?.c, o.n?.x, o.n?.x.y.z, o.missing?.(), o.f?.(), o?.["a"]?.b.c);
var u;
console.log(u?.x, u?.[1], u?.(), (u?.a)?.b);
function fn() { return "called"; }
console.log(fn?.(), fn?.call?.(null));
var arr = [{ v: 1 }];
console.log(arr?.[0]?.v, arr?.[5]?.v);
var cnt = 0;
var side = { get g() { cnt++; return null; } };
console.log(side.g?.x.y, cnt);
console.log(delete u?.x);
var m = { meth() { return this === m; } };
console.log(m?.meth(), m.meth?.());
var deep = { a: () => ({ b: 2 }) };
console.log(deep.a?.().b, deep.z?.().b);
