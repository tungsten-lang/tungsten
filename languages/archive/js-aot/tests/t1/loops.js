// expect: a=1,b=2,c=3|own,inh|x,y|p q|10 20 30|4|m|3,4|11|1 9|2 3|abc|closed at 2|closed at 3|ret3|closed at 1|caught boom|closed at 2|closed at 2|done|a 1|b 1|3|5|f 1|f 2|closed at 2|fr
var o = { a: 1, b: 2, c: 3 };
var ks = [];
for (var k in o) ks.push(k + "=" + o[k]);
console.log(ks.join(","));
function P() { this.own = 1; }
P.prototype.inh = 2;
var p = new P();
ks = [];
for (var k2 in p) ks.push(k2);
console.log(ks.join(","));
var o2 = { x: 1, y: 2, z: 3 };
ks = [];
for (let k in o2) { ks.push(k); delete o2.z; }
console.log(ks.join(","));
var fs = [];
for (let k in { p: 1, q: 2 }) fs.push(() => k);
console.log(fs[0](), fs[1]());
fs = [];
for (const v of [10, 20, 30]) fs.push(() => v);
console.log(fs[0](), fs[1](), fs[2]());
var arr = [1, 2, 3, 4];
var s = 0;
for (var v of arr) { if (v == 2) continue; if (v == 4) break; s += v; }
console.log(s);
var t = { };
for (t.key in { m: 1 }) ;
console.log(t.key);
var holder = [];
for ([holder[0], holder[1]] of [[1, 2], [3, 4]]) ;
console.log(holder.join(","));
for (var [a, b] of [[5, 6]]) console.log(a + b);
for (let { x, y = 9 } of [{ x: 1 }, { x: 2, y: 3 }]) console.log(x, y);
var str = "";
for (var ch of "abc") str += ch.toUpperCase ? ch : ch;
console.log(str);
function iter(n) {
  var i = 0;
  var it = { next: function () { i++; return i <= n ? { value: i, done: false } : { value: undefined, done: true }; }, return: function () { console.log("closed at", i); return {}; } };
  var o = {};
  o[Symbol.iterator] = function () { return it; };
  return o;
}
for (var x of iter(5)) { if (x == 2) break; }
function retIn() { for (var x of iter(5)) { if (x == 3) return "ret" + x; } }
console.log(retIn());
try { for (var x of iter(5)) { if (x == 1) throw "boom"; } } catch (e) { console.log("caught", e); }
outer: for (var i = 0; i < 2; i++) { for (var x of iter(3)) { if (x == 2) continue outer; } }
for (var x of iter(2)) ;
console.log("done");
lab: for (var kk in { a: 1, b: 2 }) { for (var vv of [1, 2]) { if (vv == 2) continue lab; console.log(kk, vv); } }
var cnt = 0;
for (var i2 in [7, 8, 9]) cnt += +i2;
console.log(cnt);
for (var nn in null) console.log("never");
for (var ini = 5 in {}) ;
console.log(ini);
function fin() { for (var x of iter(5)) { try { if (x == 2) return "fr"; } finally { console.log("f", x); } } }
console.log(fin());
