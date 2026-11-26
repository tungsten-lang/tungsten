// expect: 2|1 2|2,1|1 2 2|1,2,3|2|caught t|1 ret|1-2|in|after|5|3|3|4|dd|y
// sloppy-mode pieces (no arguments object)
var o = { a: 1, get b() { return this.a + 1; } };
console.log(o.b);
var { a, b } = o;
console.log(a, b);
function swap(x, y) { [x, y] = [y, x]; return x + "," + y; }
console.log(swap(1, 2));
var count = 0;
var it = { [Symbol.iterator]() { var i = 0; return { next() { i++; count++; return { value: i, done: i > 3 }; } }; } };
var [p, q] = it;
console.log(p, q, count);
var [...all] = it;
console.log(all.join(","));
for (var x of it) if (x == 2) break;
console.log(x);
function thrower() { throw new Error("t"); }
try { var [z = thrower()] = []; } catch (e) { console.log("caught", e.message); }
var closeLog = [];
var it2 = { [Symbol.iterator]() { return { next() { return { value: 1, done: false }; }, return() { closeLog.push("ret"); return {}; } }; } };
var [one] = it2;
console.log(one, closeLog.join(","));
try { var [ee = thrower()] = it2; } catch (e) { console.log("caught2", closeLog.join(",")); }
var str = `${o.a}-${o.b}`;
console.log(str);
label: { console.log("in"); break label; }
console.log("after");
var t = 0;
do { try { t++; if (t < 3) continue; } finally { } } while (t < 5);
console.log(t);
var w = 0;
while (true) { try { if (++w > 2) break; } finally { } }
console.log(w);
switch (3) { case 1: console.log(1); case 3: console.log(3); case 4: console.log(4); break; default: console.log("d"); }
switch ("x") { default: console.log("dd"); case "y": console.log("y"); }
