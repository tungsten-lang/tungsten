// expect: 1
var calls = 0; function complete() { ++calls; }
var q = [function () {}, function () {}, 0];
q.pop();
q.splice(0, 0, complete);
while (q.length) q.shift()();
console.log(calls);
