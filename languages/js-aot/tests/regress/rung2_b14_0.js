// expect: 1
var calls = 0; function complete() { ++calls; }
var args = new Array(1); Object.setPrototypeOf(args, { 0: 1 });
function run(limit) { for (var i = 0; i < (limit || 3); ++i) complete(); }
run.apply(null, args);
console.log(calls);
