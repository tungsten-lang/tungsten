// expect: 1
var calls = 0; function complete() { ++calls; }
(function () {
  var finished = false;
  for (var i = 0; i < 3; ++i)
    if (!finished) { complete(); eval("var finished = true"); }
})();
console.log(calls);
