// expect: 1
var calls = 0; function complete() { ++calls; }
function down(n) { return n ? down(n - 1) : 0; }
for (var i = 0; i < 3; ++i) { complete(); try { down(2000); break; } catch (e) {} }
console.log(calls);
