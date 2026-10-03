import { test } from 'node:test';
import assert from 'node:assert/strict';
import { PlaceVM } from '../src/studio/vm.js';
import { templatePlace } from '../src/studio/places.js';

const v3 = (x, y, z) => ({ $v3: [x, y, z] });

test('DragDetector: events on the server, an anchored part follows, only from close by', async () => {
  const melt = templatePlace('Drag');
  melt.tree.k.find((n) => n.c === 'Workspace').k.push({ c: 'Part', n: 'Crate', p: { Position: v3(0, 1, -4) }, k: [{ c: 'DragDetector', n: 'Drag', p: { MaxActivationDistance: 10 } }] });
  melt.tree.k.find((n) => n.c === 'ServerScriptService').k = [{ c: 'Script', n: 'S', p: { Source: `
    local d = workspace.Crate.Drag
    d.DragStart:Connect(function(p, at) print("start", p.Name, at.Z) end)
    d.DragContinue:Connect(function(p, at) print("move", workspace.Crate.Position.X) end)
    d.DragEnd:Connect(function(p) print("end", p.Name) end)
  ` } }];
  const vm = await PlaceVM.create();
  const logs = [];
  const run = (out) => { for (const o of out || []) if (o.o === 'print') logs.push(o.msg); return out || []; };
  run(vm.init({ role: 'server', place: melt, seed: 1 }));
  run(vm.start());
  run(vm.dispatch([{ e: 'player_add', userId: 1, name: 'p1', display: 'p1', lang: 'en' }]));
  run(vm.step(0.1));
  const det = vm.snapshot().find((o) => o.n === 'Drag').id;
  const crate = vm.snapshot().find((o) => o.n === 'Crate').id;
  run(vm.dispatch([{ e: 'pos', userId: 1, p: v3(0, 1, 0) }]));
  run(vm.dispatch([{ e: 'drag', userId: 1, id: det, phase: 'start', p: [0, 1.5, -3.5] }]));
  const moved = run(vm.dispatch([{ e: 'drag', userId: 1, id: det, phase: 'move', p: [2, 1.5, -3.5], pos: [2, 1, -4] }]));
  assert.ok(moved.some((o) => o.o === 'set' && o.id === crate && o.k === 'Position'), 'the move goes to everyone');
  run(vm.dispatch([{ e: 'drag', userId: 1, id: det, phase: 'end' }]));
  run(vm.step(0.05));
  assert.deepEqual(logs.filter((l) => /^(start|move|end)/.test(l)), ['start p1 -3.5', 'move 2', 'end p1']);
  // From across the map: nothing happens.
  run(vm.dispatch([{ e: 'pos', userId: 1, p: v3(0, 1, 200) }]));
  const far = run(vm.dispatch([{ e: 'drag', userId: 1, id: det, phase: 'move', p: [5, 1.5, -3.5], pos: [5, 1, -4] }]));
  assert.ok(!far.some((o) => o.o === 'set' && o.id === crate));
  vm.close();
});

test('GuiObject.Draggable: Position follows, DragBegin and DragStopped fire', async () => {
  const vm = await PlaceVM.create({ timeLimit: 0.5 });
  const logs = [];
  const run = (out) => { for (const o of out || []) if (o.o === 'print') logs.push(o.msg); return out || []; };
  run(vm.init({ role: 'client', userId: 5, seed: 1 }));
  run(vm.start());
  run(vm.dispatch([
    { e: 'new', id: 'sg', c: 'ScreenGui', n: 'G', parent: '0' },
    { e: 'new', id: 'f', c: 'Frame', n: 'Window', parent: 'sg', p: { Draggable: true } },
    { e: 'new', id: 'sp', c: 'StarterPlayer', n: 'StarterPlayer', parent: '0' },
    { e: 'new', id: 'sps', c: 'StarterPlayerScripts', n: 'StarterPlayerScripts', parent: 'sp' },
    { e: 'new', id: 'ls', c: 'LocalScript', n: 'L', parent: 'sps', p: { Source: `
      local f = game:GetService("StarterPlayer")  -- (any LocalScript)
      task.wait()
      local w = game:FindFirstChild("G", true) and game:FindFirstChild("G", true).Window
      w.DragBegin:Connect(function(at) print("begin", at.X.Offset) end)
      w.DragStopped:Connect(function(x, y) print("stopped", x, y, w.Position.X.Offset, w.Position.Y.Offset) end)
    ` } },
    { e: 'new', id: 'pl', c: 'Players', n: 'Players', parent: '0' },
    { e: 'new', id: 'me', c: 'Player', n: 'tester', parent: 'pl', p: { UserId: 5 } },
  ]));
  for (let i = 0; i < 3; i++) run(vm.step(0.05));
  run(vm.dispatch([{ e: 'gui', id: 'f', ev: 'drag', value: [0, 0, 0, 0, 'start'] }]));
  run(vm.dispatch([{ e: 'gui', id: 'f', ev: 'drag', value: [0, 30, 0, 40, 'move'] }]));
  run(vm.dispatch([{ e: 'gui', id: 'f', ev: 'drag', value: [0, 30, 0, 40, 'end', 300, 400] }]));
  run(vm.step(0.05));
  assert.deepEqual(logs, ['begin 0', 'stopped 300 400 30 40'], logs.join('\n'));
  vm.close();
});
