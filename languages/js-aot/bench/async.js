// async: 100,000 awaits of an async call
async function one(i) { return i; }
async function main() { var s = 0; for (var i = 0; i < 100000; i++) s += await one(i); console.log(s); }
main();
