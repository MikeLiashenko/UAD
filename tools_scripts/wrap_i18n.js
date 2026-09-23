// Wraps user-visible Cyrillic string literals in GS.t("...") so they go through the
// translation server. Skips comments, const tables, and files that hold only data names.
const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..', 'scripts');
const SKIP_FILES = new Set(['autoload/gs.gd', 'world/city_gen.gd', 'world/landmarks.gd', 'world/shaders.gd']);
const CYR = /[А-Яа-яЁёІіЇїЄєҐґ]/;

function walk(dir, out) {
  for (const f of fs.readdirSync(dir)) {
    const p = path.join(dir, f);
    if (fs.statSync(p).isDirectory()) walk(p, out);
    else if (f.endsWith('.gd')) out.push(p);
  }
  return out;
}

let changed = 0;
for (const file of walk(root, [])) {
  const rel = path.relative(root, file).replace(/\\/g, '/');
  if (SKIP_FILES.has(rel) || rel.startsWith('i18n/')) continue;
  const lines = fs.readFileSync(file, 'utf8').split('\n');
  let depth = 0; // inside a const block
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const trimmed = line.trim();
    if (depth > 0) {
      for (const ch of line) { if ('[{('.includes(ch)) depth++; else if (']})'.includes(ch)) depth--; }
      continue;
    }
    if (/^const\s/.test(trimmed)) {
      let d = 0;
      for (const ch of line) { if ('[{('.includes(ch)) d++; else if (']})'.includes(ch)) d--; }
      depth = Math.max(d, 0);
      continue;
    }
    if (trimmed.startsWith('#') || !CYR.test(line)) continue;
    // replace string literals containing Cyrillic, not already wrapped, not in comparisons
    const out = line.replace(/(GS\.t\()?("(?:[^"\\]|\\.)*")/g, (m, pre, lit, off) => {
      if (pre) return m;
      if (!CYR.test(lit)) return m;
      const before = line.slice(0, off);
      if (/(==|!=)\s*$/.test(before) || /contains\(\s*$/.test(before) || /print\([^)]*$/.test(before)) return m;
      if (/^\s*"[^"]*"\s*:/.test(line.slice(off))) return m; // dictionary key
      return 'GS.t(' + lit + ')';
    });
    if (out !== line) { lines[i] = out; changed++; }
  }
  fs.writeFileSync(file, lines.join('\n'));
}
console.log('wrapped lines:', changed);
