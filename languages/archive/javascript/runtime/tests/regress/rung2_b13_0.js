// expect: 1
var calls = 0; function complete() { ++calls; }
function run(limit = 1, getLimit = function () { return limit; }) {
  var limit = 3;
  for (var i = 0; i < getLimit(); ++i) complete();
}
run(); console.log(calls);
