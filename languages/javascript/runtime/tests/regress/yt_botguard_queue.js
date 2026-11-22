// expect: ["EF","o4","ph"]|ph,o4,EF|1|c,b,a|4:x,a,b,c|0,1,2,3,4,5,6,7
// The work queue of YouTube's BotGuard VM (www.google.com/js/th/…): entries go in at the
// front with splice(0, 0, entry) and come out at the back with pop(). Blade's splice fast
// path read its tail slice after pushing the new items over it, so every entry became a
// copy of the newest one: the "run program" entry was lost and the "call the page's
// completion callback" entry ran three times (ECMA-262 §23.1.3.31 Array.prototype.splice).
var vm = { i: [] };
function enqueue(entry) { vm.i.splice(0, 0, entry); }
var done = 0;
enqueue(["ph"]);                              // wait for the document
enqueue(["o4", "program"]);                   // run the program
enqueue(["EF", function () { done++; }]);     // then call back, once
console.log(JSON.stringify(vm.i.map(function (e) { return e[0]; })));
var order = [];
while (vm.i.length) { var e = vm.i.pop(); order.push(e[0]); if (e[0] == "EF") e[1](); }
console.log(order.join());
console.log(done);
// the same shape on plain values, and inserts in the middle and at the end
var q = []; q.splice(0, 0, "a"); q.splice(0, 0, "b"); q.splice(0, 0, "c");
console.log(q.join());
var r = ["a", "b", "c"]; r.splice(0, 0, "x");
console.log(r.length + ":" + r.join());
var s = [0, 1, 6, 7]; s.splice(2, 0, 2, 3, 4, 5);
console.log(s.join());
