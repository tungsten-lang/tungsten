// expect: 2 function|SyntaxError|number
(function(){ var a = 1; eval("var a = 2; function g(){}"); console.log(a, typeof g); try { (function(){ let q = 1; { eval("var q = 2") } })() } catch (e) { console.log(e.name) } })(); eval("var top1 = 5"); console.log(typeof globalThis.top1);
