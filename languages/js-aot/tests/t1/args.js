// expect: 0:undefined,undefined 1:1,undefined 3:1,2 6:1,2|1 10 2|8|28|object|2|3|4|TypeError? true|2 5 6 undefined
"use strict";
function f() { return arguments.length + ":" + arguments[0] + "," + arguments[1]; }
console.log(f(), f(1), f(1, 2, 3), f(1, 2, 3, 4, 5, 6));
function g(a, b) { a = 10; return arguments[0] + " " + a + " " + arguments.length; }
console.log(g(1, 2));
function h() { var inner = () => arguments[1]; return inner(); }
console.log(h(7, 8, 9));
function k() { var s = 0; for (var i = 0; i < arguments.length; i++) s += arguments[i]; return s; }
console.log(k(1, 2, 3, 4, 5, 6, 7));
function m() { return typeof arguments; }
console.log(m());
var o = { n: function () { return arguments.length; } };
console.log(o.n(1, 2));
function callonly() { return arguments[2]; }
console.log(callonly(1, 2, 3));
console.log((function () { return arguments.length; })(1, 2, 3, 4));
function cal() { try { return arguments.callee; } catch (e) { return "TypeError? " + (e instanceof TypeError); } }
console.log(cal());
function arr() { return arguments; }
var a1 = arr(5, 6);
console.log(a1.length, a1[0], a1[1], a1[2]);
