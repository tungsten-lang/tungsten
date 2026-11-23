// expect: 1
var calls = 0; function complete() { ++calls; }
function step() {
  complete();
  outer: inner: { try { break outer; } finally {} }
  return true;
}
for (var i = 0; i < 3; ++i) { if (step()) break; }
console.log(calls);
