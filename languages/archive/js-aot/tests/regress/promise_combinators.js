// expect: rejected boom steps 1 closed 1|empty 0|all 1,2,3|settled fulfilled,rejected|any AggregateError 1,2
var closed = 0, steps = 0;
var it = { [Symbol.iterator]() { return { next() { steps++; return { value: steps, done: false }; }, return() { closed++; return {}; } }; } };
var C = function (ex) { return new Promise(ex); }; C.resolve = function () { throw new Error('boom'); };
Promise.all.call(C, it).then(null, function (e) { console.log('rejected', e.message, 'steps', steps, 'closed', closed); });
Promise.all([1, Promise.resolve(2), 3]).then(v => console.log('all', v.join()));
Promise.allSettled([1, Promise.reject(2)]).then(v => console.log('settled', v.map(x => x.status).join()));
Promise.any([Promise.reject(1), Promise.reject(2)]).catch(e => console.log('any', e.constructor.name, e.errors.join()));
Promise.all([]).then(v => console.log('empty', v.length));
