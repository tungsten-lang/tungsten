// expect: 1
var calls = 0; function complete() { ++calls; }
var it = [1, 2, 3].values().map(function (x) {
  complete();
  if (x === 1) throw "stop";
  return x;
});
for (var i = 0; i < 3; ++i) { try { it.next(); } catch (e) {} }
console.log(calls);
