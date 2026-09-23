extends RefCounted
## Procedural shaders (all visuals are computed; no texture files).
## `global uniform float night` is a project-wide shader global (project.godot [shader_globals]).

## Size of the district array of the ground shader (a city may have up to this many districts).
const MAX_DISTRICTS := 32

## Sky: day gradient with the sun and its glow, a layer of drifting clouds (lit from the sun by
## day; at night dark, underlit orange by the city and rimmed by the moon), the warm dome of light
## pollution over the horizon, stars in two sizes, the Milky Way and the moon with its maria.
## The horizon colour is the fog colour (see CityMap.set_night), so the land melts into the sky.
## `gfx` (global): 0 low, 1 high, 2 ultra — cloud octaves and the star field depend on it.
const SKY := """
shader_type sky;
global uniform float night;
global uniform float gfx;
uniform vec3 sun_dir = vec3(0.4, 0.55, 0.6);
uniform vec3 moon_dir = vec3(-0.45, 0.38, -0.8);
uniform vec3 haze_day : source_color = vec3(0.7, 0.77, 0.85);
uniform vec3 haze_night : source_color = vec3(0.16, 0.1, 0.09);
uniform float cloud_cover = 0.45;
uniform vec2 wind = vec2(1.0, 0.35);

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float hash3(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

float vnoise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), u.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), u.x), u.y);
	float b = mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), u.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), u.x), u.y);
	return mix(a, b, u.z);
}

float fbm(vec2 p, int oct) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 7; i++) {
		if (i >= oct) break;
		s += a * vnoise(p);
		p = p * 2.07 + vec2(17.1, 9.3);
		a *= 0.5;
	}
	return s;
}

vec3 star_layer(vec3 d, float scale, float density, float size) {
	vec3 p = d * scale;
	vec3 cell = floor(p);
	float r = hash3(cell);
	if (r < density) return vec3(0.0);
	vec3 off = vec3(hash3(cell + 1.3), hash3(cell + 2.7), hash3(cell + 5.1)) - 0.5;
	float dist = length(fract(p) - 0.5 - off * 0.6);
	float tw = 0.6 + 0.4 * sin(TIME * (1.5 + r * 7.0) + r * 60.0);
	float t = hash3(cell + 9.7);
	vec3 tint = t < 0.2 ? vec3(1.0, 0.8, 0.62) : (t > 0.85 ? vec3(0.7, 0.82, 1.0) : vec3(0.92, 0.94, 1.0));
	return tint * smoothstep(size, 0.0, dist) * tw;
}

void sky() {
	vec3 d = EYEDIR;
	float y = d.y;
	float yh = max(y, 0.0);
	vec3 sd = normalize(sun_dir);
	vec3 md = normalize(moon_dir);
	float dusk = 1.0 - abs(night * 2.0 - 1.0);
	// --- day: deep zenith, pale hazy horizon, warm glow around the sun
	float sdot = dot(d, sd);
	vec3 day = mix(haze_day, vec3(0.13, 0.33, 0.72), pow(yh, 0.5));
	day += vec3(1.0, 0.82, 0.55) * pow(max(sdot, 0.0), 6.0) * 0.22 + vec3(1.0, 0.9, 0.72) * pow(max(sdot, 0.0), 90.0) * 0.8;
	// --- night: near-black zenith, the orange-brown dome of the city's lights over the horizon
	vec3 nt = mix(haze_night, vec3(0.004, 0.007, 0.018), pow(yh, 0.35));
	nt += vec3(0.1, 0.06, 0.036) * exp(-yh * 10.0);
	vec3 col = mix(day, nt, night);
	col += vec3(0.75, 0.3, 0.08) * dusk * exp(-yh * 7.0) * 0.7;
	if (y > 0.0) {
		float above = clamp(y * 8.0, 0.0, 1.0);
		if (!AT_CUBEMAP_PASS && night > 0.02) {
			// stars: a sparse bright layer and a dense faint one (ultra), plus the Milky Way
			vec3 stars = star_layer(d, 260.0, 0.991, 0.12) * 1.6;
			if (gfx > 0.5) stars += star_layer(d, 620.0, 0.975, 0.16) * 0.55;
			vec3 mw_n = normalize(vec3(0.42, 0.28, 0.86));
			float band = exp(-pow(dot(d, mw_n) * 5.5, 2.0));
			float mw = 0.0;
			if (gfx > 0.5) {
				mw = band * (0.35 + 0.65 * vnoise3(d * 9.0)) * (0.55 + 0.45 * vnoise3(d * 31.0));
				stars += star_layer(d, 900.0, 0.93, 0.2) * band * 0.9;
			}
			col += (stars + vec3(0.1, 0.1, 0.14) * mw * 0.55) * night * above;
			// the moon: limb-darkened disc with its seas, and a soft halo
			float mdot = dot(d, md);
			float disc = smoothstep(0.99955, 0.99972, mdot);
			if (disc > 0.0) {
				vec3 side = normalize(cross(md, vec3(0.0, 1.0, 0.0)));
				vec3 up = cross(side, md);
				vec2 q = vec2(dot(d, side), dot(d, up)) * 42.0;
				float maria = smoothstep(0.45, 0.75, vnoise(q * 3.0 + 4.0) * 0.6 + vnoise(q * 7.0) * 0.4);
				float limb = sqrt(max(0.0, 1.0 - dot(q, q)));
				col += mix(vec3(1.0, 0.98, 0.92), vec3(0.62, 0.64, 0.68), maria) * (0.55 + 0.45 * limb) * disc * night * 2.2;
			}
			col += vec3(0.5, 0.58, 0.75) * (pow(max(mdot, 0.0), 700.0) * 0.5 + pow(max(mdot, 0.0), 40.0) * 0.06) * night;
		}
		// the sun disc
		col += vec3(1.0, 0.95, 0.82) * smoothstep(0.99965, 0.99985, sdot) * 8.0 * (1.0 - night);
		// clouds: a flat layer seen through the dome, drifting with the wind
		if (gfx > -0.5 && y > 0.015) {
			float h = 1.0 / y;
			vec2 cp = d.xz * h * 0.55 + wind * TIME * 0.006;
			int oct = AT_CUBEMAP_PASS ? 3 : (gfx > 1.5 ? 6 : (gfx > 0.5 ? 5 : 3));
			float n = fbm(cp, oct);
			float dens = smoothstep(1.0 - cloud_cover - 0.08, 1.0 - cloud_cover + 0.3, n);
			if (dens > 0.001) {
				vec3 ld = mix(sd, md, step(0.5, night));
				vec2 toward = normalize(ld.xz + vec2(0.0001)) * 0.22;
				float n2 = fbm(cp + toward, max(oct - 2, 2));
				float lit = clamp(0.62 + (n - n2) * 3.2, 0.0, 1.0);
				float thick = smoothstep(0.0, 0.7, dens);
				vec3 cday = mix(vec3(0.5, 0.55, 0.64), vec3(1.0, 0.98, 0.95), lit);
				cday = mix(cday, cday * vec3(1.0, 0.8, 0.62), dusk);
				// at night the city lights the cloud bellies, most of all low over the horizon
				vec3 under = vec3(0.15, 0.085, 0.05) * (0.35 + 0.65 * exp(-yh * 4.0)) * thick;
				vec3 cnight = mix(vec3(0.018, 0.02, 0.028), vec3(0.07, 0.075, 0.09), lit) + under;
				cnight += vec3(0.25, 0.28, 0.35) * pow(max(dot(d, md), 0.0), 30.0) * (1.0 - thick) * 0.6;
				vec3 cc = mix(cday, cnight, night);
				float fade = smoothstep(0.015, 0.2, y);
				col = mix(col, cc, dens * fade * 0.94);
			}
		}
	} else {
		col = mix(col, mix(haze_day, haze_night, night), clamp(-y * 12.0, 0.0, 1.0));
	}
	COLOR = col;
}
"""


