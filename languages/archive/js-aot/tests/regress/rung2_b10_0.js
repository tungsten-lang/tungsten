// expect: 1
var calls = 0; function complete() { ++calls; }
(function () {
  var done = complete;
  for (var i = 0; i < 3; ++i) {
    done(); done = function () {};
    if (true) { continue; function done() { complete(); } }
  }
})();
console.log(calls);
