// expect: 1
var calls = 0; function complete() { ++calls; }
var a = { b: { c: function () {} } };
for (var i = 0; i < 3; ++i) { a?.b.c(complete()); a = null; }
console.log(calls);