## The land beyond the map, out to the horizon: a patchwork of fields, woods and villages,
## with the highways, railways and rivers of the map carried on outwards. At night the villages
## and the lamps along the highways light up and car lights crawl along the roads; the fog
## hides the far edge. exits[i] = (x, z, kind, half width), exit_dirs[i] = (dx, dz, seed, -)
## with kind 0 road, 1 rail, 2 river.
const OUTER := """
shader_type spatial;
global uniform float night;
global uniform float gfx;
uniform vec4 exits[20];
uniform vec4 exit_dirs[20];
uniform int exit_count = 0;
uniform float map_half = 1000.0;
varying vec3 wpos;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec2(7.1, 3.3);
		a *= 0.5;
	}
	return s;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	// fields: long strips in blocks that turn with the lie of the land
	float ang = vnoise(p * 0.0004) * 3.14159;
	vec2 fp = vec2(cos(ang) * p.x + sin(ang) * p.y, -sin(ang) * p.x + cos(ang) * p.y);
	vec2 cell = floor(fp / vec2(340.0, 120.0));
	float h = hash21(cell);
	vec3 field = vec3(0.3, 0.4, 0.17);
	if (h < 0.22) field = vec3(0.56, 0.5, 0.29);
	else if (h < 0.38) field = vec3(0.4, 0.33, 0.21);
	else if (h < 0.5) field = vec3(0.62, 0.56, 0.24);
	else if (h < 0.72) field = vec3(0.26, 0.38, 0.14);
	field *= 0.85 + 0.15 * sin(fp.y * 0.9 + h * 30.0) * step(0.5, fract(h * 7.0));
	vec2 edge = abs(fract(fp / vec2(340.0, 120.0)) - 0.5);
	float hedge = smoothstep(0.485, 0.5, max(edge.x, edge.y));
	float wood = smoothstep(0.56, 0.6, fbm(p * 0.00085 + 11.0));
	vec3 col = mix(field, vec3(0.09, 0.16, 0.07), max(wood, hedge * 0.6));
	col *= 0.9 + 0.2 * vnoise(p * 0.02);
	// villages: roofs by day, lit windows and streets by night
	float vil = smoothstep(0.66, 0.72, fbm(p * 0.00055 + 31.0)) * (1.0 - wood);
	vec2 hc = floor(p / 16.0);
	float house = step(0.55, hash21(hc)) * vil;
	col = mix(col, mix(vec3(0.55, 0.3, 0.24), vec3(0.62, 0.62, 0.6), hash21(hc + 3.0)), house * 0.8);
	vec3 emit = vec3(1.0, 0.72, 0.4) * step(0.9, hash21(hc + 7.0)) * vil * 1.6;
	// highways, railways and rivers leaving the map, drawn on to the horizon
	for (int i = 0; i < 20; i++) {
		if (i >= exit_count) break;
		vec4 e = exits[i];
		vec4 ed = exit_dirs[i];
		vec2 rel = p - e.xy;
		float along = dot(rel, ed.xy);
		if (along < -60.0) continue;
		float wob = e.z > 1.5 ? sin(along * 0.0016 + ed.z) * 140.0 * smoothstep(0.0, 800.0, along) : sin(along * 0.0005 + ed.z) * 45.0 * smoothstep(0.0, 1500.0, along);
		float across = abs(dot(rel, vec2(-ed.y, ed.x)) - wob);
		float w = e.w * (e.z > 1.5 ? 1.0 + along * 0.00005 : 1.0);
		if (e.z > 1.5) {
			float wet = smoothstep(w + 2.0, w - 2.0, across);
			col = mix(col, vec3(0.04, 0.08, 0.1), wet);
			emit += vec3(0.02, 0.04, 0.07) * wet;
		} else if (e.z > 0.5) {
			col = mix(col, vec3(0.2, 0.18, 0.16), smoothstep(4.0, 2.5, across));
		} else {
			float road = smoothstep(w + 1.0, w - 0.5, across);
			col = mix(col, vec3(0.08, 0.08, 0.085), road);
			// lamps along the highway near the city, then only the traffic
			float near = smoothstep(4500.0, 800.0, along);
			float lamp = exp(-pow(across - w - 2.0, 2.0) * 0.25) * step(0.82, fract(along / 38.0)) * near;
			float cars = 0.0;
			if (gfx > 0.5) {
				float lane = step(across, w) * step(w * 0.2, across);
				float side = sign(dot(rel, vec2(-ed.y, ed.x)) - wob);
				float c = fract(along / 170.0 + side * TIME * 0.12 + ed.z);
				cars = smoothstep(0.03, 0.0, abs(c - 0.5)) * lane;
				emit += mix(vec3(1.0, 0.95, 0.85), vec3(1.0, 0.12, 0.05), step(0.0, side)) * cars * 1.4;
			}
			emit += vec3(1.0, 0.62, 0.28) * lamp * 1.8;
		}
	}
	// the map's own ground covers this plane inside the map; its border softens into the fields
	ALBEDO = col;
	ROUGHNESS = 0.95;
	EMISSION = emit * night;
}
"""

