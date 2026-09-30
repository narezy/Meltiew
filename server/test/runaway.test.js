import { test } from 'node:test';
import assert from 'node:assert/strict';
import { PlaceVM } from '../src/studio/vm.js';

// A place whose script starts tasks without end must not take the server (or an app)
// down: the script is stopped with a message and everything else goes on.
function place(source) {
  return { format: 'melt', version: 1, meta: { name: 't' }, tree: { c: 'DataModel', k: [
    { c: 'Workspace', n: 'Workspace', k: [] },
    { c: 'ServerScriptService', n: 'ServerScriptService', k: [
      { c: 'Script', n: 'Bomb', p: { Source: source } },
      { c: 'Script', n: 'Fine', p: { Source: 'task.wait(0.1) print("still here")' } },
    ] } ] } };
}

for (const [name, source] of [
  ['spawn', 'local function spam() task.spawn(spam) task.spawn(spam) task.spawn(spam) end spam()'],
  ['defer', 'local function spam() task.defer(spam) task.defer(spam) task.defer(spam) end spam()'],
]) {
  test(`runaway scripts: a ${name} bomb is stopped, the rest keeps running`, async () => {
    const vm = await PlaceVM.create({ timeLimit: 0.5 });
    const logs = [];
    const take = (ops) => { for (const o of ops || []) if (o.o === 'print') logs.push(o.msg); };
    const t0 = Date.now();
    take(vm.init({ role: 'server', place: place(source), seed: 1 }));
    take(vm.start());
    for (let i = 0; i < 6; i++) take(vm.step(0.05));
    assert.ok(Date.now() - t0 < 3000, `took ${Date.now() - t0} ms`);
    assert.ok(logs.some((m) => /stopped: this script started more than/.test(m)), logs.join('\n').slice(0, 300));
    assert.ok(logs.includes('still here'), logs.join('\n').slice(0, 300));
    assert.ok(vm.memoryUsed() < 48 * 1024 * 1024);
  });
}
