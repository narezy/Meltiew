import { test } from 'node:test';
import assert from 'node:assert/strict';
import { PlaceVM } from '../src/studio/vm.js';

// A client VM with one LocalScript: what the app sees from a gamepad, a phone's on-screen
// action button and ContextActionService (bound keys don't reach the game's own controls).
test('input: gamepad buttons, sticks, Enum.KeyCode and ContextActionService', async () => {
  const vm = await PlaceVM.create({ timeLimit: 0.5 });
  const logs = [];
  const ops = [];
  const take = (out) => { for (const o of out || []) { ops.push(o); if (o.o === 'print') logs.push(o.msg); } };
  take(vm.init({ role: 'client', userId: 5, seed: 1, device: { touch: false, keyboard: true, mouse: true, gamepad: true, platform: 'Linux', preferred: 'Gamepad' } }));
  take(vm.start());
  const source = `
    local UIS = game:GetService("UserInputService")
    local CAS = game:GetService("ContextActionService")
    print("device", UIS:GetPlatform(), UIS.GamepadEnabled, UIS.PreferredInput, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonA, #Enum.KeyCode:GetEnumItems() > 50)
    CAS:BindAction("Throw", function(name, state, input)
      print("cas", name, state, input.KeyCode)
      return Enum.ContextActionResult.Sink
    end, true, Enum.KeyCode.ButtonX, Enum.KeyCode.Q)
    CAS:SetTitle("Throw", "Бросок")
    UIS.InputBegan:Connect(function(input, processed) print("uis", input.KeyCode, input.UserInputType, processed) end)
    UIS.InputChanged:Connect(function(input)
      if input.KeyCode == Enum.KeyCode.Thumbstick1 then print("stick", input.Position.X, input.UserInputState) end
    end)
  `;
  take(vm.dispatch([
    { e: 'new', id: 'sp', c: 'StarterPlayer', n: 'StarterPlayer', parent: '0' },
    { e: 'new', id: 'sps', c: 'StarterPlayerScripts', n: 'StarterPlayerScripts', parent: 'sp' },
    { e: 'new', id: 'ls', c: 'LocalScript', n: 'Controls', parent: 'sps', p: { Source: source } },
    { e: 'new', id: 'pl', c: 'Players', n: 'Players', parent: '0' },
    { e: 'new', id: 'me', c: 'Player', n: 'tester', parent: 'pl', p: { UserId: 5 } },
  ]));
  for (let i = 0; i < 3; i++) take(vm.step(0.05));
  take(vm.dispatch([
    { e: 'input', kind: 'Gamepad1', key: 'ButtonX', down: true },
    { e: 'input', kind: 'Gamepad1', key: 'ButtonA', down: true },
    { e: 'input', kind: 'Gamepad1', key: 'Thumbstick1', change: true, x: 0.5, y: 0 },
    { e: 'cas', name: 'Throw', down: true },
  ]));
  assert.ok(logs.includes('device Linux true Gamepad Shift ButtonA true'), logs.join('\n'));
  assert.ok(logs.includes('cas Throw Begin ButtonX'), logs.join('\n'));
  assert.ok(logs.includes('uis ButtonX Gamepad1 true'), 'a sunk input still reaches UserInputService, marked processed');
  assert.ok(logs.includes('uis ButtonA Gamepad1 false'), logs.join('\n'));
  assert.ok(logs.includes('stick 0.5 Change'), logs.join('\n'));
  assert.ok(logs.includes('cas Throw Begin Unknown'), 'the on-screen button calls the action');
  const cas = ops.filter((o) => o.o === 'cas').at(-1);
  assert.deepEqual(cas.keys, ['ButtonX', 'Q']);
  assert.equal(cas.buttons[0].name, 'Throw');
  assert.equal(cas.buttons[0].title, 'Бросок');
});
