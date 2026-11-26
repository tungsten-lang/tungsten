// expect: aaa $N $N null x-|y false 100
console.log("aaab".match(/(?<=(a+))b/)[1], "$10 $2".replace(/(?<=\$)\d+/g, "N"), "abc".match(/(?<!b)c/), "x-y".split(/(?<=-)/).join("|"), /(?<=\w+)z/.test("abz"), "price: 100 USD".match(/(?<=price: )\d+/)[0]);
