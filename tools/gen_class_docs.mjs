#!/usr/bin/env node
// Builds the class reference (server/public/docs/studio/classes.md) from the
// runtime itself: properties and events from classes.json, methods from the
// `Methods.X = { ... }` tables in runtime.luau. Run after changing either.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const runtimeDir = path.join(root, 'server/src/studio/runtime');
const schema = JSON.parse(fs.readFileSync(path.join(runtimeDir, 'classes.json'), 'utf8'));
const luau = fs.readFileSync(path.join(runtimeDir, 'runtime.luau'), 'utf8').split('\n');

// Methods.Class = { Name = function(self, a, b) ... }
const methods = {};
for (let i = 0; i < luau.length; i++) {
  const head = luau[i].match(/^Methods\.(\w+) = \{/);
  if (!head) continue;
  const list = (methods[head[1]] = []);
  for (let j = i + 1; j < luau.length && luau[j] !== '}'; j++) {
    const m = luau[j].match(/^\t(\w+) = function\(([^)]*)\)/);
    if (m) list.push({ name: m[1], args: m[2].split(',').map((s) => s.trim()).filter((a) => a && a !== 'self' && a !== '_') });
  }
  const alias = luau.slice(i).find((l) => l.startsWith(`Methods.${head[1]}.`) && l.includes(' = Methods.'));
  if (alias) list.push({ name: alias.match(/\.(\w+) = /)[1], args: ['name'] });
}

const fmtDefault = (v) => {
  if (v === null || v === undefined) return '';
  if (typeof v === 'object') {
    if (v.$v3) return `Vector3.new(${v.$v3.join(', ')})`;
    if (v.$v2) return `Vector2.new(${v.$v2.join(', ')})`;
    if (v.$c3) return `Color3.fromHex("${v.$c3}")`;
    if (v.$u2) return `UDim2.new(${v.$u2.join(', ')})`;
    if (v.$u) return `UDim.new(${v.$u.join(', ')})`;
    return '';
  }
  if (typeof v === 'string') return v === '' ? '""' : `"${v}"`;
  return String(v);
};
const fmtType = (t) => (t.startsWith('enum:') ? `[${t.slice(5)}](#${t.slice(5).toLowerCase()})` : t);

const classes = schema.classes;
const order = [undefined, 'Service', '3D', 'GUI', 'Script', 'Logic'];
const titles = { Service: 'Services', '3D': '3D world', GUI: 'User interface', Script: 'Scripts', Logic: 'Logic and values', undefined: 'Base classes and runtime objects' };
const out = [];
out.push('# Class reference', '');
out.push('> Generated from the runtime by `tools/gen_class_docs.mjs`. Every property here can be read and set from scripts;', '> "read-only" ones only read. Enum values are plain strings: `part.Material = "Neon"` and `Enum.Material.Neon` are the same.', '');
out.push('Every object is an **Instance**, so everything listed under Instance works on all of them.', '');

for (const cat of order) {
  const names = Object.keys(classes).filter((n) => classes[n].category === cat && !classes[n].hidden);
  if (!names.length) continue;
  out.push(`## ${titles[cat]}`, '');
  for (const name of names) {
    const c = classes[name];
    out.push(`### ${name}`, '');
    const tags = [];
    if (c.base && c.base !== 'Instance') tags.push(`inherits [${c.base}](#${c.base.toLowerCase()})`);
    if (c.service) tags.push('service');
    if (c.creatable) tags.push('can be created with `Instance.new`');
    if (c.abstract) tags.push('abstract');
    if (c.server_only) tags.push('server only: never sent to players');
    if (tags.length) out.push(`*${tags.join(' · ')}*`, '');
    if (c.doc) out.push(c.doc, '');
    const props = Object.entries(c.props || {});
    if (props.length) {
      out.push('| Property | Type | Default | Notes |', '|---|---|---|---|');
      for (const [k, p] of props) {
        const notes = [];
        if (p.readonly) notes.push('read-only');
        if (p.min !== undefined) notes.push(`min ${p.min}`);
        if (p.max !== undefined) notes.push(`max ${p.max}`);
        out.push(`| ${k} | ${fmtType(p.type)} | ${fmtDefault(p.default).replace(/\|/g, '\\|')} | ${notes.join(', ')} |`);
      }
      out.push('');
    }
    if (methods[name]?.length) out.push('**Methods:** ' + methods[name].map((m) => `\`${m.name}(${m.args.join(', ')})\``).join(', '), '');
    if (c.events?.length) out.push('**Events:** ' + c.events.map((e) => `\`${e}\``).join(', '), '');
    if (c.callbacks?.length) out.push('**Callbacks:** ' + c.callbacks.map((e) => `\`${e}\``).join(', '), '');
  }
}

out.push('## Enums', '');
for (const [name, values] of Object.entries(schema.enums)) {
  out.push(`### ${name}`, '', values.map((v) => `\`${v}\``).join(', '), '');
}

const target = path.join(root, 'server/public/docs/studio/classes.md');
fs.mkdirSync(path.dirname(target), { recursive: true });
fs.writeFileSync(target, out.join('\n'));
console.log('wrote', path.relative(root, target));