## Ground: zone colours from a small texture; inside urban areas the street grid of the
## nearest district (rotated grid, avenues every 3rd line) with sodium-lamp light pools.
const GROUND := """
shader_type spatial;
global uniform float night;
global uniform float gfx;
uniform sampler2D zone_tex : source_color, filter_linear, repeat_disable;
uniform float half_size = 1000.0;
uniform vec4 districts[32];
uniform int district_count = 0;
uniform vec4 blackouts[4];
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), u.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), u.x), u.y);
}

float power_at(vec2 p) {
	float pw = 1.0;
	for (int i = 0; i < 4; i++) {
		if (blackouts[i].w > 0.5 && distance(p, blackouts[i].xy) < blackouts[i].z) pw = 0.0;
	}
	return pw;
}

// Light of the lamps along one street line: poles on the kerb of both sides, the sides staggered;
// each lamp throws an oval pool stretched along the street. `across` is the signed distance to the
// line, `w` the half width of the road.
float lamp_line(float across, float along, float w, float period) {
	float side = step(0.0, across);
	float a = abs(across) - (w + 1.0);
	float b = mod(along + side * period * 0.5, period) - period * 0.5;
	return exp(-(a * a) / 18.0 - (b * b) / 70.0);
}

void fragment() {
	vec2 uv = (wpos.xz + half_size) / (half_size * 2.0);
	vec4 z = texture(zone_tex, uv);
	vec3 col = z.rgb;
	float n = hash2(floor(wpos.xz / 6.0));
	float fine = vnoise(wpos.xz * 0.9);
	col *= 0.9 + 0.2 * n;
	col *= 0.92 + 0.12 * vnoise(wpos.xz * 0.05);
	vec3 emit = vec3(0.0);
	float rough = 0.95;
	float urban = z.a;
	if (urban > 0.15) {
		float best = 1e12;
		vec4 d = districts[0];
		float di = 0.0;
		for (int i = 0; i < 32; i++) {
			if (i >= district_count) break;
			vec2 dd = wpos.xz - districts[i].xy;
			float l = dot(dd, dd);
			if (l < best) { best = l; d = districts[i]; di = float(i); }
		}
		float ca = cos(d.z);
		float sa = sin(d.z);
		vec2 rel = wpos.xz - d.xy;
		vec2 lp = vec2(ca * rel.x + sa * rel.y, -sa * rel.x + ca * rel.y);
		vec2 cell = floor(lp / d.w);
		vec2 f = lp - cell * d.w;
		vec2 near_line = cell + step(d.w * 0.5, f);
		vec2 dl = min(f, d.w - f);
		// signed distance to the nearest line (which side of the street we are on)
		vec2 sdl = vec2(f.x < d.w * 0.5 ? f.x : f.x - d.w, f.y < d.w * 0.5 ? f.y : f.y - d.w);
		float scale = urban > 0.7 ? 1.0 : 0.55;
		float ax = mod(near_line.x, 3.0) < 0.5 ? 1.0 : 0.0;
		float az = mod(near_line.y, 3.0) < 0.5 ? 1.0 : 0.0;
		float wx = (ax > 0.5 ? 7.0 : 4.0) * scale;
		float wz = (az > 0.5 ? 7.0 : 4.0) * scale;
		float road_x = step(dl.x, wx);
		float road_z = step(dl.y, wz);
		float road = max(road_x, road_z);
		float walk = max(step(dl.x, wx + 2.5), step(dl.y, wz + 2.5)) * (1.0 - road);
		// asphalt with patches and wear
		vec3 asphalt = vec3(0.05, 0.05, 0.058) * (0.85 + 0.3 * vnoise(lp * 0.35)) * (0.9 + 0.15 * fine);
		float mark = (step(dl.x, 0.18) * step(0.5, fract(lp.y / 8.0)) * road_x + step(dl.y, 0.18) * step(0.5, fract(lp.x / 8.0)) * road_z) * step(6.0, max(wx, wz));
		float edge_line = (step(abs(dl.x - (wx - 0.6)), 0.1) * road_x * (1.0 - road_z) + step(abs(dl.y - (wz - 0.6)), 0.1) * road_z * (1.0 - road_x)) * step(6.0, max(wx, wz));
		// courtyards inside the blocks: lawns, paving and flower beds in patches
		float inner = (1.0 - road) * (1.0 - walk) * step(0.7, urban);
		float patch = fract(sin(dot(floor(lp / 7.0), vec2(41.3, 17.9))) * 9731.7);
		vec3 lawn = mix(vec3(0.11, 0.2, 0.08), vec3(0.16, 0.24, 0.1), n) * (0.85 + 0.3 * fine);
		col = mix(col, lawn, inner * step(0.52, patch) * 0.85);
		col = mix(col, vec3(0.26, 0.25, 0.23) * (0.9 + 0.1 * fine), inner * step(patch, 0.18) * 0.7);
		// sidewalk tiles
		vec2 tile = fract(lp / 1.2);
		float joint = step(0.93, max(tile.x, tile.y));
		col = mix(col, vec3(0.22, 0.22, 0.23) * (1.0 - 0.18 * joint), walk * 0.85);
		col = mix(col, asphalt, road);
		col = mix(col, vec3(0.6, 0.6, 0.55), max(mark, edge_line) * 0.55);
		// zebra crossings just outside every junction
		float zx = road_x * (1.0 - road_z) * step(wz + 0.8, dl.y) * step(dl.y, wz + 3.8) * step(0.5, fract(lp.x / 1.2));
		float zz = road_z * (1.0 - road_x) * step(wx + 0.8, dl.x) * step(dl.x, wx + 3.8) * step(0.5, fract(lp.y / 1.2));
		col = mix(col, vec3(0.66, 0.66, 0.62), max(zx, zz) * 0.8);
		rough = mix(0.95, 0.55, road);
		// --- night: lamps along both kerbs, avenues in white LED light, side streets in sodium orange
		float led = step(0.55, fract(di * 0.618 + 0.3));
		float lx = lamp_line(sdl.x, lp.y, wx, ax > 0.5 ? 26.0 : 32.0);
		float lz = lamp_line(sdl.y, lp.x, wz, az > 0.5 ? 26.0 : 32.0);
		vec3 sodium = vec3(1.0, 0.56, 0.2);
		vec3 white = vec3(0.78, 0.8, 0.8);
		vec3 cx = mix(sodium, white, ax * led);
		vec3 cz = mix(sodium, white, az * led);
		vec3 light = cx * lx * (0.55 + 0.25 * ax * (1.0 - led * 0.5)) + cz * lz * (0.55 + 0.25 * az * (1.0 - led * 0.5));
		// the whole carriageway and the pavements catch some of it; junctions are brightest
		light += sodium * 0.07 * (road + walk * 0.6);
		light += mix(sodium, white, led * max(ax, az)) * 0.22 * exp(-(dl.x * dl.x + dl.y * dl.y) / 110.0);
		emit = light * 0.62 * power_at(wpos.xz) * scale;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	EMISSION = emit * night;
}
"""

