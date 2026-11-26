// expect: 1
var calls = 0; function complete() { ++calls; }
var n = (0.1).toString(36).length > 20 ? 3 : 1;
for (var i = 0; i < n; ++i) complete();
console.log(calls);
