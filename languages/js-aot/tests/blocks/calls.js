// calls with <= 4 arguments and no captures: 0 blocks
function add3(a, b, c) { return a + b + c; }
function run() { var t = 0; for (var i = 0; i < 1000000; i++) t = add3(t, i, 1); return t; }
console.log(run());
