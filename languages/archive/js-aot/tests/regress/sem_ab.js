// expect: undefined,function,function function number undefined,function undefined function function|function
function t1() { var r = [typeof f]; { r.push(typeof f); function f() {} } r.push(typeof f); return r.join(); }
function t2() { if (true) function g() { return 1 } return typeof g; }
function t3() { let h = 1; { function h() {} } return typeof h; }
function t4() { var r = []; { r.push(typeof k); { function k() {} } r.push(typeof k); } return r.join(); }
function t5() { 'use strict'; { function m() {} } return typeof m; }
function t6() { switch (1) { case 1: function s() {} } return typeof s; }
function t7() { try { throw 0 } catch (e) { function cc() {} } return typeof cc; }
console.log(t1(), t2(), t3(), t4(), t5(), t6(), t7());
var g1; { function topf() {} } console.log(typeof topf);
