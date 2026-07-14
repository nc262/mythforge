// One-time extraction of the game's data tables out of the legacy JS frontend
// into godot/data/*.json. The JSON becomes the source of truth for the Godot
// client; edit the JSON, not the JS, from here on.
//
//   node scripts/extract_studio_data.mjs
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import vm from 'node:vm';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const outDir = join(root, 'godot', 'data');
mkdirSync(outDir, { recursive: true });

// ── 1. studioCompendium.js is pure data — import it directly ───────────────
import { pathToFileURL } from 'node:url';
const comp = await import(pathToFileURL(join(root, 'static/js/studioCompendium.js')).href);
writeFileSync(join(outDir, 'bestiary.json'), JSON.stringify({ entries: comp.BESTIARY, tiers: comp.BESTIARY_TIERS }, null, 1));
writeFileSync(join(outDir, 'spells.json'), JSON.stringify({ spells: comp.SPELLS, schools: comp.SPELL_SCHOOLS }, null, 1));
writeFileSync(join(outDir, 'class_lore.json'), JSON.stringify(comp.CLASS_LORE, null, 1));
console.log('compendium: bestiary=%d spells=%d', comp.BESTIARY.length, comp.SPELLS.length);

// ── 2. characterStudio.js tables — slice `const NAME = {...};` and eval ────
const src = readFileSync(join(root, 'static/js/characterStudio.js'), 'utf8');

function slice(name) {
  const re = new RegExp(`const ${name.replace(/\$/g, '\\$')}\\s*=\\s*`, 'm');
  const m = re.exec(src);
  if (!m) throw new Error(`const ${name} not found`);
  let i = m.index + m[0].length;
  const open = src[i];
  const close = { '{': '}', '[': ']' }[open];
  if (!close) throw new Error(`${name}: unexpected start '${open}'`);
  let depth = 0, inStr = null;
  for (let j = i; j < src.length; j++) {
    const ch = src[j], prev = src[j - 1];
    if (inStr) { if (ch === inStr && prev !== '\\') inStr = null; continue; }
    if (ch === "'" || ch === '"' || ch === '`') { inStr = ch; continue; }
    if (ch === open) depth++;
    else if (ch === close && --depth === 0) return src.slice(i, j + 1);
  }
  throw new Error(`${name}: unbalanced`);
}

const TABLES = [
  'CLASS_PRESETS', '_CASTER_SLOTS', 'CLASS_SPELLS', 'CLASS_FEATURES',
  'HERITAGES', '_CONDITION_FX', '_CONDITION_DESC', '_EXHAUSTION',
  'FEATS', 'SUBCLASSES', 'SUBCLASS_GRANTS', 'BACKGROUNDS',
  'CLASS_RESKINS', '_VENDOR_STOCK',
];
const out = {};
for (const name of TABLES) {
  try {
    out[name] = vm.runInNewContext(`(${slice(name)})`, {});
    console.log('ok  %s (%s entries)', name, Array.isArray(out[name]) ? out[name].length : Object.keys(out[name]).length);
  } catch (e) {
    console.warn('SKIP %s: %s', name, e.message);
  }
}
const key = (n) => n.replace(/^_/, '').toLowerCase();
writeFileSync(join(outDir, 'tables.json'), JSON.stringify(Object.fromEntries(Object.entries(out).map(([k, v]) => [key(k), v])), null, 1));
console.log('wrote', join(outDir, 'tables.json'));
