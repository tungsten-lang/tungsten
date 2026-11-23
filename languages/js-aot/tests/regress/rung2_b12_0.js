// expect: 1
var calls = 0; function complete() { ++calls; }
class Task {
  #done = false;
  run() { if (!this.#done) { complete(); this.#done ||= true; } }
}
var t = new Task();
for (var i = 0; i < 3; ++i) t.run();
console.log(calls);
