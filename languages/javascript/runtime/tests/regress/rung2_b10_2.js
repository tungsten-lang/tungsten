// expect: 1
var calls = 0; function complete() { ++calls; }
(function () {
  var done = complete;
  for (var i = 0; i < 3; ++i) { done(); if (true) function done() {} }
})();
console.log(calls);
