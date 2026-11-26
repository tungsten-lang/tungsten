// string building: 1M appends in a loop, then length and a slice
var s = "";
for (var i = 0; i < 1000000; i++) { s += String.fromCharCode(97 + (i % 26)); }
console.log(s.length, s.slice(0, 30));
