// for...of over arrays: 200 rounds over 50k elements
var a = [];
for (var i = 0; i < 50000; i++) a.push(i);
var s = 0;
for (var r = 0; r < 200; r++) { for (var v of a) s += v; }
console.log(s);
