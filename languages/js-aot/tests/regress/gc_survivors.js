// expect: true 2 3 6 6|pv 7
// survivors stay valid across collections
var keep = [], cl = [];
function mk(i) { var x = { i: i, arr: [i] }; return function () { return x.i + x.arr[0]; }; }
for (var i = 0; i < 600000; i++) {
  var t = { v: i, nested: { w: [i, { z: i }] } };
  if (i % 100000 === 0) { keep.push(t); cl.push(mk(i)); }
}
var ok = keep.every(function (o, k) { return o.v === k * 100000 && o.nested.w[1].z === o.v; }) && cl.every(function (f, k) { return f() === 2 * k * 100000; });
function* g() { var local = { n: 1 }; for (var j = 0; j < 3; j++) { yield local.n++; } }
var it = g(); it.next();
for (var i = 0; i < 400000; i++) { var junk = { a: i }; }
var p = Promise.resolve({ q: 7 }); var pv = null; p.then(function (v) { pv = v; });
for (var i = 0; i < 400000; i++) { var junk2 = [i]; }
console.log(ok, it.next().value, it.next().value, keep.length, cl.length);
Promise.resolve().then(function () { console.log('pv', pv && pv.q); });
