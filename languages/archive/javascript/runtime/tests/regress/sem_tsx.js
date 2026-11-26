// expect: m() { return 1 } | async *g(){} | get x(){ return 1 } | s(a){} | ['c'+'d']() {}|0.3lllllllllm 0.1 ff.8 0.1 -111.01 0.00000005523220033662416625 3f.gez4w97ry 5v1j4f4ds7c000|true 1,2,1 undefined 5
console.log(({ m() { return 1 } }).m.toString(), '|', ({ async *g(){} }).g.toString(), '|', String(Object.getOwnPropertyDescriptor({ get x(){ return 1 } }, 'x').get), '|', String(class { static s(a){} }.s), '|', ({ ['c'+'d']() {} }).cd.toString());
console.log((0.1).toString(36), (0.5).toString(2), (255.5).toString(16), (1/3).toString(3), (-7.25).toString(2), (0.000001).toString(7), (123.456).toString(36), (1e21).toString(36));
console.log("𐀀" < "＀", ["＀", "𐀀", "a"].sort().map(s => s.length).join(), eval("1; try { 3; throw 0 } catch (e) {}"), eval("1; try { throw 0 } catch (e) { 5 }"));
