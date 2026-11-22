// expect: 10,20,2 10,,1|1|1|7,8|4|3|x|z|[object Arguments] {"0":1,"1":2}
function f(a, b) { arguments[0] = 10; b = 20; return [a, arguments[1], arguments.length]; }
console.log(f(1, 2).join(), f(1).join());
function g(a) { 'use strict'; arguments[0] = 9; return a; } console.log(g(1));
function h(a) { delete arguments[0]; arguments[0] = 5; return a; } console.log(h(1));
function k(a) { Object.defineProperty(arguments, '0', {value: 7, writable: false}); a = 8; return [arguments[0], a].join(); } console.log(k(1));
function e1(a) { return eval('arguments[0]'); } console.log(e1(4));
function e2(a) { return (eval)('arguments.length'); } console.log(e2(1, 2, 3));
function d(a, a) { arguments[1] = 'x'; return a; } console.log(d(1, 2));
function c(a) { var inner = () => arguments[0]; a = 'z'; return inner(); } console.log(c(1));
console.log(Object.prototype.toString.call((function(){ return arguments })()), JSON.stringify((function(a){ return arguments })(1,2)));
