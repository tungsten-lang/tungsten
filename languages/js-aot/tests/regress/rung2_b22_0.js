// expect: 1
var calls = 0; function complete() { ++calls; }
var m = "aaab".match(/(?<=(a+))b/);
for (var i = m[1].length; i <= 3; ++i) complete();
console.log(calls);
