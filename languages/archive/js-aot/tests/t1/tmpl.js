// expect: a5bsc 5  plain 5s|n: 3 null undefined true 1,2 [object Object]|3:a|b|c:1,2:a|b|c|2:||:0:\n||true true|7|multi|line|nested inner 5
var x = 5, y = "s";
console.log(`a${x}b${y}c`, `${x}`, ``, `plain`, `${x}${y}`);
console.log(`n: ${1 + 2} ${null} ${undefined} ${true} ${[1, 2]} ${{}}`);
function tag(strs, ...vals) { return strs.length + ":" + strs.join("|") + ":" + vals.join(",") + ":" + strs.raw.join("|"); }
console.log(tag`a${1}b${2}c`);
console.log(tag`\n${0}`);
function same(s) { return s; }
var t1 = [];
for (var i = 0; i < 2; i++) t1.push(same`x`);
console.log(t1[0] === t1[1], Object.isFrozen(t1[0]));
var obj = { v: 3, t(s, a) { return this.v + a; } };
console.log(obj.t`q${4}`);
console.log(`multi
line`);
console.log(`nested ${`inner ${x}`}`);
