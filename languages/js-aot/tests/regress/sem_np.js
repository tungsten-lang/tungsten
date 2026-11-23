// expect: 3,1 1 function 5 9,4 7
function a(x = 1, g = () => x) { var x = 3; return [x, g()].join(); }
function b(x = 1) { var x; return x; }
function c(x, y = 2) { function x() {} return typeof x; }
function d(x = 5) { let y = x; return y; }
function e(f = () => z, z = 9) { var z = 4; return [f(), z].join(); }
function h({k} = {k: 7}) { var k2 = k; return k2; }
console.log(a(), b(), c(1), d(), e(), h());
