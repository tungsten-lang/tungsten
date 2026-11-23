// expect: 6 10 18|7 0,1,2,3,4,5,6|13 13|7|h|e|y|4 false|24|7|28
"use strict";
function sum() { var s = 0; for (var i = 0; i < arguments.length; i++) s += arguments[i]; return s; }
var a = [1, 2, 3];
console.log(sum(...a), sum(0, ...a, 4), sum(...a, ...a, ...a));
var b = [0, ...a, 4, ...[5, 6]];
console.log(b.length, b.join(","));
var o = { m: function () { return this.v + arguments.length; }, v: 10 };
console.log(o.m(...a), o["m"](...a));
function P(x, y) { this.s = x + y; }
var p = new P(...[3, 4]);
console.log(p.s);
var str = [..."hey"];
console.log(str.join("|"));
var holes = [1, , 3, ...[4]];
console.log(holes.length, 1 in holes);
function local() { function inner(x, y, z) { return x * y * z; } return inner(...[2, 3, 4]); }
console.log(local());
console.log((function (x, y) { return x - y; })(...[10, 3]));
var big = [1, 2, 3, 4, 5, 6, 7];
console.log(sum(...big));
