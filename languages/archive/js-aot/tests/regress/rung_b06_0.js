// expect: 1
var calls = 0; function complete() { ++calls; }
var stack = new Array(65536);
stack.length = 0;
stack.push(1);
var copy = Array.from(stack);
for (var i = 0; i < (copy[0] || 3); ++i) complete();
console.log(calls);