const WATER := """
shader_type spatial;
render_mode specular_schlick_ggx;
global uniform float night;
global uniform float gfx;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
varying vec3 wpos;
varying float shore;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), u.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), u.x), u.y);
}

// What the water mirrors where the screen has nothing: the same haze and zenith as the sky.
vec3 sky_refl(vec3 r) {
	float y = max(r.y, 0.0);
	vec3 day = mix(vec3(0.66, 0.73, 0.82), vec3(0.2, 0.4, 0.74), pow(y, 0.5));
	vec3 nt = mix(vec3(0.095, 0.075, 0.082), vec3(0.008, 0.01, 0.022), pow(y, 0.4));
	return mix(day, nt, night);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// COLOR.r: 0 on the shore line, 1 out in open water (1 where the mesh has no colours)
	shore = COLOR.r;
}

void fragment() {
	float t = TIME;
	vec2 p = wpos.xz;
	// ripples: long swells and a finer chop, both drifting
	vec2 g = vec2(0.0);
	g += vec2(cos(p.x * 0.13 + t * 1.0 + p.y * 0.05), cos(p.y * 0.11 - t * 0.8 + p.x * 0.04)) * 0.035;
	g += vec2(cos((p.x + p.y) * 0.29 + t * 1.6), cos((p.x - p.y) * 0.26 - t * 1.3)) * 0.018;
	// the fine chop: crossing wave trains (smooth everywhere, no noise cells in the glints)
	for (int i = 0; i < 6; i++) {
		float a = float(i) * 2.39996 + 0.3;
		vec2 wd = vec2(cos(a), sin(a));
		float k = 0.55 + float(i) * 0.37;
		g += wd * cos(dot(p, wd) * k + t * (1.3 + float(i) * 0.45)) * 0.018 / (1.0 + float(i) * 0.35);
	}
	// calmer at night: the lights stretch into long wavering columns
	g *= mix(1.0, 0.55, night);
	vec3 nw = normalize(vec3(-g.x, 1.0, -g.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	vec3 vw = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	float cosv = clamp(dot(nw, vw), 0.0, 1.0);
	float fres = 0.02 + 0.98 * pow(1.0 - cosv, 5.0);
	// deep water dark blue-green, lighter and greener over the shallows, foam on the shore line
	vec3 deep = mix(vec3(0.02, 0.1, 0.16), vec3(0.006, 0.014, 0.028), night);
	vec3 shallow = mix(vec3(0.07, 0.19, 0.2), vec3(0.015, 0.03, 0.035), night);
	vec3 col = mix(shallow, deep, smoothstep(0.0, 0.7, shore));
	float foam = smoothstep(0.1, 0.0, shore) * smoothstep(0.35, 0.75, vnoise(p * 0.45 + vec2(t * 0.4, 0.0)));
	// the reflection: sky by default; on ultra march the mirrored ray through the depth buffer and
	// take what the screen shows where it passes behind something (bridges, lit windows, lamps)
	vec3 r = reflect(-vw, nw);
	vec3 refl = sky_refl(r);
	float hit = 0.0;
	if (gfx > 1.5) {
		// the ray follows only the long swells: the fine chop would scatter it into noise
		vec3 ns = normalize(vec3(-g.x * 0.35, 1.0, -g.y * 0.35));
		vec3 rs = reflect(-vw, ns);
		vec3 rv = normalize((VIEW_MATRIX * vec4(rs, 0.0)).xyz);
		vec3 pv = VERTEX;
		for (int i = 1; i <= 7; i++) {
			float dist = float(i * i) * 9.0;
			vec3 qv = pv + rv * dist;
			if (qv.z > -1.0) break;
			vec4 cp = PROJECTION_MATRIX * vec4(qv, 1.0);
			vec2 suv = cp.xy / cp.w * 0.5 + 0.5;
			if (suv.x < 0.0 || suv.x > 1.0 || suv.y < 0.0 || suv.y > 1.0) break;
			float dz = texture(depth_tex, suv).r;
			vec4 sp = INV_PROJECTION_MATRIX * vec4(vec3(suv, dz) * 2.0 - 1.0, 1.0);
			float scene_z = sp.z / sp.w;
			// behind something, but not far behind it (then the ray passed under a bridge, say)
			if (scene_z > qv.z + 1.5 && scene_z - qv.z < 25.0 + dist * 0.35) {
				vec3 sc = textureLod(screen_tex, suv, 0.0).rgb;
				float edge = smoothstep(0.0, 0.08, min(min(suv.x, 1.0 - suv.x), min(suv.y, 1.0 - suv.y))) * (1.0 - float(i) / 9.0);
				refl = mix(refl, sc * 0.7, edge);
				hit = edge;
				break;
			}
		}
	}
	col = mix(col, vec3(0.8, 0.85, 0.85) * mix(1.0, 0.08, night), foam * 0.5);
	// at night the water carries a faint warm sheen of the city's glow, broken by the ripples
	float sheen = smoothstep(0.35, 0.9, vnoise(p * 0.12 + vec2(t * 0.25, t * 0.1))) * (0.4 + 0.6 * fres);
	ALBEDO = col * (1.0 - fres * 0.6);
	ROUGHNESS = mix(0.06, 0.14, night);
	SPECULAR = 0.5;
	METALLIC = 0.0;
	// the mirrored world, brighter at grazing angles; lights keep their glow at night
	EMISSION = refl * mix(fres * 0.6, fres * 0.9 + 0.3 * hit + 0.06, night) * mix(0.8, 1.7, night) + vec3(0.1, 0.065, 0.045) * sheen * night * 0.35;
}
"""

