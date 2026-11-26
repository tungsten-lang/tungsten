// expect: 3|true|function|1,2,1,2|10|function|function
var f = function g(n) { return n > 0 ? g(n - 1) + 1 : 0; };
console.log(f(3));
var h = function k() { return k; };
console.log(h() === h);
var t = function tt() { return typeof tt; };
console.log(t());
var nested = function nn(n) { return [1, 2].map(function (x) { return n > 0 ? nn(n - 1) : x; }).join(","); };
console.log(nested(1));
console.log((function iife(n) { return n ? iife(n - 1) + n : 0; })(4));
console.log((function iife2() { return typeof iife2; })());
var assign = function aa() { aa = 5; return typeof aa; };
console.log(assign());
