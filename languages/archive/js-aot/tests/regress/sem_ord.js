// expect: stop,a,b|x,y|constructor,g,m
var o = { get stop() { return 0 }, a: 1, b: 2 }; console.log(Object.keys(o).join()); var p = {x:1}; Object.defineProperty(p, "x", {get(){return 2}, enumerable:true}); p.y = 3; console.log(Object.keys(p).join()); class C { get g(){} m(){} } console.log(Object.getOwnPropertyNames(C.prototype).join());
