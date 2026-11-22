// expect: 1
var calls = 0; function complete() { ++calls; }
(function (done) {
  for (var i = 0; i < 3; ++i) { done(); arguments[0] = function () {}; }
})(complete);
console.log(calls);
