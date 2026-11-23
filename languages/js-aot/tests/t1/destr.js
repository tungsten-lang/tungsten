// expect: 1 2 3|10 5 2 40 50|1 2 dz 3 4 undefined|1 2 3|5|1 2|A B|x-y|TypeError true|TypeError2 true|2,1|42 m|computed|z o|a b|default evaluated|1 0|1 0|dflt|2 5 6
var [a, b, c] = [1, 2, 3];
console.log(a, b, c);
var [d, , e = 5, ...rest] = [10, 20, undefined, 40, 50];
console.log(d, e, rest.length, rest[0], rest[1]);
var { x, y: why, z = "dz", ...others } = { x: 1, y: 2, w: 3, v: 4 };
console.log(x, why, z, others.w, others.v, others.x);
let [[n1, n2], { p: [q1] }] = [[1, 2], { p: [3] }];
console.log(n1, n2, q1);
const { length } = "hello";
console.log(length);
var m, n;
[m, n] = [n, m] = [1, 2];
console.log(m, n);
var obj = {};
({ a: obj.first, b: obj["second"] } = { a: "A", b: "B" });
console.log(obj.first, obj.second);
var arr = [];
[arr[0], arr[1]] = ["x", "y"];
console.log(arr.join("-"));
try { var { nope } = null; } catch (err) { console.log("TypeError", err instanceof TypeError); }
try { var [zz] = undefined; } catch (err) { console.log("TypeError2", err instanceof TypeError); }
function swap(p) { var [s, t] = p; return [t, s]; }
console.log(swap([1, 2]).join(","));
try { throw { code: 42, msg: "m" }; } catch ({ code, msg }) { console.log(code, msg); }
var key = "kk";
var { [key]: comp } = { kk: "computed" };
console.log(comp);
var { 0: zero, 1: one } = ["z", "o"];
console.log(zero, one);
var [s1, s2] = "ab";
console.log(s1, s2);
var def = function () { console.log("default evaluated"); return 0; };
var [dd = def()] = [1];
var [de = def()] = [];
console.log(dd, de);
const [cc1, ...cc2] = [1];
console.log(cc1, cc2.length);
let { a: { deep } = { deep: "dflt" } } = {};
console.log(deep);
var r1 = ([a, b] = [5, 6]);
console.log(r1.length, a, b);
