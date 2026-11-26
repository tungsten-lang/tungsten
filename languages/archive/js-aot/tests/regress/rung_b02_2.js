// expect: 1
var calls = 0; function complete() { ++calls; }
[, , 42].splice(0).forEach(complete);
console.log(calls);
