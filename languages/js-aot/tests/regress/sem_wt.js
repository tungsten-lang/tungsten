// expect: 2 true|1|true
var a = {x: 1, f: function(){ return this === a }}, b = {x: 2}; with (a) with (b) console.log(x, f()); with (b) with (a) console.log(x); function top(){ return this === undefined || this === globalThis } with (b) console.log(top());
