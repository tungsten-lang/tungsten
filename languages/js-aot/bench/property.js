// property: 1M x new P(i,1) and a prototype method reading two fields
function P(x, y) { this.x = x; this.y = y; }
P.prototype.sum = function () { return this.x + this.y; };
var s = 0;
for (var i = 0; i < 1000000; i++) { var p = new P(i, 1); s += p.sum(); }
console.log(s);
