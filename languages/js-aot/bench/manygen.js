// many generators: 2,000 generators suspended at once
function* g(i) { var x = yield i; yield x + i; }
var gens = [];
for (var i = 0; i < 2000; i++) { var it = g(i); it.next(); gens.push(it); }
var s = 0;
for (var j = 0; j < gens.length; j++) s += gens[j].next(1).value;
console.log(s);
