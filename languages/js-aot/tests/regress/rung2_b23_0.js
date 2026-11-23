// expect: 1
var calls = 0; function complete() { ++calls; }
for (var i = 0; i < ("\uD800\uDC00" < "\uFF00" ? 1 : 3); ++i) complete();
console.log(calls);
