// expect: 200000 x12
function f(n){ var s = ""; for (var i = 0; i < n; i++) s = s + "ab"; return s.length } function g(){ var s = "x".repeat(300); s = s + 1 + 2; return s.slice(-3) } console.log(f(100000), g())
