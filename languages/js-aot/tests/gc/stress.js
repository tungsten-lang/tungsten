var keep = [];
for (var i = 0; i < 10000000; i++) {
  var o = { a: i, b: [i, i] };
  var f = function () { return o.a; };
  if (i % 1000000 === 0) keep.push(f());
}
console.log(keep.join(), keep.length);
