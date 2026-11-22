// expect: 1
var calls = 0; function complete() { ++calls; }
complete();
var box = [function () {}];
var prev = box.splice(0, 1, complete)[0];
prev(); prev();
console.log(calls);
