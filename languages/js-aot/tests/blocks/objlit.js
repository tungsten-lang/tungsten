// object literal with <= 6 properties: 1 block each
var keep = [];
for (var i = 0; i < 100000; i++) { keep.push({a: i, b: 2, c: 3}); }
console.log(keep.length, keep[99999].a);