## Buildings (MultiMesh of unit cubes / prisms). INSTANCE_CUSTOM: r = damage, g = seed,
## b = style / 10 (0 panel, 1 stalinka, 2 glass tower, 3 industrial, 4 private house,
## 5 church / public, 6 blank wall, 7 pitched roof).
## Every style has its own wall (prefab seams and balconies, stucco with pilasters and a cornice,
## curtain wall, sheeting), window frames, and glass that mirrors the sky by day. Behind the glass
## (ultra) a room is traced into the wall: walls, floor, ceiling lamp, furniture, curtains.
## Tall roofs carry blinking aviation lights, towers a lit crown.
const BUILDING := """
shader_type spatial;
global uniform float night;
global uniform float gfx;
uniform vec4 blackouts[4];
varying vec3 wpos;
varying vec3 lpos;
varying vec3 lnorm;
varying vec3 bsize;
varying vec3 lcam;
varying flat vec4 idata;
varying flat vec3 icol;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(vec3(i, 1.7));
	float b = hash(vec3(i + vec2(1.0, 0.0), 1.7));
	float c = hash(vec3(i + vec2(0.0, 1.0), 1.7));
	float d = hash(vec3(i + vec2(1.0, 1.0), 1.7));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float power_at(vec2 p) {
	float pw = 1.0;
	for (int i = 0; i < 4; i++) {
		if (blackouts[i].w > 0.5 && distance(p, blackouts[i].xy) < blackouts[i].z) pw = 0.0;
	}
	return pw;
}

// What a window mirrors (world direction): the same haze and zenith as the sky, the city below.
vec3 sky_refl(vec3 r) {
	float y = clamp(r.y, -0.3, 1.0);
	vec3 day = mix(vec3(0.66, 0.73, 0.82), vec3(0.16, 0.36, 0.72), pow(max(y, 0.0), 0.5));
	day = mix(day, vec3(0.28, 0.3, 0.3), smoothstep(0.0, -0.12, y));
	vec3 nt = mix(vec3(0.095, 0.075, 0.082), vec3(0.008, 0.01, 0.022), pow(max(y, 0.0), 0.4));
	nt = mix(nt, vec3(0.05, 0.035, 0.03), smoothstep(0.0, -0.12, y));
	return mix(day, nt, night);
}

// The room behind a window: the view ray goes into a box one window cell wide, one floor high and
// about as deep, and shades whatever it meets first — the back wall with a sofa, a wardrobe or a
// picture, the floor, the ceiling with its lamp, the side walls. `o` is the point on the window in
// cell units, `vd` the ray in cell units (z into the building), `h` picks the flat.
vec3 interior(vec2 o2, vec3 vd, float h, float lamp, float daylight) {
	float depth = 0.8 + h * 0.6;
	vec3 o = vec3(o2, 0.0);
	vec3 inv = 1.0 / vd;
	vec3 t0 = -o * inv;
	vec3 t1 = (vec3(1.0, 1.0, depth) - o) * inv;
	vec3 tf = max(t0, t1);
	float t = min(min(tf.x, tf.y), tf.z);
	vec3 p = o + vd * t;
	vec3 wall = vec3(0.8, 0.72, 0.58);
	if (h > 0.3) wall = vec3(0.64, 0.72, 0.74);
	if (h > 0.55) wall = vec3(0.84, 0.82, 0.78);
	if (h > 0.8) wall = vec3(0.74, 0.6, 0.52);
	vec3 c;
	if (t == tf.z) {
		c = wall;
		if (h < 0.45) {
			c = mix(c, vec3(0.3, 0.2, 0.16) * (0.7 + h), step(0.14, p.x) * step(p.x, 0.86) * step(p.y, 0.3));
		} else {
			c = mix(c, vec3(0.38, 0.27, 0.19), step(0.58, p.x) * step(p.x, 0.96) * step(p.y, 0.82));
		}
		c = mix(c, vec3(0.2, 0.3, 0.4), step(0.28, p.x) * step(p.x, 0.52) * step(0.5, p.y) * step(p.y, 0.7) * step(0.55, fract(h * 13.0)));
	} else if (t == tf.y) {
		c = vd.y < 0.0 ? vec3(0.36, 0.25, 0.16) : vec3(0.92, 0.9, 0.86);
	} else {
		c = wall * 0.8;
	}
	float dl = distance(p, vec3(0.5, 0.95, depth * 0.55));
	float light = lamp * max(1.45 - dl * 0.95, 0.12) + daylight * (0.55 - p.z * 0.35);
	return c * light;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	bsize = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	lpos = VERTEX * bsize + vec3(0.0, bsize.y * 0.5, 0.0);
	lnorm = NORMAL;
	idata = INSTANCE_CUSTOM;
	icol = COLOR.rgb;
	// the camera in the same metric local space as lpos (for the rooms behind the windows)
	vec3 cl = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	lcam = cl * bsize + vec3(0.0, bsize.y * 0.5, 0.0);
}

void fragment() {
	int style = int(idata.b * 10.0 + 0.5);
	vec3 col = icol;
	float roof = step(0.7, lnorm.y);
	float side = 1.0 - roof;
	float dmg = idata.x;
	float seed = floor(idata.y * 997.0);
	float flick = 0.6 + 0.4 * sin(TIME * 7.0 + wpos.x * 0.7 + wpos.z * 0.3);
	float pw = power_at(wpos.xz);
	vec3 nw = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 vw = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	if (style == 7) {
		// pitched roof: rows of tiles
		col *= 0.88 + 0.12 * step(0.5, fract(lpos.y * 2.6));
		col *= 0.9 + 0.1 * vnoise(lpos.xz * 1.5 + seed);
		ALBEDO = mix(col, vec3(0.03, 0.02, 0.02), dmg);
		ROUGHNESS = 0.75;
		EMISSION = vec3(1.0, 0.3, 0.05) * dmg * flick * 1.2;
	} else {
		float fh = 3.0; float ww = 3.0;
		float x0 = 0.28; float x1 = 0.72; float y0 = 0.3; float y1 = 0.82;
		float litp = 0.6;
		if (style == 1) { fh = 3.6; ww = 3.4; x0 = 0.3; x1 = 0.7; y0 = 0.2; y1 = 0.82; litp = 0.55; }
		else if (style == 2) { fh = 3.4; ww = 2.2; x0 = 0.05; x1 = 0.95; y0 = 0.08; y1 = 0.92; litp = 0.66; }
		else if (style == 3) { fh = 5.0; ww = 6.0; x0 = 0.05; x1 = 0.95; y0 = 0.55; y1 = 0.8; litp = 0.82; }
		else if (style == 4) { fh = 3.0; ww = 3.6; x0 = 0.34; x1 = 0.66; y0 = 0.35; y1 = 0.78; litp = 0.5; }
		else if (style == 5) { fh = 7.0; ww = 4.0; x0 = 0.38; x1 = 0.62; y0 = 0.18; y1 = 0.86; litp = 0.35; }
		bool on_x = abs(lnorm.x) > 0.5;
		float u = on_x ? lpos.z : lpos.x;
		float halfu = on_x ? bsize.z * 0.5 : bsize.x * 0.5;
		float v = lpos.y;
		vec2 cell = vec2((u + halfu) / ww, v / fh);
		vec2 f = fract(cell);
		// round (not floor): interpolated normals are only approximately ±1
		float face = floor(lnorm.x * 2.0 + lnorm.z * 3.0 + 5.5);
		float inside = step(abs(u), halfu - 0.9) * step(v, bsize.y - 1.0) * step(0.6, v);
		float win = step(x0, f.x) * step(f.x, x1) * step(y0, f.y) * step(f.y, y1) * side * inside;
		if (style == 6) win = 0.0;
		float h = hash(vec3(floor(cell), seed + face * 13.0));
		float lit = step(litp, h);
		float shop = 0.0;
		if ((style == 1 || style == 2) && v < fh) {
			shop = step(0.08, f.x) * step(f.x, 0.92) * step(0.12, v / fh) * step(v / fh, 0.85) * side * step(abs(u), halfu - 0.5);
			shop *= step(0.3, hash(vec3(floor(cell.x), seed * 0.31, face)));
			win = max(win, shop);
			lit = max(lit, shop);
		}
		if (style == 0) {
			// panel blocks: the stairwell column glows dimly in every section
			float sec = floor(cell.x);
			if (mod(sec + mod(seed, 7.0), 6.0) < 0.5) lit = step(0.25, h);
		}
		if (style == 2 && shop < 0.5) {
			// office towers: whole runs of a floor stay lit late
			float fl = hash(vec3(floor(cell.x / 6.0), floor(cell.y), seed + face));
			lit = step(0.5, fl) * step(0.12, h);
		}
		float wh = hash(vec3(floor(cell) + 3.0, seed * 0.13 + face));
		vec3 wincol = vec3(1.0, 0.7, 0.36);
		if (wh > 0.62) wincol = vec3(1.0, 0.86, 0.66);
		if (wh > 0.84) wincol = vec3(0.72, 0.85, 1.0);
		float tv = step(0.93, wh) * (0.55 + 0.45 * sin(TIME * (6.0 + wh * 20.0) + h * 40.0));
		if (tv > 0.0) wincol = vec3(0.45, 0.6, 1.0);
		if (style == 2) wincol = mix(vec3(0.78, 0.9, 1.0), vec3(1.0, 0.92, 0.75), step(0.7, wh));
		float bright = 0.6 + 0.8 * hash(vec3(floor(cell) + 7.0, face));
		if (shop > 0.5) { wincol = vec3(1.0, 0.82, 0.58); bright = 0.55; }
		lit *= mix(step(0.95, h) * (1.0 - shop), 1.0, pw);

		// --- the wall itself
		float streak = vnoise(vec2(u * 0.45 + seed, v * 0.06));
		if (style == 0) {
			// prefab slabs: seams between them, every slab a shade apart, some columns of balconies
			vec2 pc = vec2((u + halfu) / ww + 0.5, v / fh);
			vec2 pf = fract(pc);
			col *= 0.93 + 0.12 * hash(vec3(floor(pc), seed));
			col *= 1.0 - 0.22 * clamp(step(0.965, pf.x) + step(pf.y, 0.035), 0.0, 1.0) * side;
			float bal = step(0.6, hash(vec3(floor(cell.x), seed, 2.0))) * step(fh * 1.5, v) * inside;
			float slab = bal * step(f.y, 0.1) * step(0.12, f.x) * step(f.x, 0.88);
			float rail = bal * step(0.1, f.y) * step(f.y, 0.42) * step(0.12, f.x) * step(f.x, 0.88);
			col = mix(col, col * 0.75 + vec3(0.04), slab * side);
			col = mix(col, mix(vec3(0.55, 0.55, 0.52), vec3(0.3, 0.42, 0.5), step(0.5, hash(vec3(floor(cell), seed + 4.0)))), rail * side * 0.85);
		} else if (style == 1) {
			// stalinka: rough stucco, pilasters between the windows, rusticated ground floor, cornice
			col *= 0.94 + 0.08 * vnoise(vec2(u, v) * 1.7 + seed);
			float pil = step(abs(fract(cell.x) - 0.0) , 0.06) + step(0.94, fract(cell.x));
			col = mix(col, col * 1.08, clamp(pil, 0.0, 1.0) * step(fh, v) * side);
			float rust = step(v, fh) * step(fract(v / 0.75), 0.08) * side;
			col *= 1.0 - 0.2 * rust;
			float cornice = step(bsize.y - 1.6, v) * side;
			col = mix(col, col * 1.15, cornice);
			col *= 1.0 - 0.25 * step(bsize.y - 1.7, v) * step(v, bsize.y - 1.45) * side;
		} else if (style == 2) {
			// curtain wall: dark spandrels between the floors, fine mullions
			float mull = step(0.96, fract(cell.x)) + step(0.97, fract(cell.y));
			col = mix(col * 0.55 + vec3(0.02, 0.04, 0.06), vec3(0.12, 0.13, 0.14), clamp(mull, 0.0, 1.0) * side);
		} else if (style == 3) {
			// corrugated sheeting
			col *= 0.9 + 0.1 * sin(u * 9.0) * side;
		} else {
			col *= 0.94 + 0.08 * vnoise(vec2(u, v) * 1.3 + seed);
		}
		// rain streaks under the roof edge and grime near the street
		col *= mix(1.0, 0.86 + 0.14 * streak, side * step(0.5, float(style != 2)));
		col *= 0.72 + 0.28 * clamp(v / 8.0, 0.0, 1.0);
		col = mix(col, vec3(0.12, 0.12, 0.13), roof);

		vec3 emit = vec3(0.0);
		float rough = style == 2 ? 0.3 : 0.88;
		float metal = style == 2 ? 0.35 : 0.0;
		float spec = 0.4;
		if (roof > 0.5) {
			// roof: gravel, a lighter parapet all around, hatches and vents
			vec2 rp = lpos.xz;
			col *= 0.85 + 0.2 * vnoise(rp * 2.3 + seed);
			float edge = min(bsize.x * 0.5 - abs(rp.x), bsize.z * 0.5 - abs(rp.y));
			col = mix(col, vec3(0.34, 0.33, 0.31), step(edge, 0.5));
			vec2 hc = floor(rp / 5.0);
			col = mix(col, vec3(0.07, 0.07, 0.08), step(0.86, hash(vec3(hc, seed))) * step(0.9, edge) * step(abs(fract(rp.x / 5.0) - 0.5), 0.18) * step(abs(fract(rp.y / 5.0) - 0.5), 0.18));
		}
		if (win > 0.5) {
			// --- a window: frame, glass mirroring the sky, and the room behind it
			float fx = (f.x - x0) / (x1 - x0);
			float fy = (f.y - y0) / (y1 - y0);
			float frame = step(min(min(fx, 1.0 - fx), min(fy, 1.0 - fy)), 0.075);
			// casement windows: a mullion down the middle and a transom near the top
			if (style == 0 || style == 1 || style == 4) frame = max(frame, step(abs(fx - 0.5), 0.028) + step(abs(fy - 0.7), 0.035));
			if (style == 2 || shop > 0.5) frame = step(min(min(fx, 1.0 - fx), min(fy, 1.0 - fy)), 0.03);
			frame = clamp(frame, 0.0, 1.0);
			vec3 framecol = style == 1 ? vec3(0.86, 0.83, 0.77) : (style == 4 ? vec3(0.5, 0.36, 0.24) : vec3(0.92, 0.92, 0.9));
			if (style == 2) framecol = vec3(0.14, 0.15, 0.16);
			float cosv = clamp(dot(nw, vw), 0.0, 1.0);
			float fres = 0.06 + 0.94 * pow(1.0 - cosv, 5.0);
			vec3 refl = sky_refl(reflect(-vw, nw));
			float lamp = lit * pw * night;
			vec3 room;
			if (gfx > 1.5 && shop < 0.5) {
				vec3 L = normalize(lpos - lcam);
				vec3 n = normalize(lnorm);
				vec3 ua = on_x ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
				vec3 vd = vec3(dot(L, ua) / ww, L.y / fh, max(dot(L, -n), 0.02) / ww);
				room = interior(f, vd, h, lamp * (0.45 + 0.35 * bright), (1.0 - night) * 0.4) * mix(vec3(1.0), wincol * 1.2, 0.6);
			} else {
				room = wincol * bright * lamp * (0.85 + 0.3 * fy) + vec3(0.05, 0.06, 0.07) * (1.0 - night);
			}
			// curtains drawn from the sides; office blinds
			float cw = step(0.35, fract(h * 3.1)) * (0.12 + 0.3 * fract(h * 7.3));
			float cur = step(fx, cw) + step(1.0 - cw, fx);
			vec3 cloth = mix(vec3(0.95, 0.78, 0.55), vec3(0.62, 0.74, 0.9), step(0.6, fract(h * 5.0)));
			cloth *= 0.8 + 0.2 * sin(fx * 90.0);
			if (style == 2) {
				cur = step(0.55, fract(h * 11.0)) * step(0.5, fract(fy * 16.0));
				cloth = vec3(0.85, 0.87, 0.88);
			}
			room = mix(room, cloth * (0.08 * (1.0 - night) + lamp * bright * 0.95), clamp(cur, 0.0, 1.0) * (shop > 0.5 ? 0.0 : 1.0));
			if (tv > 0.0) room += vec3(0.25, 0.35, 0.9) * tv * lamp * 0.6;
			vec3 glass = mix(room, refl, fres * (style == 2 ? 0.95 : 0.8));
			glass = mix(glass, refl * 0.9 + room * 0.3, (1.0 - night) * (style == 2 ? 0.55 : 0.2));
			// unlit panes at night still catch a little of the city in them
			glass += vec3(0.018, 0.02, 0.03) * night * (1.0 - lit);
			emit += glass * (1.0 - frame) * 1.2 * (1.0 - dmg * step(bsize.y - fh * 3.0, v));
			col = mix(vec3(0.02, 0.025, 0.03), framecol * (0.72 + 0.28 * clamp(v / 8.0, 0.0, 1.0)), frame);
			rough = mix(0.06, 0.6, frame);
			metal = 0.0;
			spec = mix(0.6, 0.4, frame);
		}
		// the city itself lights its walls at night a little (sky glow, windows across the street)
		emit += col * vec3(0.05, 0.048, 0.07) * night * side * (1.0 - win);
		// street lamps light the lower floors warmly at night
		emit += vec3(1.0, 0.6, 0.28) * 0.05 * exp(-v / 6.0) * night * pw * side * (1.0 - win);
		// tall buildings: red aviation lights blinking on the corners of the roof, towers wear a crown
		if (bsize.y > 55.0) {
			float corner = step(halfu - 1.1, abs(u)) * step(bsize.y - 1.2, v) * side;
			float blink = step(0.5, fract(TIME * 0.6 + seed * 0.137));
			emit += vec3(1.0, 0.08, 0.04) * corner * blink * 9.0 * night;
			if (style == 2) {
				float crown = step(bsize.y - 2.6, v) * step(v, bsize.y - 1.4) * side;
				float hc = hash(vec3(seed, 9.1, 3.3));
				vec3 led = hc < 0.35 ? vec3(0.7, 0.85, 1.0) : (hc < 0.6 ? vec3(0.55, 0.35, 1.0) : (hc < 0.8 ? vec3(1.0, 0.75, 0.4) : vec3(0.3, 1.0, 0.8)));
				emit += led * crown * 2.2 * night * pw;
			}
		}
		// damage: soot, the top floors burning
		float topfire = step(bsize.y - fh * 2.2, v) * dmg * side * win;
		col = mix(col, vec3(0.03, 0.02, 0.02), dmg * (roof + side * step(bsize.y - fh * 3.0, v) * 0.8));
		emit += vec3(1.0, 0.3, 0.05) * dmg * roof * flick * 1.6 + vec3(1.0, 0.45, 0.1) * topfire * flick * 2.5;
		ALBEDO = col;
		ROUGHNESS = rough;
		METALLIC = metal;
		SPECULAR = spec;
		EMISSION = emit;
	}
}
"""

