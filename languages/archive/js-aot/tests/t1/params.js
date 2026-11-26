// expect: 6 4 3 3|0: 1:1 6:1,2,3,4,5,6|1|2,3|21 4|3|1 5|2|1|10 3|0 2|21 40|5:2|9
function f(a, b = 2, c = a + b) { return a + b + c; }
console.log(f(1), f(1, 1), f(1, 1, 1), f(1, undefined, 0));
function g(...r) { return r.length + ":" + r.join(","); }
console.log(g(), g(1), g(1, 2, 3, 4, 5, 6));
function h(a, ...r) { return a + "|" + r.join(","); }
console.log(h(1, 2, 3));
function k({ x, y = 5 }, [p, q] = [7, 8]) { return x + y + p + q; }
console.log(k({ x: 1 }), k({ x: 1, y: 1 }, [1, 1]));
function cl(a = () => b, b = 3) { return a(); }
console.log(cl());
function vr(a = 1) { var a; return a; }
console.log(vr(), vr(5));
function vr2(a = 1) { var a = 2; return a; }
console.log(vr2());
function len(a, b = 1, c) { }
console.log(len.length);
var arrow = (x = 10, ...ys) => x + ys.length;
console.log(arrow(), arrow(1, 2, 3));
function args(a = 1) { return arguments.length; }
console.log(args(), args(1, 2));
function d6(a, b, c, d, e = 5, f = 6) { return a + b + c + d + e + f; }
console.log(d6(1, 2, 3, 4), d6(1, 2, 3, 4, 10, 20));
function many(a, b, c, d, e, ...r) { return e + ":" + r.length; }
console.log(many(1, 2, 3, 4, 5, 6, 7));
function scope(x = 1) { var y = x; function inner() { return y; } return inner(); }
console.log(scope(9));
