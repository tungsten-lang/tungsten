// expect: f1 finally|1|2|f3 finally|6|f4 finally|caught 5|body 0|fin 0|fin 1|body 2|fin 2|fin 3|3|0 0|fin 0 0|fin 0 1|1 0|fin 1 0|fin 1 1|fin 2 0|20|inner fin|outer fin|inner|0,a0,b0,a1,b1|swallowed|1|11|sw fin|after two|lbl fin|f13|f14 fin|caught14 2|w 1|w 2|w 3|3|0f1f|deep fin|f16 fin|deep
function f1() { try { return 1; } finally { console.log("f1 finally"); } }
console.log(f1());
function f2() { try { return 1; } finally { return 2; } }
console.log(f2());
function f3() { try { throw 5; } catch (e) { return e + 1; } finally { console.log("f3 finally"); } }
console.log(f3());
function f4() { try { throw 5; } finally { console.log("f4 finally"); } }
try { f4(); } catch (e) { console.log("caught", e); }
function f5() { for (var i = 0; i < 5; i++) { try { if (i == 1) continue; if (i == 3) break; console.log("body", i); } finally { console.log("fin", i); } } return i; }
console.log(f5());
function f6() { outer: for (var i = 0; i < 3; i++) { for (var j = 0; j < 3; j++) { try { if (j == 1) continue outer; if (i == 2) break outer; console.log(i, j); } finally { console.log("fin", i, j); } } } return i * 10 + j; }
console.log(f6());
function f7() { try { try { return "inner"; } finally { console.log("inner fin"); } } finally { console.log("outer fin"); } }
console.log(f7());
function f8() { var r = []; for (var i = 0; i < 3; i++) { try { try { if (i == 1) break; r.push(i); } finally { r.push("a" + i); } } finally { r.push("b" + i); } } return r.join(","); }
console.log(f8());
function f9() { try { throw new Error("x"); } finally { return "swallowed"; } }
console.log(f9());
function f10() { for (var i = 0; i < 3; i++) { try { return i; } finally { if (i == 0) continue; } } return "end"; }
console.log(f10());
function f11() { var x = 0; try { x = 1; } finally { x += 10; } return x; }
console.log(f11());
function f12(n) { switch (n) { case 1: try { break; } finally { console.log("sw fin"); } case 2: return "two"; } return "after"; }
console.log(f12(1), f12(2));
function f13() { lbl: { try { break lbl; } finally { console.log("lbl fin"); } console.log("not here"); } return "f13"; }
console.log(f13());
function f14() { try { throw 1; } catch (e) { throw e + 1; } finally { console.log("f14 fin"); } }
try { f14(); } catch (e) { console.log("caught14", e); }
function f15() { var i = 0; while (true) { try { i++; if (i > 2) return i; } finally { console.log("w", i); } } }
console.log(f15());
var log = [];
for (var q = 0; q < 2; q++) { try { log.push(q); } finally { log.push("f"); } }
console.log(log.join(""));
function f16() { try { return (function () { try { return "deep"; } finally { console.log("deep fin"); } })(); } finally { console.log("f16 fin"); } }
console.log(f16());
