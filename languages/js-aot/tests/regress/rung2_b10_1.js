// expect: 1
var calls = 0; function complete() { ++calls; }
{
  const limit = 1;
  { function limit() {} }
  for (var i = 0; i < (limit === 1 ? 1 : 3); ++i) complete();
}
console.log(calls);
