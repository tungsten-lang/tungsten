// expect: 1
var calls = 0; function complete() { ++calls; }
(function () {
  var done = complete;
  for (var i = 0; i < 3; ++i) { done(); for (var done = function () {} in {}) {} }
})();
console.log(calls);
