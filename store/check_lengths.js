// Checks the Google Play limits of store/listing.md: name 30, short description 80, full 4000.
const fs = require("fs");
const path = require("path");
const LIMITS = { "Name": 30, "Short description": 80, "Full description": 4000, "Release notes (first release)": 500 };
const text = fs.readFileSync(path.join(__dirname, "listing.md"), "utf8").replace(/\r/g, "");
let lang = "", bad = 0;
for (const block of text.split(/\n(?=##+ )/)) {
	const head = block.match(/^(##+) (.+)/);
	if (!head) continue;
	if (head[1] === "##") { lang = head[2]; continue; }
	const limit = LIMITS[head[2]];
	if (!limit) continue;
	const body = block.slice(head[0].length).replace(/\n---\s*$/, "").trim();
	const n = [...body].length;
	const ok = n <= limit;
	if (!ok) bad++;
	console.log(`${ok ? "ok " : "TOO LONG"} ${lang.padEnd(16)} ${head[2].padEnd(30)} ${n}/${limit}`);
}
process.exit(bad ? 1 : 0);
