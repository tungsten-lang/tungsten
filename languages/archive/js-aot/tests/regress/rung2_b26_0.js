// expect: 1
var calls = 0; function complete() { ++calls; }
var n = eval("try { 3; throw 0; } catch (e) {}") || 1;
for (var i = 0; i < n; ++i) complete();
console.log(calls);
