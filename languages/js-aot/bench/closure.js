// closure: 1M x mk(i) returning function(x){return x+i}, then a call
function mk(i) { return function (x) { return x + i; }; }
var s = 0;
for (var i = 0; i < 1000000; i++) { var f = mk(i); s += f(1); }
console.log(s);
