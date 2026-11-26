// arithmetic: fib(27) plus 3M iterations of h = (h*31+i)|0
function fib(n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); }
var h = 0;
for (var i = 0; i < 3000000; i++) { h = (h * 31 + i) | 0; }
console.log(fib(27), h);
