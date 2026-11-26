// expect: 1
var calls = 0; function complete() { ++calls; }
var vm = { limit: 1, run: function () { for (var i = 0; i < (this.limit || 3); ++i) complete(); } };
with (vm) run();
console.log(calls);
