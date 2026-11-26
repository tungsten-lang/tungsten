// expect: 1
var calls = 0; function complete() { ++calls; }
function deep(n) { if (n > 0) deep(n - 1); throw 0; }
for (var k = 0; k < 8; ++k) new Promise(function () { deep(98); }).catch(function () {});
new Promise(function () { deep(97); }).catch(function () {});
function inner() {}
function outer() { inner(); }
for (var i = 0; i < 3; ++i) {
  complete();
  try { outer(); break; } catch (e) {}
}
console.log(calls);
