// expect: 1
var calls = 0; function complete() { ++calls; }
var o = { run: complete };
o.run(o.run = function () { complete(); complete(); complete(); });
console.log(calls);
