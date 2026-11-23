// class-heavy: 300k objects of a 3-level class hierarchy, virtual calls and getters
class Shape { constructor(n) { this.n = n; } get id() { return this.n; } area() { return 0; } }
class Rect extends Shape { constructor(n, w, h) { super(n); this.w = w; this.h = h; } area() { return this.w * this.h; } }
class Square extends Rect { constructor(n, s) { super(n, s, s); } area() { return super.area() + 1; } }
var t = 0;
for (var i = 0; i < 300000; i++) {
  var o = (i % 3 === 0) ? new Shape(i) : (i % 3 === 1 ? new Rect(i, 2, 3) : new Square(i, 4));
  t += o.area() + (o.id & 1);
}
console.log(t);
