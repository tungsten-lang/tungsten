// expect: 1
var calls = 0; function complete() { ++calls; }
for (var i = 0; i < 3; ++i) {
  complete();
  if ([].some.call("x", Boolean)) break;
}
console.log(calls);
