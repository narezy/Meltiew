import { test } from 'node:test';
import assert from 'node:assert/strict';
import { PlaceVM } from '../src/studio/vm.js';
import { templatePlace } from '../src/studio/places.js';
import { GameHub } from '../src/game.js';

const v3 = (x, y, z) => ({ $v3: [x, y, z] });

// A car: a VehicleSeat, a wheel and a back seat in one Model.
test('vehicle: the driver and riders are told to the server, the whole Model moves with the seat', async () => {
  const melt = templatePlace('Cars');
  const ws = melt.tree.k.find((n) => n.c === 'Workspace');
  ws.k.push({ c: 'Model', n: 'Car', k: [
    { c: 'VehicleSeat', n: 'Drive', p: { Position: v3(0, 1, 0) } },
    { c: 'Part', n: 'Wheel', p: { Position: v3(2, 0.5, -3) } },
    { c: 'Seat', n: 'Back', p: { Position: v3(0, 1, 2) } },
  ] });
  melt.tree.k.find((n) => n.c === 'ServerScriptService').k = [{ c: 'Script', n: 'Watch', p: { Source: `
    local seat = workspace.Car.Drive
    seat:GetPropertyChangedSignal("Throttle"):Connect(function() print("throttle", seat.Throttle, seat.Steer) end)
  ` } }];
  const vm = await PlaceVM.create();
  const logs = [];
  const run = (out) => { for (const o of out || []) if (o.o === 'print') logs.push(o.msg); return out || []; };
  run(vm.init({ role: 'server', place: melt, seed: 1 }));
  run(vm.start());
  for (const u of [1, 2]) run(vm.dispatch([{ e: 'player_add', userId: u, name: 'p' + u, display: 'p' + u, lang: 'en' }]));
  run(vm.step(0.05));
  const byName = (name) => vm.snapshot().find((o) => o.n === name);
  const drive = byName('Drive').id;
  const back = byName('Back').id;
  let out = run(vm.dispatch([{ e: 'seat', userId: 1, id: drive }]));
  let veh = out.find((o) => o.o === 'vehicle');
  assert.deepEqual([veh.id, veh.driver, veh.riders, veh.max], [drive, 1, [1], 60]);
  out = run(vm.dispatch([{ e: 'seat', userId: 2, id: back }]));
  veh = out.find((o) => o.o === 'vehicle');
  assert.deepEqual([veh.driver, veh.riders.sort()], [1, [1, 2]]);
  // Driven 10 studs along X and turned a quarter round: the wheel goes along.
  run(vm.dispatch([{ e: 'veh', id: drive, p: [10, 1, 0], r: [0, 90, 0], th: 1, st: -0.5, sp: 12 }]));
  const wheel = byName('Wheel').p;
  const near = (a, b) => a.every((x, i) => Math.abs(x - b[i]) < 1e-6);
  assert.ok(near(wheel.Position.$v3, [7, 0.5, -2]), JSON.stringify(wheel));
  assert.ok(near(wheel.Rotation.$v3, [0, 90, 0]), JSON.stringify(wheel));
  run(vm.step(0.05));
  assert.ok(logs.includes('throttle 1 -1'), logs.join('\n'));
  // The driver gets out: nobody drives, the back seat still rides.
  out = run(vm.dispatch([{ e: 'seat', userId: 1 }]));
  veh = out.find((o) => o.o === 'vehicle');
  assert.deepEqual([veh.driver, veh.riders], [0, [2]]);
  vm.close();
});

test('vehicle: only the driver (or one who just got out) moves it, and no faster than it goes', () => {
  const server = { vm: {}, vehicles: new Map(), riders: new Map(), vehOut: new Map(), vehVm: new Map() };
  const conn = (id) => ({ server, player: {}, user: { id } });
  const hub = Object.create(GameHub.prototype);
  server.vehicles.set('car', { driver: 1, riders: [1], max: 60, p: null, r: null, at: 0 });
  hub.vehicleIn(conn(2), { id: 'car', p: [5, 0, 0], r: [0, 0, 0] });
  assert.equal(server.vehOut.size, 0, 'not the driver');
  hub.vehicleIn(conn(1), { id: 'car', p: [5, 0, 0], r: [0, 45, 0], sp: 3, th: 1, st: 0 });
  assert.deepEqual(server.vehOut.get('car').slice(0, 7), ['car', 5, 0, 0, 0, 45, 0]);
  // 500 studs in a moment: not a car's doing.
  hub.vehicleIn(conn(1), { id: 'car', p: [505, 0, 0], r: [0, 45, 0] });
  assert.deepEqual(server.vehicles.get('car').p, [5, 0, 0]);
  // Got out a moment ago: it may still roll to a stop.
  const v = server.vehicles.get('car');
  Object.assign(v, { driver: 0, last: 1, coastUntil: Date.now() + 5000, at: Date.now() - 200 });
  hub.vehicleIn(conn(1), { id: 'car', p: [6, 0, 0], r: [0, 45, 0] });
  assert.deepEqual(server.vehicles.get('car').p, [6, 0, 0]);
});
