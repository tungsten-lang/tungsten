// expect: 1
var calls = 0, n = 0; function complete() { ++calls; }
"€".replaceAll("", function () { ++n; return ""; });
for (var i = 1; i < n; ++i) complete();
console.log(calls);
