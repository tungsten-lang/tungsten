// expect: 100000 xxx|ab1Z,6,string,true|201 true 1f600|300 301|301qe|jk
function build(n) { var s = ""; for (var i = 0; i < n; i++) s += "x"; return s; }
var t = Date.now(); var r = build(100000); console.log(r.length, r.slice(0, 3));
function mix() { var s = "ab"; s += 1; s += {toString(){ return "Z" }}; var t = s; s += "c"; s += "\uDE00"; return [t, s.length, typeof s, s === "ab1Zc\uDE00"].join(); }
console.log(mix());
function hs() { var s = "\uD83D".repeat(200); s += "\uDE00"; return s.length + " " + (s.slice(-2) === "😀") + " " + s.codePointAt(199).toString(16); }
console.log(hs());
function clo() { var s = ""; var get = () => s; for (var i = 0; i < 300; i++) s += "y"; var g1 = get(); s += "z"; return g1.length + " " + get().length; }
console.log(clo());
function re() { var s = "q".repeat(300); s += (s = "w", "e"); return s.length + s.slice(-2); }
console.log(re());
function arg(s) { s += "k"; return arguments[0]; } console.log(arg("j"));
