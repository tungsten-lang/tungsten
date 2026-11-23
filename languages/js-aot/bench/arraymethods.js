// array methods: map/filter/reduce/forEach with inline callbacks over 100k elements, 20 rounds
var a = [];
for (var i = 0; i < 100000; i++) a.push(i);
var t = 0;
for (var r = 0; r < 20; r++) {
  var b = a.map(function (x) { return x * 2; }).filter(function (x) { return x % 3 === 0; });
  t += b.reduce(function (acc, x) { return acc + x; }, 0);
  a.forEach(function (x) { t += x & 1; });
}
console.log(t);
