// Third pass: String(<table>.name) -> GS.t(String(<table>.name))
const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..', 'scripts');
const SKIP = new Set(['autoload/gs.gd', 'world/city_gen.gd', 'world/landmarks.gd', 'world/shaders.gd', 'world/kyiv_map.gd']);
const RE = /(?<!GS\.t\()String\(((?:GS\.\w+\[[^\]]+\]|GS\.loc_def\(\)|[A-Za-z_][\w.]*def)\.(?:name|short|plural|desc|abbr))\)/g;
function walk(d, o) {
  for (const f of fs.readdirSync(d)) {
    const p = path.join(d, f);
    if (fs.statSync(p).isDirectory()) walk(p, o); else if (f.endsWith('.gd')) o.push(p);
  }
  return o;
}
let n = 0;
for (const f of walk(root, [])) {
  const rel = path.relative(root, f).split(path.sep).join('/');
  if (SKIP.has(rel)) continue;
  const s = fs.readFileSync(f, 'utf8').replace(RE, (m, x) => { n++; return 'GS.t(String(' + x + '))'; });
  fs.writeFileSync(f, s);
}
console.log('wrapped', n);