## Floodlit landmarks (cathedrals, monuments, bridges): an ordinary surface by day; at night lamps at
## the foot wash the walls with warm light, brightest low down and on the upright faces.
const FLOODLIT := """
shader_type spatial;
global uniform float night;
uniform vec3 albedo : source_color = vec3(0.8, 0.8, 0.8);
uniform float rough = 0.8;
uniform float metal = 0.0;
uniform float flood = 0.5;
uniform float day_glow = 0.0;
varying vec3 wpos;
varying vec3 wn;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = metal;
	float wash = mix(1.0, 0.4, clamp(wpos.y / 70.0, 0.0, 1.0)) * (0.5 + 0.5 * clamp(1.0 - abs(wn.y), 0.0, 1.0));
	EMISSION = albedo * (vec3(1.0, 0.85, 0.64) * flood * wash * night + day_glow * (1.0 - night));
}
"""

## Neon: signs and shop fronts that glow in their instance colour, much brighter at night.
const NEON := """
shader_type spatial;
render_mode unshaded, shadows_disabled;
global uniform float night;
uniform vec4 blackouts[4];
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
}

void fragment() {
	float pw = 1.0;
	for (int i = 0; i < 4; i++) {
		if (blackouts[i].w > 0.5 && distance(wpos.xz, blackouts[i].xy) < blackouts[i].z) pw = 0.0;
	}
	float flick = 0.92 + 0.08 * sin(TIME * 3.0 + wpos.x * 0.37);
	ALBEDO = COLOR.rgb * mix(0.55, 2.2 * flick, night) * mix(0.25, 1.0, pw);
}
"""

