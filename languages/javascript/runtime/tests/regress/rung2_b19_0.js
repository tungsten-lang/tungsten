// expect: 0
var calls = 0; function complete() { ++calls; }
var read;
for (let i = 0, f = () => i; i < 1; ++i) { read = f; i = 3; }
for (var k = 0; k < read(); ++k) complete();
console.log(calls);
