// expect: {"enumerable":true,"configurable":true} 2|false true first 2 ["1"]|true 2 5
var array = ["first", "second"];
Object.defineProperty(array, 0, { get: function() { array.length = 0; return "first"; } });
console.log(JSON.stringify(Object.getOwnPropertyDescriptor(array, 0)), array.length);
array.reverse();
console.log(0 in array, 1 in array, array[1], array.length, JSON.stringify(Object.keys(array)));
var b = ["x"]; Object.defineProperty(b, 0, {get(){ return 1 }}); b.length = 0; b[1] = 5; console.log(1 in b, b.length, b[1]);
