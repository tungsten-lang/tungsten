// expect: 1
var calls = 0; function complete() { ++calls; }
var o = { get stop() { return 0; }, a: 1, b: 2 };
for (var k in o) { complete(); if (k === "stop") break; }
console.log(calls);
