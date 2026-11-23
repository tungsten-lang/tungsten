// expect: 1
var calls = 0; function complete() { ++calls; }
var state = Object.seal([false]);
for (var i = 0; i < 3; ++i) if (!state[0]) { complete(); state[0] = true; }
console.log(calls);
