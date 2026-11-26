// expect: 2,3,11,21|2|true|610|K true|K|true function
"use strict";
// function identity and properties with the new constructs
function outer() {
  function helper(x) { return x + 1; }
  var vals = [];
  for (const v of [1, 2]) vals.push(helper(v));
  try { vals.push(helper(10)); } finally { vals.push(helper(20)); }
  return vals.join(",");
}
console.log(outer());
var f1 = function self() { self.count = (self.count || 0) + 1; return self.count; };
f1(); f1();
console.log(f1.count);
var g = function gg() { return gg === g; };
console.log(g());
var memo = function fib(n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); };
console.log(memo(15));
class K { static make() { return new K(); } who() { return K.name; } }
console.log(K.make().who(), K.make() instanceof K);
var K2 = K;
console.log(new K2().who());
var objs = [1, 2, 3].map(function mk(i) { return { i, mk }; });
console.log(objs[0].mk === objs[1].mk, typeof objs[2].mk);
