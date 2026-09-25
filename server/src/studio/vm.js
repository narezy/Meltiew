// A place's scripts in a sandboxed Luau VM (WebAssembly build of native/core).
// The same runtime.luau runs inside every client, so behaviour matches on both ends.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import createLuau from './luau.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
export const RUNTIME_SOURCE = fs.readFileSync(path.join(here, 'runtime', 'runtime.luau'), 'utf8');
export const SCHEMA = JSON.parse(fs.readFileSync(path.join(here, 'runtime', 'classes.json'), 'utf8'));

let modulePromise = null;
function luau() {
  modulePromise ??= createLuau();
  return modulePromise;
}

export class PlaceVM {
  // memoryMb caps what scripts can allocate; timeLimit (s) stops loops that never yield.
  static async create({ memoryMb = 64, timeLimit = 0.25 } = {}) {
    const L = await luau();
    const vm = new PlaceVM();
    vm.vm = new L.VM(memoryMb);
    vm.timeLimit = timeLimit;
    const err = vm.vm.run('=runtime', RUNTIME_SOURCE);
    if (err) throw new Error('runtime failed to load: ' + err);
    vm.vm.sandbox();
    return vm;
  }

  _call(name, arg) {
    if (!this.vm) return []; // closed with its server
    const out = this.vm.call(name, arg === undefined ? '' : JSON.stringify(arg), this.timeLimit);
    if (!this.vm.ok()) throw new Error(out);
    return out ? JSON.parse(out) : [];
  }

  init(cfg) {
    return this._call('__init', { schema: SCHEMA, ...cfg });
  }

  start() {
    return this._call('__start');
  }

  dispatch(events) {
    return this._call('__dispatch', events);
  }

  step(dt) {
    return this._call('__step', { dt });
  }

  snapshot() {
    return this._call('__snapshot');
  }

  memoryUsed() {
    return this.vm.memoryUsed();
  }

  close() {
    this.vm?.delete();
    this.vm = null;
  }
}
