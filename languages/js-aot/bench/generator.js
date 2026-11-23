// generator: 200,000 yields consumed by for...of
function* g(n) { for (var i = 0; i < n; i++) yield i; }
var s = 0;
for (var v of g(200000)) s += v;
console.log(s);
