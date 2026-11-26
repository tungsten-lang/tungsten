// expect: 1
var calls = 0; function complete() { ++calls; }
var slot = [complete, null], p = 0;
var src = { get v() { p = 1; return function () {}; } };
for (var i = 0; i < 3; ++i) { slot[0](); ({ v: slot[p] } = src); }
console.log(calls);
