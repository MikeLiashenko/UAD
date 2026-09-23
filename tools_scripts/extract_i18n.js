// Lists every translatable key: GS.t("...") literals + Cyrillic data strings (names, descriptions)
// from data files. Prints keys missing from scripts/i18n/en.gd and uk.gd.
const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..', 'scripts');
const CYR = /[А-Яа-яЁё]/;
function walk(d, o) {
  for (const f of fs.readdirSync(d)) {
    const p = path.join(d, f);
    if (fs.statSync(p).isDirectory()) walk(p, o); else if (f.endsWith('.gd')) o.push(p);
  }
  return o;
}
const keys = new Set();
const DATA = new Set(['autoload/gs.gd', 'world/city_gen.gd', 'world/landmarks.gd', 'ui/main_menu.gd', 'world/city_map.gd', 'main.gd']);
for (const f of walk(root, [])) {
  const rel = path.relative(root, f).split(path.sep).join('/');
  if (rel.startsWith('i18n/')) continue;
  const src = fs.readFileSync(f, 'utf8');
  for (const m of src.matchAll(/GS\.t\(("(?:[^"\\]|\\.)*")\)/g)) keys.add(JSON.parse(m[1]));
  if (DATA.has(rel) || rel.startsWith('world/cities/')) {
    for (const line of src.split('\n')) {
      const t = line.trim();
      if (t.startsWith('#') || /print\(|\.contains\(|get_meta|set_meta/.test(line)) continue;
      for (const m of line.matchAll(/("(?:[^"\\]|\\.)*")/g)) {
        const s = JSON.parse(m[1]);
        if (CYR.test(s)) keys.add(s);
      }
    }
  }
}
function dictKeys(file) {
  const p = path.join(root, 'i18n', file);
  if (!fs.existsSync(p)) return new Set();
  const src = fs.readFileSync(p, 'utf8');
  const s = new Set();
  for (const m of src.matchAll(/^\s*("(?:[^"\\]|\\.)*")\s*:/gm)) s.add(JSON.parse(m[1]));
  return s;
}
const mode = process.argv[2] || 'list';
if (mode === 'list') {
  for (const k of [...keys].sort()) console.log(JSON.stringify(k));
  console.error('total keys:', keys.size);
} else {
  for (const file of ['en.gd', 'uk.gd']) {
    const d = dictKeys(file);
    const miss = [...keys].filter((k) => !d.has(k));
    const extra = [...d].filter((k) => !keys.has(k));
    console.log(`${file}: ${d.size} entries, missing ${miss.length}, unused ${extra.length}`);
    for (const k of miss) console.log('  MISSING ' + JSON.stringify(k));
  }
}
