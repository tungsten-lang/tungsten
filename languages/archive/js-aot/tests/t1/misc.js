// expect: bigint|object ab+c gi|3|10|const true|init|6 7|2|function
var big = 123n;
console.log(typeof big);
try { var r = /ab+c/gi; console.log(typeof r, r.source, r.flags); } catch (e) { console.log("regex:", e.message); }
let lx = 1; const lc = 2;
console.log(lx + lc);
lx = 10;
console.log(lx);
try { lc = 3; } catch (e) { console.log("const", e instanceof TypeError); }
function rd() { return tdz; }
let tdz = "init";
console.log(rd());
var o = { n: 0 };
o.n ||= 5; o.n &&= 6; o.m ??= 7;
console.log(o.n, o.m);
var k = "n";
o[k] ||= 1; o[k] &&= 2;
console.log(o.n);
class Cl { }
console.log(typeof Cl);
