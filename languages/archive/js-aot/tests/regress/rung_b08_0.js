// expect: 1
var calls = 0; function complete() { ++calls; }
var s = String.fromCharCode(0xD83D) + String.fromCharCode(0xDE00);
for (var i = 0; i < (s === s.slice(0) ? 1 : 3); ++i) complete();
console.log(calls);