## Instanced point lights (street lamps, aviation warning lights, bridge lights ...).
## Screen-size aware: a quad that never shrinks below a few pixels, so distant lights twinkle.
## COLOR = light colour, INSTANCE_CUSTOM: r = blink phase, g = blink (1) / steady (0),
## b = minimum world size, a = size per unit of distance.
const LIGHTS := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
global uniform float night;
uniform vec4 blackouts[4];
varying vec3 col;
varying float ph;
varying float blink;
varying float power;

void vertex() {
	vec3 ow = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec4 c = MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	float d = max(-c.z, 0.1);
	float s = max(INSTANCE_CUSTOM.b, d * INSTANCE_CUSTOM.a);
	c.xy += VERTEX.xy * s;
	POSITION = PROJECTION_MATRIX * c;
	col = COLOR.rgb;
	ph = INSTANCE_CUSTOM.r;
	blink = INSTANCE_CUSTOM.g;
	power = 1.0;
	if (blink < 0.5) {
		for (int i = 0; i < 4; i++) {
			if (blackouts[i].w > 0.5 && distance(ow.xz, blackouts[i].xy) < blackouts[i].z) power = 0.0;
		}
	}
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float a = clamp(1.0 - r, 0.0, 1.0);
	a = a * a * (0.35 + 0.65 * a);
	float b = blink > 0.5 ? step(0.55, fract(TIME * 0.75 + ph)) : 1.0;
	ALBEDO = col * a * b * night * power * 2.4;
}
"""

## Moving car lights along street segments. Each instance is a segment start oriented along
## its local -Z. INSTANCE_CUSTOM: r = speed, g = segment length, b = phase.
const TRAFFIC := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
global uniform float night;
uniform vec4 blackouts[4];
varying vec3 col;
varying float fade;

void vertex() {
	float len = max(INSTANCE_CUSTOM.g, 1.0);
	float t = fract(INSTANCE_CUSTOM.b + TIME * INSTANCE_CUSTOM.r / len);
	vec4 lp = vec4(0.0, 0.8, -t * len, 1.0);
	vec3 ow = (MODEL_MATRIX * lp).xyz;
	vec4 c = MODELVIEW_MATRIX * lp;
	float d = max(-c.z, 0.1);
	float s = max(1.1, d * 0.0028);
	// a short streak along the road: from above, the traffic reads as moving threads of light
	vec2 mv = (MODELVIEW_MATRIX * vec4(0.0, 0.0, -1.0, 0.0)).xy;
	mv = length(mv) > 0.001 ? normalize(mv) : vec2(1.0, 0.0);
	c.xy += mv * VERTEX.x * s * 2.6 + vec2(-mv.y, mv.x) * VERTEX.y * s;
	POSITION = PROJECTION_MATRIX * c;
	col = COLOR.rgb;
	fade = smoothstep(0.0, 0.04, t) * smoothstep(1.0, 0.96, t);
	for (int i = 0; i < 4; i++) {
		if (blackouts[i].w > 0.5 && distance(ow.xz, blackouts[i].xy) < blackouts[i].z) fade *= 0.35;
	}
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float a = clamp(1.0 - r, 0.0, 1.0);
	a = a * a;
	ALBEDO = col * a * fade * night * 2.6;
}
"""

