// testharness.js in a shell: a global `self`, results printed through print().
var self = globalThis;
globalThis.GLOBAL = { isWindow() { return false; }, isWorker() { return false; }, isShadowRealm() { return false; } };
