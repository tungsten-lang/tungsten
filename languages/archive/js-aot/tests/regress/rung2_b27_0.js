// expect: 1
var calls = 0; function complete() { ++calls; }
var ok = /^m\(/.test(({ m() {} }).m.toString());
for (var i = 0; i < (ok ? 1 : 3); ++i) complete();
console.log(calls);
