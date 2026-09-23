// Second pass: wraps displayed data-table fields (names, descriptions, abbreviations)
// and target names in GS.t(...).
const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..', 'scripts');
const SKIP = new Set(['autoload/gs.gd', 'world/city_gen.gd', 'world/landmarks.gd', 'world/shaders.gd', 'world/kyiv_map.gd']);
const FIELD = /(?<![\w.(])((?:GS\.(?:WEAPONS|ENEMIES|LOCATIONS|DIFFICULTY)\[[^\]]+\]|GS\.loc_def\(\)|[A-Za-z_][\w.]*\.def|def))\.(name|short|plural|desc|abbr)\b/g;

function walk(dir, out) {
  for (const f of fs.readdirSync(dir)) {
    const p = path.join(dir, f);
    if (fs.statSync(p).isDirectory()) walk(p, out); else if (f.endsWith('.gd')) out.push(p);
  }
  return out;
}
let n = 0;
for (const file of walk(root, [])) {
  const rel = path.relative(root, file).replace(/\\/g, '/');
  if (SKIP.has(rel) || rel.startsWith('i18n/')) continue;
  const src = fs.readFileSync(file, 'utf8');
  const lines = src.split('\n').map((line) => {
    if (line.trim().startsWith('#')) return line;
    let out = line.replace(FIELD, (m, obj, f) => { n++; return `GS.t(String(${obj}.${f}))`; });
    out = out.replace(/(?<![\w.(])(e\.target_name)\b(?!\s*=)/g, (m) => { n++; return `GS.t(${m})`; });
    return out;
  });
  fs.writeFileSync(file, lines.join('\n'));
}
console.log('wrapped data fields:', n);
