// expect: 1
var calls = 0, source = [10, 20, 30];
Array.from(source, function (v) { ++calls; source.length = 0; return v; });
console.log(calls);
