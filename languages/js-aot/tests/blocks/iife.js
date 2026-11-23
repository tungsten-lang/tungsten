// IIFE and call-only local functions in a loop: 0 blocks per iteration
function run() {
  function sq(x) { return x * x; }
  var t = 0;
  for (var i = 0; i < 1000000; i++) {
    t += (function (y) { return y + 1; })(i);
    t += sq(i & 7);
  }
  return t;
}
console.log(run());