## Car bodies: same motion as TRAFFIC (identical instance data), so every body carries its lights.
const CAR_BODY := """
shader_type spatial;
varying vec3 col;

void vertex() {
	float len = max(INSTANCE_CUSTOM.g, 1.0);
	float t = fract(INSTANCE_CUSTOM.b + TIME * INSTANCE_CUSTOM.r / len);
	float fade = smoothstep(0.0, 0.03, t) * smoothstep(1.0, 0.97, t);
	VERTEX *= fade;
	VERTEX.z -= t * len;
	col = COLOR.rgb;
}

void fragment() {
	ALBEDO = col;
	ROUGHNESS = 0.3;
	METALLIC = 0.45;
}
"""

## Pedestrians walking along sidewalks. INSTANCE_CUSTOM: r = speed, g = length, b = phase,
## a = presence (at night most people are in shelters: only a < 0.3 stay outside).
const PEOPLE := """
shader_type spatial;
global uniform float night;
varying vec3 col;

void vertex() {
	float len = max(INSTANCE_CUSTOM.g, 1.0);
	float t = fract(INSTANCE_CUSTOM.b + TIME * INSTANCE_CUSTOM.r / len);
	float present = step(INSTANCE_CUSTOM.a, 1.0 - night * 0.7);
	float fade = smoothstep(0.0, 0.02, t) * smoothstep(1.0, 0.98, t) * present;
	VERTEX *= fade;
	VERTEX.y += abs(sin(TIME * 7.0 + INSTANCE_CUSTOM.b * 40.0)) * 0.06 * step(0.5, VERTEX.y);
	VERTEX.z -= t * len;
	col = COLOR.rgb;
}

void fragment() {
	ALBEDO = col;
	ROUGHNESS = 0.85;
}
"""

## Single glare sprite (engine plumes, muzzle flashes, searchlight heads).
const GLARE := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
global uniform float night;
uniform vec4 color : source_color = vec4(1.0, 0.7, 0.3, 1.0);
uniform float energy = 2.0;
uniform float base_size = 2.0;
uniform float dist_k = 0.004;
uniform float day_vis = 0.25;
uniform float flicker = 0.0;

void vertex() {
	vec4 c = MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	float d = max(-c.z, 0.1);
	float s = max(base_size, d * dist_k);
	c.xy += VERTEX.xy * s;
	POSITION = PROJECTION_MATRIX * c;
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float a = clamp(1.0 - r, 0.0, 1.0);
	a = a * a * (0.3 + 0.7 * a) + pow(a, 12.0) * 2.0;
	float f = 1.0 - flicker * 0.35 * (sin(TIME * 37.0) * 0.5 + 0.5) * (sin(TIME * 23.0 + 1.7) * 0.5 + 0.5);
	ALBEDO = color.rgb * energy * a * f * mix(day_vis, 1.0, night);
}
"""

## Full-screen night-vision filter for the gunner sight.
const NIGHT_VISION := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.3, 0.59, 0.11));
	l = pow(clamp(l, 0.0, 4.0), 0.5) * 1.7 + 0.03;
	float noise = fract(sin(dot(SCREEN_UV * vec2(1234.5, 987.6) + fract(TIME) * 91.0, vec2(12.9898, 78.233))) * 43758.5453);
	float scan = 0.93 + 0.07 * sin(SCREEN_UV.y * 1100.0 + TIME * 30.0);
	float vig = smoothstep(0.78, 0.25, length((SCREEN_UV - 0.5) * vec2(1.3, 1.0)));
	vec3 nv = vec3(0.3, 1.0, 0.42) * (l * scan + (noise - 0.5) * 0.14) * vig;
	COLOR = vec4(nv, 1.0);
}
"""


static func material(code: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


static func canvas_material(code: String) -> ShaderMaterial:
	return material(code)
