extends RefCounted
## Procedural shaders (all visuals are computed; no texture files).
## `global uniform float night` is a project-wide shader global (project.godot [shader_globals]).

## Size of the district array of the ground shader (a city may have up to this many districts).
const MAX_DISTRICTS := 96

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
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float hash3(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	// quintic: smooth in its slope too (the lit side of a cloud is a difference of two noises,
	// and with the cubic curve its kinks along every lattice line showed as facets)
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
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
	// every octave is turned against the one before: the lattice of the noise never lines up
	mat2 turn = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < 7; i++) {
		if (i >= oct) break;
		s += a * vnoise(p);
		p = turn * p * 2.07 + vec2(17.1, 9.3);
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
			cp += (vec2(vnoise(cp * 0.6 + 3.1), vnoise(cp * 0.6 + 11.7)) - 0.5) * 0.45;
			int oct = AT_CUBEMAP_PASS ? 3 : (gfx > 1.5 ? 6 : (gfx > 0.5 ? 5 : 3));
			float n = fbm(cp, oct);
			float dens = smoothstep(1.0 - cloud_cover - 0.08, 1.0 - cloud_cover + 0.3, n);
			if (dens > 0.001) {
				vec3 ld = mix(sd, md, step(0.5, night));
				vec2 toward = normalize(ld.xz + vec2(0.0001)) * 0.22;
				float n2 = fbm(cp + toward, max(oct - 2, 2));
				float lit = smoothstep(-0.1, 1.1, 0.62 + (n - n2) * 2.4);
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


## Shared by the ground of the map and the land beyond it, so the two meet without a seam: value
## noise and the open country — a patchwork of fields in long strips that turn with the lie of the
## land, hedges between them and patches of wood.
const LAND_LIB := """
float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
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

// Open country at p (metres). `px` is the size of a pixel on the ground: fine patterns fade into
// their average before they would shimmer.
vec3 fields(vec2 p, float px) {
	float ang = vnoise(p * 0.00013) * 3.14159;
	vec2 fp = vec2(cos(ang) * p.x + sin(ang) * p.y, -sin(ang) * p.x + cos(ang) * p.y);
	vec2 cs = vec2(620.0, 230.0);
	vec2 cell = floor(fp / cs);
	float h = hash21(cell);
	vec3 field = vec3(0.3, 0.4, 0.17);
	if (h < 0.22) field = vec3(0.56, 0.5, 0.29);
	else if (h < 0.38) field = vec3(0.4, 0.33, 0.21);
	else if (h < 0.5) field = vec3(0.62, 0.56, 0.24);
	else if (h < 0.72) field = vec3(0.26, 0.38, 0.14);
	float fine = 1.0 - smoothstep(1.5, 6.0, px);
	// furrows along the strip, a track along its edge
	field *= 1.0 + 0.1 * sin(fp.y * 1.6 + h * 30.0) * step(0.5, fract(h * 7.0)) * fine;
	vec2 edge = abs(fract(fp / cs) - 0.5);
	float hedge = smoothstep(0.5 - 9.0 / cs.y, 0.5, max(edge.x * cs.x / cs.y * 0.37 + 0.315, edge.y)) * (1.0 - smoothstep(20.0, 90.0, px));
	float wood = smoothstep(0.56, 0.6, fbm(p * 0.00034 + 11.0));
	vec3 col = mix(field, vec3(0.09, 0.16, 0.07), max(wood, hedge * 0.6));
	col *= 0.88 + 0.24 * vnoise(p * 0.012);
	col *= 0.94 + 0.12 * vnoise(p * 0.3) * fine;
	return mix(vec3(0.19, 0.22, 0.12), col, 0.55);
}
"""

## The land beyond the map, out to the horizon: fields, woods and villages, with the highways,
## railways and rivers of the map carried on outwards. At night the villages and the lamps along
## the highways light up and car lights crawl along the roads; the haze hides the far edge.
## exits[i] = (x, z, kind, half width), exit_dirs[i] = (dx, dz, seed, -) with kind 0 road, 1 rail,
## 2 river.
const OUTER := "shader_type spatial;\n" + LAND_LIB + """
global uniform float night;
global uniform float gfx;
uniform vec4 exits[24];
uniform vec4 exit_dirs[24];
uniform int exit_count = 0;
uniform float map_half = 15000.0;
// the open sea: shore lines (x, z, normal towards the sea) east and south of the map
uniform vec4 sea_a = vec4(0.0);
uniform vec4 sea_b = vec4(0.0);
uniform float sea_on = 0.0;
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float px = max(length(dFdx(p)), length(dFdy(p)));
	vec3 col = fields(p, px);
	float sea = 0.0;
	float beach = 0.0;
	if (sea_on > 0.5) {
		float sd = -1e6;
		float away = 0.0;
		if (p.x > map_half) {
			sd = dot(p - sea_a.xy, sea_a.zw);
			away = p.x - map_half;
		} else if (p.y > map_half) {
			sd = dot(p - sea_b.xy, sea_b.zw);
			away = p.y - map_half;
		}
		// capes and bays, growing with the distance from the map (the shore meets it exactly)
		sd += (fbm(p * 0.00022 + 5.0) - 0.5) * 5000.0 * smoothstep(0.0, 6000.0, away);
		float soft = max(px, 1.0);
		sea = smoothstep(-soft, soft, sd);
		beach = smoothstep(-70.0 - soft, -40.0, sd) * (1.0 - sea);
	}
	float wood = smoothstep(0.56, 0.6, fbm(p * 0.00034 + 11.0));
	// villages and small towns: roofs by day, lit windows and streets by night
	float vil = smoothstep(0.7, 0.76, fbm(p * 0.00021 + 31.0)) * (1.0 - wood);
	vec2 hc = floor(p / 22.0);
	float near_v = 1.0 - smoothstep(8.0, 30.0, px);
	float house = step(0.55, hash21(hc)) * vil;
	col = mix(col, mix(vec3(0.55, 0.3, 0.24), vec3(0.62, 0.62, 0.6), hash21(hc + 3.0)), house * 0.8 * near_v);
	vec3 emit = vec3(1.0, 0.72, 0.4) * mix(0.1 * vil, step(0.9, hash21(hc + 7.0)) * vil, near_v) * 1.6;
	// highways, railways and rivers leaving the map, drawn on to the horizon
	for (int i = 0; i < 24; i++) {
		if (i >= exit_count) break;
		vec4 e = exits[i];
		vec4 ed = exit_dirs[i];
		vec2 rel = p - e.xy;
		float along = dot(rel, ed.xy);
		if (along < -120.0) continue;
		float wob = e.z > 1.5 ? sin(along * 0.0005 + ed.z) * 900.0 * smoothstep(0.0, 4000.0, along) : sin(along * 0.00016 + ed.z) * 300.0 * smoothstep(0.0, 6000.0, along);
		float across = abs(dot(rel, vec2(-ed.y, ed.x)) - wob);
		float w = e.w * (e.z > 1.5 ? 1.0 + along * 0.000012 : 1.0);
		float soft = max(px * 0.7, 1.0);
		if (e.z > 1.5) {
			float wet = smoothstep(w + soft, w - soft, across);
			col = mix(col, vec3(0.04, 0.08, 0.1), wet);
			emit += vec3(0.02, 0.04, 0.07) * wet;
		} else if (e.z > 0.5) {
			col = mix(col, vec3(0.2, 0.18, 0.16), smoothstep(4.0 + soft, 2.5, across));
		} else {
			float road = smoothstep(w + soft, w - 0.5, across);
			col = mix(col, vec3(0.08, 0.08, 0.085), road);
			// lamps along the highway near the city, then only the traffic
			float nearc = smoothstep(14000.0, 2500.0, along);
			float lampd = exp(-pow(across - w - 2.0, 2.0) / (4.0 + soft * soft));
			float lamp = lampd * mix(0.18, step(0.82, fract(along / 42.0)), 1.0 - smoothstep(4.0, 16.0, px)) * nearc;
			if (gfx > 0.5) {
				float lane = step(across, w) * step(w * 0.2, across);
				float side = sign(dot(rel, vec2(-ed.y, ed.x)) - wob);
				float c = fract(along / 380.0 + side * TIME * 0.05 + ed.z);
				float cars = smoothstep(0.03, 0.0, abs(c - 0.5)) * lane * (1.0 - smoothstep(6.0, 25.0, px));
				emit += mix(vec3(1.0, 0.95, 0.85), vec3(1.0, 0.12, 0.05), step(0.0, side)) * cars * 1.4;
			}
			emit += vec3(1.0, 0.62, 0.28) * lamp * 1.8;
		}
	}
	col = mix(col, vec3(0.5, 0.45, 0.33), beach);
	emit *= night * (1.0 - sea) * (1.0 - beach);
	float rough = 0.95;
	if (sea > 0.0) {
		// the same water as on the map: dark and deep, the sky mirrored at grazing angles
		vec3 vw = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
		float fres = 0.02 + 0.98 * pow(1.0 - clamp(vw.y, 0.0, 1.0), 5.0);
		vec3 deep = mix(vec3(0.02, 0.1, 0.16), vec3(0.006, 0.014, 0.028), night);
		vec3 refl = mix(vec3(0.66, 0.73, 0.82), vec3(0.095, 0.075, 0.082), night);
		col = mix(col, deep * (1.0 - fres * 0.6), sea);
		emit += refl * mix(fres * 0.6, fres * 0.9 + 0.06, night) * mix(0.8, 1.7, night) * sea;
		rough = mix(rough, mix(0.06, 0.14, night), sea);
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	EMISSION = emit;
}
"""

## Avenues, highways and rail beds: ribbons lying on the ground (CityMap._ribbon). UV.x = metres
## across from the axis, UV.y = metres along; COLOR.r = 1 a road / 0 a rail bed, COLOR.g = half
## width / 32. The road gets its markings, the worn lanes and the pools of its lamps (which stand
## every 21 m on alternating kerbs); the rail bed its sleepers and rails. The depth is pulled
## toward the camera along the view ray, so a ribbon covers exactly the same pixels but always
## wins over the ground under it, however coarse the depth buffer is.
const ROAD := "shader_type spatial;\n" + LAND_LIB + """
global uniform float night;
global uniform float gfx;
global uniform vec4 lamp_real;
uniform float lamp_gain = 5.0;
uniform vec4 blackouts[4];
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	v.xyz *= 1.0 - 0.0012;
	POSITION = PROJECTION_MATRIX * v;
}

float power_at(vec2 p) {
	float pw = 1.0;
	for (int i = 0; i < 4; i++) {
		if (blackouts[i].w > 0.5 && distance(p, blackouts[i].xy) < blackouts[i].z) pw = 0.0;
	}
	return pw;
}

void fragment() {
	float w = COLOR.g * 32.0;
	float x = UV.x;
	float a = abs(x);
	float s = UV.y;
	float px = max(length(dFdx(UV)), length(dFdy(UV)));
	float fine = 1.0 - smoothstep(0.25, 1.2, px);
	vec3 col;
	float rough = 0.9;
	vec3 emit = vec3(0.0);
	if (COLOR.r > 0.5) {
		// asphalt: patches, cracks of a darker shade, the lanes polished by tyres
		float n1 = vnoise(wpos.xz * 0.21);
		float n2 = vnoise(wpos.xz * 2.7);
		col = vec3(0.095, 0.095, 0.1) * (0.8 + 0.4 * n1) * (0.92 + 0.14 * n2 * fine);
		col *= 0.88 + 0.24 * hash21(floor(wpos.xz * 55.0)) * fine;
		col *= 1.0 - 0.3 * smoothstep(0.62, 0.7, vnoise(wpos.xz * 0.11 + 17.0));
		col *= 1.0 - 0.2 * step(0.9, hash21(floor(vec2(s / 7.0, x / 2.6)))) * (1.0 - smoothstep(1.5, 6.0, px));
		float lanes = max(floor((w - 0.8) / 3.5), 1.0);
		float lw = (w - 0.8) / lanes;
		float in_lane = fract(a / lw);
		float track = (smoothstep(0.12, 0.26, in_lane) - smoothstep(0.34, 0.5, in_lane)) + (smoothstep(0.5, 0.66, in_lane) - smoothstep(0.74, 0.88, in_lane));
		col *= 1.0 - 0.16 * track * fine;
		rough = mix(0.86, 0.62, track * 0.5);
		// paint: a double line down the middle, dashes between the lanes, a solid line at each kerb
		float soft = max(px, 0.03);
		float centre = smoothstep(0.09 + soft, 0.09, abs(a - 0.22));
		float lane_line = smoothstep(0.07 + soft, 0.07, abs(in_lane - 0.5 > 0.0 ? (1.0 - in_lane) * lw : in_lane * lw)) * step(lw * 0.6, a) * step(a, w - 1.6) * step(fract(s / 9.0), 0.36);
		float edge = smoothstep(0.08 + soft, 0.08, abs(a - (w - 0.55)));
		float paint = max(max(centre, lane_line), edge) * (1.0 - smoothstep(0.8, 3.0, px));
		col = mix(col, vec3(0.62, 0.62, 0.58) * (0.8 + 0.2 * n2), paint * 0.8);
		// the kerb
		col = mix(col, vec3(0.3, 0.3, 0.3), smoothstep(w - 0.22, w - 0.12, a) * fine);
		if (gfx > 2.5) {
			// a damp sheen in the dips of the surface
			float wet = smoothstep(0.48, 0.8, vnoise(wpos.xz * 0.09 + 7.0)) * (1.0 - paint) * (0.2 + 0.8 * night);
			rough = mix(rough, 0.16 + 0.1 * n2, wet * 0.8);
			col *= 1.0 - 0.3 * wet;
		}
		// lamps every 21 m on alternating kerbs, their heads over the carriageway
		float light = 0.0;
		float k0 = floor((s - 14.0) / 21.0 + 0.5);
		for (int i = -1; i <= 1; i++) {
			float k = k0 + float(i);
			float side = mod(k, 2.0) < 0.5 ? 1.0 : -1.0;
			float ds = s - (14.0 + 21.0 * k);
			float da = x - side * (w - 0.3);
			light += exp(-(da * da) / 90.0 - (ds * ds) / 130.0);
		}
		float avg = 0.55;
		light = mix(avg, light, 1.0 - smoothstep(3.0, 14.0, px));
		float realk = lamp_real.z > 0.0 ? smoothstep(lamp_real.z, lamp_real.w, distance(wpos.xz, lamp_real.xy)) : 1.0;
		emit = vec3(0.82, 0.86, 0.95) * col * light * lamp_gain * mix(0.1, 1.0, realk) * power_at(wpos.xz);
	} else {
		// ballast, sleepers, two rails
		float n2 = vnoise(wpos.xz * 3.1);
		col = vec3(0.2, 0.19, 0.18) * (0.75 + 0.5 * n2);
		float sleeper = step(fract(s / 0.62), 0.42) * step(a, 1.35) * fine;
		col = mix(col, vec3(0.12, 0.1, 0.09), sleeper * 0.85);
		float rail = smoothstep(0.07 + px, 0.05, abs(a - 0.76)) * (1.0 - smoothstep(0.5, 2.0, px));
		col = mix(col, vec3(0.5, 0.5, 0.53), rail);
		rough = mix(0.95, 0.35, rail);
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	EMISSION = emit * night;
}
"""

## Ground of the map. A small texture (info_tex, one texel per ~30 m) tells the zone, how built-up
## the place is and the district; the shader blends the four texels around a point and bends the
## borders with noise, so the zones meet in soft irregular lines, not squares. Inside built-up areas
## the street grid of the nearest district is drawn exactly as the generator lays it (rotated grid,
## every ap-th line an avenue): asphalt with markings and zebra crossings, kerbs, paved sidewalks,
## lawns and yards, and the pools of the street lamps at night.
## district_a[i] = (x, z, grid angle, block), district_b[i] = (street half width, avenue half
## width, avenue period, LED lamps).
const GROUND := "shader_type spatial;\n" + LAND_LIB + """
global uniform float night;
global uniform float gfx;
global uniform vec4 lamp_real;
uniform float lamp_gain = 4.0;
uniform sampler2D info_tex : filter_nearest, repeat_disable;
uniform float half_size = 15000.0;
uniform float zn = 1024.0;
uniform vec4 district_a[96];
uniform vec4 district_b[96];
uniform int district_count = 0;
uniform vec4 blackouts[4];
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float power_at(vec2 p) {
	float pw = 1.0;
	for (int i = 0; i < 4; i++) {
		if (blackouts[i].w > 0.5 && distance(p, blackouts[i].xy) < blackouts[i].z) pw = 0.0;
	}
	return pw;
}

float zw(vec4 t, float id) {
	return step(abs(t.r * 5.0 - id), 0.25);
}

// Light of the lamps along one street line. `across` is the signed distance to the line, `along`
// the distance along it, `w` the half width of the road. Streets have a lamp every 64 m on each
// kerb, the two kerbs staggered; avenues one every 32 m on both. The lamp heads hang over the road.
float lamp_line(float across, float along, float w, float avenue) {
	float side = step(0.0, across);
	float a = abs(across) - (w - 0.6);
	float per = mix(64.0, 32.0, avenue);
	float b = mod(along + 16.0 + side * 32.0 * (1.0 - avenue), per);
	b = min(b, per - b);
	return exp(-(a * a) / 46.0 - (b * b) / 110.0);
}

void fragment() {
	vec2 p = wpos.xz;
	float px = max(length(dFdx(p)), length(dFdy(p)));
	float fine = 1.0 - smoothstep(0.3, 1.5, px);
	// --- the four texels around the point (the lookup is bent by noise: no straight borders)
	vec2 g = (p + half_size) / (2.0 * half_size) * zn - 0.5;
	g += (vec2(vnoise(p * 0.017), vnoise(p * 0.017 + 31.7)) - 0.5) * 0.9;
	ivec2 i0 = ivec2(floor(g));
	vec2 f = fract(g);
	ivec2 mx = ivec2(int(zn) - 1);
	vec4 t00 = texelFetch(info_tex, clamp(i0, ivec2(0), mx), 0);
	vec4 t10 = texelFetch(info_tex, clamp(i0 + ivec2(1, 0), ivec2(0), mx), 0);
	vec4 t01 = texelFetch(info_tex, clamp(i0 + ivec2(0, 1), ivec2(0), mx), 0);
	vec4 t11 = texelFetch(info_tex, clamp(i0 + ivec2(1, 1), ivec2(0), mx), 0);
	float w00 = (1.0 - f.x) * (1.0 - f.y);
	float w10 = f.x * (1.0 - f.y);
	float w01 = (1.0 - f.x) * f.y;
	float w11 = f.x * f.y;
	float wf = w00 * zw(t00, 1.0) + w10 * zw(t10, 1.0) + w01 * zw(t01, 1.0) + w11 * zw(t11, 1.0);
	float ww = w00 * zw(t00, 2.0) + w10 * zw(t10, 2.0) + w01 * zw(t01, 2.0) + w11 * zw(t11, 2.0);
	float wc = w00 * zw(t00, 3.0) + w10 * zw(t10, 3.0) + w01 * zw(t01, 3.0) + w11 * zw(t11, 3.0);
	float ws = w00 * zw(t00, 4.0) + w10 * zw(t10, 4.0) + w01 * zw(t01, 4.0) + w11 * zw(t11, 4.0);
	float urban = w00 * t00.g + w10 * t10.g + w01 * t01.g + w11 * t11.g;
	float n = hash21(floor(p / 6.0));
	float nz = vnoise(p * 0.9);
	// --- open country, woods, sand, the bed under the water
	vec3 col = fields(p, px);
	float forest = smoothstep(0.42, 0.56, wf);
	vec3 fcol = vec3(0.05, 0.11, 0.045) * (0.7 + 0.7 * vnoise(p * 0.11)) * (0.8 + 0.4 * vnoise(p * 0.43) * fine);
	col = mix(col, fcol, forest);
	col = mix(col, vec3(0.5, 0.45, 0.33) * (0.9 + 0.2 * nz), smoothstep(0.4, 0.55, ws));
	col = mix(col, vec3(0.03, 0.06, 0.08), smoothstep(0.45, 0.6, ww));
	vec3 emit = vec3(0.0);
	float rough = 0.95;
	float built = smoothstep(0.2, 0.3, urban) * (1.0 - forest) * (1.0 - smoothstep(0.45, 0.6, ww));
	if (built > 0.01) {
		// --- the nearest district among those of the four texels
		float best = 1e20;
		vec4 da = district_a[0];
		vec4 db = district_b[0];
		float di = 0.0;
		for (int k = 0; k < 4; k++) {
			vec4 t = k == 0 ? t00 : (k == 1 ? t10 : (k == 2 ? t01 : t11));
			int idx = int(t.b * 255.0 + 0.5);
			if (idx < district_count) {
				vec2 dd = p - district_a[idx].xy;
				float l = dot(dd, dd);
				if (l < best) { best = l; da = district_a[idx]; db = district_b[idx]; di = float(idx); }
			}
		}
		float B = da.w;
		float ca = cos(da.z);
		float sa = sin(da.z);
		vec2 rel = p - da.xy;
		vec2 lp = vec2(ca * rel.x + sa * rel.y, -sa * rel.x + ca * rel.y);
		vec2 cell = floor(lp / B);
		vec2 fr = lp - cell * B;
		vec2 near_line = cell + step(B * 0.5, fr);
		vec2 dl = min(fr, B - fr);
		// signed distance to the nearest line (which side of the street we are on)
		vec2 sdl = vec2(fr.x < B * 0.5 ? fr.x : fr.x - B, fr.y < B * 0.5 ? fr.y : fr.y - B);
		float scale = urban > 0.75 ? 1.0 : 0.7;
		float ax = mod(near_line.x, db.z) < 0.5 ? 1.0 : 0.0;
		float az = mod(near_line.y, db.z) < 0.5 ? 1.0 : 0.0;
		float wx = (ax > 0.5 ? db.y : db.x) * scale;
		float wz = (az > 0.5 ? db.y : db.x) * scale;
		float soft = max(px * 0.6, 0.02);
		float road_x = smoothstep(wx + soft, wx - soft, dl.x);
		float road_z = smoothstep(wz + soft, wz - soft, dl.y);
		float road = max(road_x, road_z);
		float sw = 3.2 * scale;
		float walk = max(smoothstep(wx + sw + soft, wx + sw - soft, dl.x), smoothstep(wz + sw + soft, wz + sw - soft, dl.y)) * (1.0 - road);
		// the ground of the city itself: beaten earth and gravel between everything else
		vec3 ccol = vec3(0.15, 0.15, 0.155) * (0.88 + 0.24 * n) * (0.9 + 0.2 * vnoise(p * 0.07));
		// yards: lawns, paths and paved patches (suburbs: gardens)
		float inner = (1.0 - road) * (1.0 - walk);
		float patch = hash21(floor(lp / 11.0) + di);
		float lawn_n = vnoise(lp * 0.045 + di * 3.1);
		vec3 lawn = mix(vec3(0.085, 0.14, 0.06), vec3(0.13, 0.17, 0.08), n) * (0.82 + 0.36 * nz * fine);
		// trodden bald patches and last year's leaves in the grass
		lawn = mix(lawn, vec3(0.17, 0.15, 0.11), smoothstep(0.55, 0.8, vnoise(lp * 0.6 + di)) * 0.6);
		float lawn_w = smoothstep(0.38, 0.5, lawn_n) * (urban > 0.75 ? 0.9 : 1.0);
		ccol = mix(ccol, lawn, inner * lawn_w);
		ccol = mix(ccol, vec3(0.25, 0.24, 0.225) * (0.9 + 0.1 * nz), inner * (1.0 - lawn_w) * step(patch, 0.3) * 0.7);
		// sidewalk slabs with their joints, the kerb stone along the road
		vec2 tq = lp / 0.5 + vec2(0.5 * floor(lp.y / 0.5), 0.0);
		vec2 tile = fract(tq);
		float joint = step(0.955, max(tile.x, tile.y)) * fine;
		vec3 slab = vec3(0.19, 0.19, 0.195) * (0.86 + 0.2 * hash21(floor(tq))) * (0.92 + 0.16 * vnoise(lp * 5.0) * fine);
		// worn darker along the middle where everybody walks, stains here and there
		slab *= 0.9 + 0.2 * vnoise(lp * 0.35 + 9.0);
		ccol = mix(ccol, slab * (1.0 - 0.3 * joint), walk * 0.94);
		float kerb = (smoothstep(0.22, 0.1, abs(dl.x - wx - 0.1)) * (1.0 - road_z) + smoothstep(0.22, 0.1, abs(dl.y - wz - 0.1)) * (1.0 - road_x)) * fine;
		// asphalt with patches and wear
		vec3 asphalt = vec3(0.092, 0.092, 0.098) * (0.8 + 0.4 * vnoise(lp * 0.27)) * (0.9 + 0.16 * nz * fine);
		// the grain of the stone in it, darker patches of new tar, cracks
		asphalt *= 0.88 + 0.24 * hash21(floor(lp * 55.0)) * fine;
		asphalt *= 1.0 - 0.3 * smoothstep(0.62, 0.7, vnoise(lp * 0.11 + 17.0));
		asphalt *= 1.0 - 0.2 * step(0.9, hash21(floor(lp / vec2(7.0, 2.6)) + di)) * (1.0 - smoothstep(1.5, 6.0, px));
		ccol = mix(ccol, asphalt, road);
		ccol = mix(ccol, vec3(0.34, 0.34, 0.33), clamp(kerb, 0.0, 1.0) * 0.8);
		// paint: the centre line, dashed lanes on the avenues, zebra crossings outside every junction
		float far_paint = 1.0 - smoothstep(0.6, 2.5, px);
		float cx_line = smoothstep(0.09 + soft, 0.09, dl.x) * road_x * (1.0 - road_z);
		float cz_line = smoothstep(0.09 + soft, 0.09, dl.y) * road_z * (1.0 - road_x);
		float dash_x = mix(step(0.5, fract(lp.y / 8.0)), 1.0, ax);
		float dash_z = mix(step(0.5, fract(lp.x / 8.0)), 1.0, az);
		float lane_x = smoothstep(0.07 + soft, 0.07, abs(dl.x - 3.4)) * ax * step(8.0, wx) * step(fract(lp.y / 9.0), 0.36) * road_x * (1.0 - road_z);
		float lane_z = smoothstep(0.07 + soft, 0.07, abs(dl.y - 3.4)) * az * step(8.0, wz) * step(fract(lp.x / 9.0), 0.36) * road_z * (1.0 - road_x);
		float mark = max(max(cx_line * dash_x, cz_line * dash_z), max(lane_x, lane_z));
		float zx = road_x * (1.0 - road_z) * step(wz + sw + 0.6, dl.y) * step(dl.y, wz + sw + 4.2) * step(0.5, fract(lp.x / 1.1)) * step(dl.x, wx - 0.4);
		float zz = road_z * (1.0 - road_x) * step(wx + sw + 0.6, dl.x) * step(dl.x, wx + sw + 4.2) * step(0.5, fract(lp.y / 1.1)) * step(dl.y, wz - 0.4);
		ccol = mix(ccol, vec3(0.62, 0.62, 0.58), max(mark, max(zx, zz)) * 0.75 * far_paint);
		rough = mix(0.95, 0.72, road);
		if (gfx > 2.5) {
			// a damp sheen on the carriageway: the lamps and the windows stretch in it
			float wet = smoothstep(0.46, 0.8, vnoise(p * 0.08 + 3.0)) * road * (0.2 + 0.8 * night);
			rough = mix(rough, 0.16 + 0.1 * nz, wet * 0.85);
			ccol *= 1.0 - 0.3 * wet;
		}
		// --- night: lamps along the kerbs, avenues in white LED light, side streets in sodium orange
		float lx = lamp_line(sdl.x, lp.y, wx, ax);
		float lz = lamp_line(sdl.y, lp.x, wz, az);
		vec3 sodium = vec3(1.0, 0.56, 0.2);
		vec3 white = vec3(0.8, 0.84, 0.9);
		vec3 cx = mix(sodium, white, ax * db.w);
		vec3 cz = mix(sodium, white, az * db.w);
		// from far away the pools melt into the even glow of a lit street
		float pools = 1.0 - smoothstep(4.0, 18.0, px);
		float gx = exp(-pow(max(dl.x - wx, 0.0), 2.0) / 60.0) * mix(0.2, 0.34, ax);
		float gz = exp(-pow(max(dl.y - wz, 0.0), 2.0) / 60.0) * mix(0.2, 0.34, az);
		vec3 light = cx * mix(gx, lx * (0.75 + 0.3 * ax), pools) + cz * mix(gz, lz * (0.75 + 0.3 * az), pools);
		// windows and porch lamps spill a little warm light into the yards
		light += sodium * (0.04 + 0.2 * smoothstep(0.58, 0.9, vnoise(lp * 0.055 + di * 1.7))) * inner;
		// near the camera the lamps are real lights (Max / UltraMax): the painted pools step back
		float realk = lamp_real.z > 0.0 ? smoothstep(lamp_real.z, lamp_real.w, distance(p, lamp_real.xy)) : 1.0;
		emit = light * ccol * lamp_gain * mix(0.1, 1.0, realk) * power_at(p) * scale;
		col = mix(col, ccol, built);
		emit *= built;
		rough = mix(0.95, rough, built);
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	EMISSION = emit * night;
}
"""

const WATER := """
shader_type spatial;
// (the mirrored sky is worked out here, in full detail: the coarse sky of the engine stays out)
render_mode specular_schlick_ggx, ambient_light_disabled;
global uniform float night;
global uniform float gfx;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
varying vec3 wpos;
varying float shore;

float hash2(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
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
	// depth pulled 0.2 % toward the camera along the view ray (same pixels): the water never
	// flickers against the riverbed under it, even with a phone's coarse depth buffer
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	v.xyz *= 0.998;
	POSITION = PROJECTION_MATRIX * v;
}

void fragment() {
	float t = TIME;
	vec2 p = wpos.xz;
	// ripples: long swells and a finer chop, both drifting
	vec2 g = vec2(0.0);
	// (a wave train shorter than a few pixels would beat against the pixel grid: it fades out
	// before that, so far water is calm and not a moire of crossing lines)
	float wpx = max(length(dFdx(p)), length(dFdy(p)));
	// the swell: three trains from different quarters, bent by a slow noise, so their crests
	// never draw a regular lattice on open water
	vec2 pb = p + (vec2(vnoise(p * 0.011), vnoise(p * 0.011 + 7.3)) - 0.5) * 70.0;
	for (int i = 0; i < 3; i++) {
		float sa = 0.35 + float(i) * 1.17;
		vec2 sd = vec2(cos(sa), sin(sa));
		float sk = 0.1 + float(i) * 0.047;
		g += sd * cos(dot(pb, sd) * sk + t * (0.8 + float(i) * 0.25)) * 0.03 * (1.0 - smoothstep(0.3, 0.9, sk * wpx));
	}
	g += vec2(cos((pb.x + pb.y) * 0.29 + t * 1.6), cos((pb.x - pb.y) * 0.26 - t * 1.3)) * 0.018 * (1.0 - smoothstep(0.3, 0.9, 0.4 * wpx));
	// the fine chop: crossing wave trains (smooth everywhere, no noise cells in the glints)
	for (int i = 0; i < 6; i++) {
		float a = float(i) * 2.39996 + 0.3;
		vec2 wd = vec2(cos(a), sin(a));
		float k = 0.55 + float(i) * 0.37;
		g += wd * cos(dot(p, wd) * k + t * (1.3 + float(i) * 0.45)) * 0.018 / (1.0 + float(i) * 0.35) * (1.0 - smoothstep(0.3, 0.9, k * wpx));
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
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
			vec4 sp = INV_PROJECTION_MATRIX * vec4(vec3(suv, dz) * 2.0 - 1.0, 1.0);
#else
			vec4 sp = INV_PROJECTION_MATRIX * vec4(suv * 2.0 - 1.0, dz, 1.0);
#endif
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
	// matt for the engine (its own screen reflections break up into blocks on a wide flat
	// surface seen at a low angle): the mirror is in EMISSION, the glints in light() below
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	METALLIC = 0.0;
	// the mirrored world, brighter at grazing angles; lights keep their glow at night
	EMISSION = refl * mix(fres * 0.6, fres * 0.9 + 0.3 * hit + 0.06, night) * mix(0.8, 1.7, night) + vec3(0.1, 0.065, 0.045) * sheen * night * 0.35;
	// daylight scattered back out of the water: its own colour where it mirrors little
	EMISSION += col * (1.0 - fres) * 0.55 * (1.0 - night);
}

void light() {
	// the sun, the moon and the lamps on the water: a tight glint inside a broad sheen
	float nl = max(dot(NORMAL, LIGHT), 0.0);
	float nh = max(dot(NORMAL, normalize(VIEW + LIGHT)), 0.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * nl / PI;
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * nl * (pow(nh, 1200.0) * 5.0 + pow(nh, 110.0) * 0.35);
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
	// one lamp under the ceiling: bright around it, the corners in half-shadow
	float dl = distance(p, vec3(0.5, 0.95, depth * 0.55));
	float light = lamp * max(1.25 - dl * 0.85, 0.16) + daylight * (0.55 - p.z * 0.35);
	return c * light;
}

// A shop behind its window: shelves of goods along the back wall, a tiled floor, light panels in
// the ceiling.
vec3 shop_room(vec2 o2, vec3 vd, float h, float lamp, float daylight) {
	float depth = 1.5;
	vec3 o = vec3(o2, 0.0);
	vec3 inv = 1.0 / vd;
	vec3 tf = max(-o * inv, (vec3(1.0, 1.0, depth) - o) * inv);
	float t = min(min(tf.x, tf.y), tf.z);
	vec3 p = o + vd * t;
	vec3 c;
	if (t == tf.z) {
		float shelf = floor(p.y * 5.0);
		float item = floor(p.x * 13.0 + shelf * 3.7);
		vec3 goods = 0.3 + 0.55 * vec3(hash(vec3(item, shelf, h)), hash(vec3(item, shelf, h + 1.0)), hash(vec3(item, shelf, h + 2.0)));
		float stocked = step(0.14, fract(p.y * 5.0)) * step(p.y, 0.8) * step(0.12, hash(vec3(item, shelf, h + 5.0)));
		c = mix(vec3(0.8, 0.78, 0.74), goods, stocked);
	} else if (t == tf.y) {
		if (vd.y < 0.0) {
			c = vec3(0.5, 0.48, 0.45) * (0.88 + 0.12 * step(0.5, fract(p.x * 3.0 + floor(p.z * 3.0) * 0.5)));
		} else {
			c = mix(vec3(0.62), vec3(1.25), step(0.6, fract(p.z * 2.0 + 0.2)) * step(0.25, fract(p.x * 2.0)));
		}
	} else {
		float shelf = floor(p.y * 5.0);
		float item = floor(p.z * 9.0 + shelf * 2.3);
		vec3 goods = 0.3 + 0.55 * vec3(hash(vec3(item, shelf, h + 7.0)), hash(vec3(item, shelf, h + 8.0)), hash(vec3(item, shelf, h + 9.0)));
		c = mix(vec3(0.74, 0.72, 0.68), goods, step(0.14, fract(p.y * 5.0)) * step(p.y, 0.8) * step(0.2, hash(vec3(item, shelf, h + 6.0))));
	}
	// brightest under the panels, the floor and the foot of the shelves in their own shadow
	float light = lamp * (0.45 + 0.55 * p.y) * (1.0 - 0.2 * p.z) + daylight * (0.6 - p.z * 0.3);
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
	} else if (style == 8) {
		// a stack of balconies down a facade (the detail stream hangs them on the panel blocks):
		// floor after floor a slab, a parapet panel and the opening above it — open and dark, or
		// glazed in with its own lit window. idata.a = floor height / 10.
		float fh8 = max(idata.a * 10.0, 2.5);
		float fl8 = floor(lpos.y / fh8);
		float fy8 = fract(lpos.y / fh8);
		bool x8 = abs(lnorm.x) > 0.5;
		float u8 = x8 ? lpos.z : lpos.x;
		float half8 = x8 ? bsize.z * 0.5 : bsize.x * 0.5;
		float h8 = hash(vec3(fl8, seed, 3.0));
		vec3 panel = mix(col, mix(vec3(0.3, 0.42, 0.5), vec3(0.62, 0.6, 0.5), step(0.5, hash(vec3(fl8, seed, 5.0)))), step(0.62, hash(vec3(fl8, seed, 7.0))));
		panel *= 0.9 + 0.1 * step(0.5, fract(u8 * 5.0));
		panel *= 0.9 + 0.14 * vnoise(vec2(u8 * 2.0 + fl8 * 7.0, lpos.y * 0.7 + seed));
		vec3 c8 = col * 0.72;
		vec3 e8 = vec3(0.0);
		float r8 = 0.85;
		if (fy8 > 0.07 && fy8 < 0.42) {
			c8 = panel;
		} else if (fy8 >= 0.42) {
			float lit8 = step(0.55, hash(vec3(fl8, seed, 11.0))) * pw * night;
			vec3 wc8 = mix(vec3(1.0, 0.72, 0.4), vec3(0.75, 0.86, 1.0), step(0.8, hash(vec3(fl8, seed, 13.0))));
			float fx8 = (u8 + half8) / (2.0 * half8);
			float gy8 = (fy8 - 0.42) / 0.58;
			if (h8 > 0.5) {
				float frame8 = clamp(step(min(min(fx8, 1.0 - fx8), min(gy8, 1.0 - gy8)), 0.05) + step(abs(fx8 - 0.5), 0.016) + step(abs(fx8 - 0.25), 0.012) + step(abs(fx8 - 0.75), 0.012), 0.0, 1.0);
				float fres8 = 0.06 + 0.94 * pow(1.0 - clamp(dot(nw, vw), 0.0, 1.0), 5.0);
				// a glazed balcony is a lumber room: its light is dim and the curtain is usually drawn
				vec3 in8 = wc8 * lit8 * (0.22 + 0.2 * hash(vec3(fl8, seed, 17.0))) * (0.75 + 0.25 * gy8) + vec3(0.05, 0.055, 0.06) * (1.0 - night);
				vec3 glass8 = mix(in8, sky_refl(reflect(-vw, nw)), fres8);
				c8 = mix(vec3(0.02, 0.025, 0.03), vec3(0.82, 0.82, 0.8), frame8);
				e8 = glass8 * (1.0 - frame8);
				r8 = mix(0.08, 0.6, frame8);
			} else {
				// the open recess: the window of the room glows deep inside, washing lines and boxes
				c8 = col * 0.28;
				e8 = wc8 * lit8 * 0.2 * smoothstep(0.1, 0.4, fx8) * smoothstep(0.9, 0.6, fx8);
			}
		}
		c8 = mix(c8, col * 0.6, roof);
		ALBEDO = c8;
		ROUGHNESS = r8;
		EMISSION = e8 * side + c8 * vec3(0.03, 0.03, 0.045) * night * side;
	} else {
		float fh = 3.0; float ww = 3.0;
		float x0 = 0.28; float x1 = 0.72; float y0 = 0.3; float y1 = 0.82;
		float litp = 0.6;
		// how deep the glass sits in the wall, metres
		float rd = 0.2;
		if (style == 1) { fh = 3.6; ww = 3.4; x0 = 0.3; x1 = 0.7; y0 = 0.2; y1 = 0.82; litp = 0.55; rd = 0.34; }
		else if (style == 2) { fh = 3.4; ww = 2.2; x0 = 0.05; x1 = 0.95; y0 = 0.08; y1 = 0.92; litp = 0.66; rd = 0.06; }
		else if (style == 3) { fh = 5.0; ww = 6.0; x0 = 0.05; x1 = 0.95; y0 = 0.55; y1 = 0.8; litp = 0.82; rd = 0.1; }
		else if (style == 4) { fh = 3.0; ww = 3.6; x0 = 0.34; x1 = 0.66; y0 = 0.35; y1 = 0.78; litp = 0.5; rd = 0.14; }
		else if (style == 5) { fh = 7.0; ww = 4.0; x0 = 0.38; x1 = 0.62; y0 = 0.18; y1 = 0.86; litp = 0.35; rd = 0.4; }
		bool on_x = abs(lnorm.x) > 0.5;
		float u = on_x ? lpos.z : lpos.x;
		float halfu = on_x ? bsize.z * 0.5 : bsize.x * 0.5;
		float v = lpos.y;
		// metres of wall per pixel: fine detail fades before it starts to shimmer
		float px = max(length(dFdx(lpos)), length(dFdy(lpos)));
		float fine = 1.0 - smoothstep(0.03, 0.16, px);
		float mid = 1.0 - smoothstep(0.12, 0.6, px);
		// the view ray in the frame of the wall: along it, up, into it
		vec3 Lr = normalize(lpos - lcam);
		vec3 nl = normalize(lnorm);
		vec3 ua = on_x ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
		vec3 ray = vec3(dot(Lr, ua), Lr.y, max(dot(Lr, -nl), 0.05));
		vec2 cell = vec2((u + halfu) / ww, v / fh);
		vec2 f = fract(cell);
		// round (not floor): interpolated normals are only approximately ±1
		float face = floor(lnorm.x * 2.0 + lnorm.z * 3.0 + 5.5);
		float inside = step(abs(u), halfu - 0.9) * step(v, bsize.y - 1.0) * step(0.6, v);
		float h = hash(vec3(floor(cell), seed + face * 13.0));
		float lit = step(litp, h);
		// shop fronts along the ground floor of the street houses and the towers
		float shop = 0.0;
		float signb = 0.0;
		if ((style == 1 || style == 2) && v < fh) {
			float sh = hash(vec3(floor(cell.x), seed * 0.31, face));
			if (sh > 0.3 && abs(u) < halfu - 0.5) {
				shop = 1.0;
				x0 = 0.07; x1 = 0.93; y0 = 0.1; y1 = 0.78;
				rd = 0.12;
				inside = side;
				lit = step(0.52, fract(sh * 7.3));
				// the sign over the window
				signb = step(0.83, f.y) * step(f.y, 0.96) * step(0.1, f.x) * step(f.x, 0.9) * step(0.45, fract(sh * 3.1)) * side;
			}
		}
		float open = step(x0, f.x) * step(f.x, x1) * step(y0, f.y) * step(f.y, y1) * side * inside;
		if (style == 6) open = 0.0;
		// the glass is set back: where the ray reaches its plane inside the opening we see the
		// window, otherwise the side of the opening (the reveal: dark soffit, pale sill)
		float win = 0.0;
		float reveal = 0.0;
		float rshade = 1.0;
		vec2 fg = f;
		if (open > 0.5) {
			vec2 dsh = ray.xy / ray.z * rd / vec2(ww, fh);
			fg = f + dsh;
			if (fg.x > x0 && fg.x < x1 && fg.y > y0 && fg.y < y1) {
				win = 1.0;
			} else {
				reveal = 1.0;
				float tx = dsh.x > 0.0 ? (x1 - f.x) / dsh.x : (dsh.x < 0.0 ? (x0 - f.x) / dsh.x : 1e9);
				float ty = dsh.y > 0.0 ? (y1 - f.y) / dsh.y : (dsh.y < 0.0 ? (y0 - f.y) / dsh.y : 1e9);
				rshade = tx < ty ? 0.66 : (dsh.y > 0.0 ? 0.42 : 1.12);
			}
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
		// the lamp of the flat: warm bulbs mostly, some daylight LEDs, a few rooms lit by the TV only
		vec3 wincol = vec3(1.0, 0.66, 0.34);
		if (wh > 0.45) wincol = vec3(1.0, 0.8, 0.56);
		if (wh > 0.78) wincol = vec3(0.86, 0.9, 1.0);
		float tv = step(0.93, wh) * (0.55 + 0.45 * sin(TIME * (6.0 + wh * 20.0) + h * 40.0));
		if (tv > 0.0) wincol = vec3(0.45, 0.6, 1.0);
		if (style == 2) wincol = mix(vec3(0.78, 0.9, 1.0), vec3(1.0, 0.92, 0.75), step(0.7, wh));
		float bright = 0.35 + 0.65 * hash(vec3(floor(cell) + 7.0, face));
		if (shop > 0.5) { wincol = mix(vec3(1.0, 0.9, 0.74), vec3(0.86, 0.93, 1.0), step(0.5, fract(wh * 5.0))); bright = 1.0; }
		lit *= mix(step(0.95, h) * (1.0 - shop), 1.0, pw);

		// --- the wall itself
		float streak = vnoise(vec2(u * 0.45 + seed, v * 0.06));
		// plaster and concrete are never one flat colour: big damp patches, a finer mottle, grain
		col *= 0.9 + 0.2 * vnoise(vec2(u, v) * 0.11 + seed * 0.37);
		col *= 1.0 + (vnoise(vec2(u, v) * 1.9 + seed) - 0.5) * 0.12 * mid;
		col *= 1.0 + (vnoise(vec2(u, v) * 17.0) - 0.5) * 0.1 * fine;
		// the sill under every window and the damp streaks that run down from its corners
		float in_x = step(x0 - 0.03, f.x) * step(f.x, x1 + 0.03);
		float below = step(f.y, y0) * inside * side * (1.0 - shop) * float(style != 6 && style != 2);
		float sill = below * in_x * step(y0 - 0.085 / fh, f.y);
		float under = below * in_x * step(y0 - 0.2 / fh, f.y) * (1.0 - sill);
		float drip = below * (smoothstep(0.06, 0.0, abs(f.x - x0)) + smoothstep(0.06, 0.0, abs(f.x - x1))) * smoothstep(0.0, y0, f.y);
		if (style == 0) {
			// prefab slabs: seams between them, every slab a shade apart, some columns of balconies
			vec2 pc = vec2((u + halfu) / ww + 0.5, v / fh);
			vec2 pf = fract(pc);
			col *= 0.93 + 0.12 * hash(vec3(floor(pc), seed));
			float seam = clamp(step(0.975, pf.x) + step(pf.y, 0.022), 0.0, 1.0) * side;
			col *= 1.0 - 0.34 * seam * mid;
			// the pebble-dash face of the slab
			col *= 1.0 + (hash(vec3(floor(vec2(u, v) * 26.0), 3.0)) - 0.5) * 0.16 * fine * side;
			float bal = step(0.6, hash(vec3(floor(cell.x), seed, 2.0))) * step(fh * 1.5, v) * inside;
			float slab = bal * step(f.y, 0.1) * step(0.12, f.x) * step(f.x, 0.88);
			float rail = bal * step(0.1, f.y) * step(f.y, 0.42) * step(0.12, f.x) * step(f.x, 0.88);
			col = mix(col, col * 0.75 + vec3(0.04), slab * side);
			col = mix(col, mix(vec3(0.55, 0.55, 0.52), vec3(0.3, 0.42, 0.5), step(0.5, hash(vec3(floor(cell), seed + 4.0)))), rail * side * 0.85);
		} else if (style == 1) {
			// a street house of stucco: a rusticated ground floor under a string course, pilasters
			// between the windows, a moulded surround to every window, a cornice under the roof
			float gf = step(v, fh);
			float groove = gf * (step(fract(v / 0.6), 0.07) + step(fract((u + floor(v / 0.6) * 0.45) / 1.3), 0.035) * mid) * (1.0 - shop * step(0.1, f.y) * step(f.y, 0.8) * step(0.07, f.x) * step(f.x, 0.93));
			col *= 1.0 - 0.3 * clamp(groove, 0.0, 1.0) * side;
			col *= 1.0 - 0.07 * gf * side;
			float course = step(fh - 0.32, v) * step(v, fh) * side;
			col = mix(col, col * 1.16, course);
			col *= 1.0 - 0.3 * step(fh - 0.4, v) * step(v, fh - 0.32) * side;
			float pil = (step(f.x, 0.07) + step(0.93, f.x)) * step(fh, v) * step(v, bsize.y - 1.6) * side;
			col = mix(col, col * 1.1, clamp(pil, 0.0, 1.0));
			col *= 1.0 - 0.22 * step(0.07, f.x) * step(f.x, 0.085) * step(fh, v) * side * mid;
			// the surround: a paler band round the opening with a shadow under its hood
			float sx = step(x0 - 0.045, f.x) * step(f.x, x1 + 0.045);
			float sy = step(y0 - 0.02, f.y) * step(f.y, y1 + 0.05);
			float surround = sx * sy * (1.0 - open) * step(fh, v) * inside * side;
			col = mix(col, col * 1.2 + vec3(0.03), surround * 0.8);
			float hood = sx * step(y1 + 0.05, f.y) * step(f.y, y1 + 0.075) * step(fh, v) * inside * side;
			col *= 1.0 - 0.3 * hood * mid;
			float cornice = step(bsize.y - 1.6, v) * side;
			col = mix(col, col * 1.18, cornice);
			col *= 1.0 - 0.32 * step(bsize.y - 1.85, v) * step(v, bsize.y - 1.6) * side;
			col *= 1.0 - 0.14 * step(fract((u + halfu) / 0.42), 0.4) * step(bsize.y - 1.3, v) * step(v, bsize.y - 0.9) * side * fine;
		} else if (style == 2) {
			// curtain wall: dark spandrels between the floors, fine mullions
			float mull = step(0.96, fract(cell.x)) + step(0.97, fract(cell.y));
			col = mix(col * 0.55 + vec3(0.02, 0.04, 0.06), vec3(0.12, 0.13, 0.14), clamp(mull, 0.0, 1.0) * side);
		} else if (style == 3) {
			// corrugated sheeting, rust creeping up from the ground and down from the fixings
			col *= 0.9 + 0.1 * sin(u * 9.0) * side;
			col = mix(col, vec3(0.3, 0.17, 0.1), smoothstep(0.62, 0.9, vnoise(vec2(u * 0.7 + seed, v * 0.25))) * 0.4 * side);
		}
		col = mix(col, vec3(0.8, 0.79, 0.76) * (0.9 + 0.1 * streak), sill);
		col *= 1.0 - 0.3 * under * mid;
		col *= 1.0 - 0.16 * drip * mid;
		// rain streaks under the roof edge, the plinth and the grime near the street
		col *= mix(1.0, 0.84 + 0.16 * streak, side * step(0.5, float(style != 2)));
		col *= 1.0 - 0.16 * smoothstep(bsize.y - 4.0, bsize.y, v) * smoothstep(0.35, 0.75, streak) * side * float(style != 2);
		float plinth = step(v, 0.7) * side * (1.0 - shop * step(0.07, f.x) * step(f.x, 0.93)) * float(style != 2);
		col = mix(col, vec3(0.2, 0.2, 0.21) * (0.85 + 0.3 * vnoise(vec2(u, v) * 2.3)), plinth * 0.85);
		col *= 0.8 + 0.2 * clamp(wpos.y / 5.0, 0.0, 1.0);
		col = mix(col, vec3(0.12, 0.12, 0.13), roof);

		vec3 emit = vec3(0.0);
		float rough = style == 2 ? 0.3 : 0.9;
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
		if (signb > 0.5) {
			// a shop sign: a coloured board by day, its letters glowing at night
			float sh2 = hash(vec3(floor(cell.x), seed * 0.77, face + 2.0));
			vec3 board = sh2 < 0.3 ? vec3(0.62, 0.1, 0.1) : (sh2 < 0.55 ? vec3(0.08, 0.2, 0.5) : (sh2 < 0.75 ? vec3(0.08, 0.36, 0.2) : vec3(0.12, 0.12, 0.13)));
			float lx = (f.x - 0.1) / 0.8;
			float ly = (f.y - 0.83) / 0.13;
			float nlet = 5.0 + floor(sh2 * 7.0);
			float letter = step(0.16, fract(lx * nlet)) * step(fract(lx * nlet), 0.84) * step(0.24, ly) * step(ly, 0.76) * step(0.12, lx) * step(lx, 0.88);
			letter *= step(0.12, hash(vec3(floor(lx * nlet), sh2 * 91.0, 4.0)));
			vec3 lc = sh2 > 0.75 ? vec3(1.0, 0.8, 0.3) : vec3(0.95, 0.95, 0.9);
			col = mix(board, lc, letter * mid);
			emit += (lc * letter * 1.1 + board * 0.22) * night * pw * step(0.3, fract(sh2 * 17.0)) * mix(0.5, 1.0, mid);
			rough = 0.45;
		}
		if (reveal > 0.5) {
			col *= rshade;
		}
		if (win > 0.5) {
			// --- a window: the frame, the glass that mirrors the sky, the room behind it
			vec2 g = (fg - vec2(x0, y0)) / vec2(x1 - x0, y1 - y0);
			float fx = g.x;
			float fy = g.y;
			// frame bars a few centimetres wide whatever the size of the opening
			float bx = 0.06 / (ww * (x1 - x0));
			float by = 0.06 / (fh * (y1 - y0));
			float frame = 1.0 - step(bx, fx) * step(fx, 1.0 - bx) * step(by, fy) * step(fy, 1.0 - by);
			float old = step(0.55, fract(wh * 9.7));
			if (shop > 0.5) {
				// a shop front: a door of glass in one of them, slim posts
				frame = max(frame, step(abs(fract(fx * 3.0 + 0.5) - 0.5) / 3.0, bx * 0.6));
			} else if (style == 0) {
				// panel flats: a wide pane and a narrow opening one
				frame = max(frame, step(abs(fx - 0.62), bx * 0.7));
				frame = max(frame, step(abs(fy - 0.72), by * 0.6) * step(0.62, fx) * old);
			} else if (style == 1 || style == 4) {
				// casements: a mullion down the middle and a transom near the top
				frame = max(frame, step(abs(fx - 0.5), bx * 0.75));
				frame = max(frame, step(abs(fy - 0.72), by * 0.7));
				frame = max(frame, step(abs(fy - 0.36), by * 0.5) * old);
			} else if (style == 3) {
				// factory glazing: a grid of small panes
				frame = max(frame, max(step(abs(fract(fx * 8.0 + 0.5) - 0.5) / 8.0, bx * 0.5), step(abs(fract(fy * 3.0 + 0.5) - 0.5) / 3.0, by * 0.5)));
			} else if (style == 5) {
				frame = max(frame, step(abs(fract(fx * 2.0 + 0.5) - 0.5) / 2.0, bx * 0.7));
				frame = max(frame, step(abs(fract(fy * 4.0 + 0.5) - 0.5) / 4.0, by * 0.6));
			}
			frame = clamp(frame, 0.0, 1.0) * mix(0.35, 1.0, mid);
			// white plastic in the renovated flats, brown paint in the old ones
			vec3 framecol = mix(vec3(0.84, 0.84, 0.82), vec3(0.3, 0.2, 0.14), old * float(style == 0 || style == 1 || style == 4));
			if (style == 2 || shop > 0.5) framecol = vec3(0.1, 0.11, 0.12);
			if (style == 3) framecol = vec3(0.2, 0.2, 0.2);
			float cosv = clamp(dot(nw, vw), 0.0, 1.0);
			float f0 = style == 2 ? 0.3 : 0.07;
			float fres = f0 + (1.0 - f0) * pow(1.0 - cosv, 5.0);
			vec3 rdir = reflect(-vw, nw);
			vec3 refl = sky_refl(rdir);
			// in a street the low sky is hidden by the houses across it: the panes mirror their walls
			vec3 across = mix(vec3(0.3, 0.3, 0.31), vec3(0.03, 0.024, 0.02), night) * (0.7 + 0.6 * hash(vec3(floor(cell), face + 33.0)));
			float canyon = (1.0 - smoothstep(0.1, 0.5, rdir.y)) * (1.0 - 0.7 * smoothstep(8.0, 40.0, wpos.y));
			refl = mix(refl, across, canyon * (style == 2 ? 0.6 : 1.0));
			// panes are never quite flat: the mirrored sky wobbles from one to the next
			refl *= 0.86 + 0.28 * hash(vec3(floor(cell), face + 21.0));
			float lamp = lit * pw * night;
			float daylight = (1.0 - night) * 0.34;
			vec3 vd = vec3(ray.x / ww, ray.y / fh, ray.z / ww);
			vec3 room;
			if (shop > 0.5) {
				room = shop_room(clamp(fg, 0.01, 0.99), vd, h, lamp * 0.62, daylight) * wincol;
			} else if (gfx > 1.5) {
				room = interior(clamp(fg, 0.01, 0.99), vd, h, lamp * (0.4 + 0.5 * bright), daylight) * mix(vec3(1.0), wincol, 0.75);
			} else {
				room = wincol * (0.3 + 0.5 * bright) * lamp * (0.85 + 0.3 * fy) + vec3(0.05, 0.06, 0.07) * (1.0 - night);
			}
			if (shop < 0.5) {
				// what hangs in the window: net curtains that glow evenly from the lamp behind them,
				// heavy ones drawn from the sides, a pot plant on the sill; blinds in the offices
				float glow = lamp * (0.3 + 0.5 * bright);
				float net = step(0.42, fract(h * 17.3)) * float(style != 2 && style != 3);
				vec3 netc = mix(vec3(0.9, 0.88, 0.82), vec3(0.84, 0.8, 0.7), fract(h * 29.0)) * (0.9 + 0.1 * sin(fx * 70.0 + sin(fy * 9.0)));
				vec3 neted = netc * (glow * wincol * 0.95 + daylight * 0.9) + room * 0.18;
				room = mix(room, neted, net * (0.7 + 0.25 * fract(h * 41.0)));
				float cw = step(0.35, fract(h * 3.1)) * (0.1 + 0.26 * fract(h * 7.3));
				float cur = clamp(step(fx, cw) + step(1.0 - cw, fx), 0.0, 1.0);
				vec3 cloth = mix(vec3(0.74, 0.56, 0.38), vec3(0.42, 0.5, 0.62), step(0.6, fract(h * 5.0)));
				cloth = mix(cloth, vec3(0.6, 0.24, 0.22), step(0.85, fract(h * 23.0)));
				cloth *= 0.78 + 0.22 * sin(fx * 90.0);
				if (style == 2) {
					cur = step(0.55, fract(h * 11.0)) * step(0.5, fract(fy * 16.0));
					cloth = vec3(0.85, 0.87, 0.88);
				}
				room = mix(room, cloth * (glow * wincol * 0.6 + daylight * 0.75), cur);
				float plant = step(0.7, fract(h * 13.7)) * float(style != 2 && style != 3);
				float leaf = plant * step(fy, 0.16 + 0.12 * sin(fx * 31.0 + h * 9.0)) * step(abs(fx - (0.25 + 0.5 * fract(h * 3.3))), 0.13);
				room = mix(room, vec3(0.05, 0.12, 0.04) * (glow + daylight * 2.0), leaf);
				if (tv > 0.0) room += vec3(0.25, 0.35, 0.9) * tv * lamp * 0.35;
			}
			vec3 glass = room * (1.0 - fres) + refl * fres;
			// unlit panes at night still catch the lamps of the street in them
			glass += (vec3(0.012, 0.014, 0.022) + vec3(1.0, 0.62, 0.3) * 0.035 * exp(-wpos.y / 9.0) * pw) * night * (1.0 - lit);
			emit += glass * (1.0 - frame) * (1.0 - dmg * step(bsize.y - fh * 3.0, v));
			col = mix(vec3(0.02, 0.025, 0.03), framecol * (0.72 + 0.28 * clamp(v / 8.0, 0.0, 1.0)), frame);
			rough = mix(0.05, 0.55, frame);
			metal = 0.0;
			spec = mix(0.6, 0.4, frame);
		}
		// the city itself lights its walls at night a little (sky glow, windows across the street)
		emit += col * vec3(0.035, 0.034, 0.05) * night * side * (1.0 - win);
		// street lamps wash the lower floors warmly at night
		emit += col * vec3(1.0, 0.62, 0.3) * 0.16 * exp(-max(wpos.y - 2.0, 0.0) / 6.0) * night * pw * side * (1.0 - win);
		// a lit window throws its light on the sill and the reveal around it
		emit += col * wincol * 0.25 * lit * pw * night * max(reveal, sill) * (0.4 + 0.6 * bright);
		// tall buildings: red aviation lights blinking on the corners of the roof, towers wear a crown
		if (bsize.y > 62.0) {
			float corner = step(halfu - 1.1, abs(u)) * step(bsize.y - 1.2, v) * side * mid;
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
	ALBEDO = COLOR.rgb * mix(0.55, 0.95 * flick, night) * mix(0.25, 1.0, pw);
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
	float s = max(INSTANCE_CUSTOM.b, d * INSTANCE_CUSTOM.a) * 3.0;
	c.xy += VERTEX.xy * s;
	POSITION = PROJECTION_MATRIX * c;
	col = COLOR.rgb;
	ph = INSTANCE_CUSTOM.r;
	blink = INSTANCE_CUSTOM.g;
	// a light kept visible by its smallest size is fainter than it is drawn; the haze takes more
	power = pow(clamp(INSTANCE_CUSTOM.b / max(d * INSTANCE_CUSTOM.a, 0.001), 0.0, 1.0), 0.35) * exp(-d * 0.00005);
	if (blink < 0.5) {
		for (int i = 0; i < 4; i++) {
			if (blackouts[i].w > 0.5 && distance(ow.xz, blackouts[i].xy) < blackouts[i].z) power = 0.0;
		}
	}
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float a = clamp(1.0 - r * 3.0, 0.0, 1.0);
	// a hot core and a wide faint halo
	a = a * a * (0.35 + 0.65 * a) + pow(max(1.0 - r, 0.0), 3.0) * 0.06;
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

## What a car is made of, by the part id in UV.x (Meshes.car_mesh): paint in the instance colour
## with a clear coat, dark glass that mirrors the sky, rubber, lamp lenses, chrome. `lit` = the
## lamps are on (moving traffic at night).
const CAR_FRAG := """
float chash(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void fragment() {
	int part = int(part_id + 0.5);
	vec3 c = col;
	float rough = 0.32;
	float metal = 0.55;
	float spec = 0.5;
	vec3 emit = vec3(0.0);
	if (part == 1) {
		c = vec3(0.012, 0.015, 0.018);
		rough = 0.04;
		metal = 0.0;
		spec = 0.55;
	} else if (part == 2) {
		c = vec3(0.035, 0.035, 0.038);
		rough = 0.85;
		metal = 0.0;
		spec = 0.2;
	} else if (part == 3) {
		c = vec3(0.6, 0.62, 0.6);
		rough = 0.12;
		metal = 0.6;
		emit = vec3(1.0, 0.95, 0.82) * lit * 5.0;
	} else if (part == 4) {
		c = vec3(0.45, 0.03, 0.02);
		rough = 0.2;
		metal = 0.0;
		emit = vec3(1.0, 0.06, 0.03) * lit * 2.0;
	} else if (part == 5) {
		c = vec3(0.7, 0.71, 0.73);
		rough = 0.25;
		metal = 0.9;
	} else if (part == 6) {
		// the number plate
		c = vec3(0.82, 0.82, 0.8);
		rough = 0.5;
		metal = 0.0;
	} else {
		// lacquer over the paint; road dust on the lower panels, a different sheen from car to car
		float kind = chash(vec3(col * 7.0));
		c *= 0.9 + 0.1 * kind;
		float dust = (1.0 - smoothstep(0.22, 0.7, ly)) * (0.25 + 0.5 * kind);
		c = mix(c, vec3(0.2, 0.19, 0.17), dust * 0.5);
		rough = mix(0.3, 0.6, dust);
		metal = mix(0.25, 0.7, step(0.45, kind));
		CLEARCOAT = 1.0 - dust;
		CLEARCOAT_ROUGHNESS = 0.06;
	}
	ALBEDO = c;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
	EMISSION = emit;
}
"""

## Parked cars (the detail stream).
const CAR := """
shader_type spatial;
global uniform float night;
varying vec3 col;
varying float part_id;
varying float lit;
varying float ly;

void vertex() {
	col = COLOR.rgb;
	part_id = UV.x;
	lit = 0.0;
	ly = VERTEX.y;
}
""" + CAR_FRAG

## Car bodies of the traffic: same motion as TRAFFIC (identical instance data), so every body
## carries its lights.
const CAR_BODY := """
shader_type spatial;
global uniform float night;
varying vec3 col;
varying float part_id;
varying float lit;
varying float ly;

void vertex() {
	ly = VERTEX.y;
	float len = max(INSTANCE_CUSTOM.g, 1.0);
	float t = fract(INSTANCE_CUSTOM.b + TIME * INSTANCE_CUSTOM.r / len);
	float fade = smoothstep(0.0, 0.03, t) * smoothstep(1.0, 0.97, t);
	VERTEX *= fade;
	VERTEX.z -= t * len;
	col = COLOR.rgb;
	part_id = UV.x;
	lit = night;
}
""" + CAR_FRAG

## Pedestrians walking along sidewalks. INSTANCE_CUSTOM: r = speed, g = length, b = phase,
## a = presence (at night most people are in shelters: only a < 0.3 stay outside). UV.x marks the
## skin (1), trousers (2) and hair (3); the coat is the instance colour.
const PEOPLE := """
shader_type spatial;
global uniform float night;
varying vec3 col;
varying float part_id;

void vertex() {
	float len = max(INSTANCE_CUSTOM.g, 1.0);
	float t = fract(INSTANCE_CUSTOM.b + TIME * INSTANCE_CUSTOM.r / len);
	float present = step(INSTANCE_CUSTOM.a, 1.0 - night * 0.7);
	float fade = smoothstep(0.0, 0.02, t) * smoothstep(1.0, 0.98, t) * present;
	// the stride: legs and arms swing against each other
	float ph = TIME * 6.5 * INSTANCE_CUSTOM.r / 1.4 + INSTANCE_CUSTOM.b * 40.0;
	float limb = step(0.05, abs(VERTEX.x)) * sign(VERTEX.x);
	float leg = step(VERTEX.y, 0.86) * (0.86 - VERTEX.y);
	float arm = step(0.82, VERTEX.y) * step(0.2, abs(VERTEX.x)) * (1.45 - VERTEX.y);
	VERTEX.z += sin(ph) * limb * (leg * 0.45 - arm * 0.4);
	VERTEX.y += abs(sin(ph)) * 0.035 * step(0.5, VERTEX.y);
	VERTEX *= fade;
	VERTEX.z -= t * len;
	col = COLOR.rgb;
	part_id = UV.x;
}

void fragment() {
	int part = int(part_id + 0.5);
	vec3 c = col;
	if (part == 1) c = vec3(0.86, 0.68, 0.56);
	else if (part == 2) c = vec3(0.12, 0.13, 0.17);
	else if (part == 3) c = vec3(0.14, 0.1, 0.07);
	ALBEDO = c;
	ROUGHNESS = 0.85;
}
"""

## Trees (Meshes.deciduous_mesh / conifer_mesh): the instance colour is the leaf tint, UV.x = 1 on
## the wood, UV.y the height inside a crown. Leaves in patches of light and shade, darker inside
## and underneath, a little light shining through from behind, the crowns swaying in the wind; at
## night the street below lights them faintly.
const TREE := """
shader_type spatial;
render_mode cull_disabled;
global uniform float night;
global uniform float gfx;
global uniform vec4 lamp_real;
varying vec3 leaf;
varying float part;
varying float hgt;
varying vec3 lp;
varying vec3 wp;
varying float seed;

float thash(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

float tnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(thash(i), thash(i + vec3(1, 0, 0)), u.x), mix(thash(i + vec3(0, 1, 0)), thash(i + vec3(1, 1, 0)), u.x), u.y);
	float b = mix(mix(thash(i + vec3(0, 0, 1)), thash(i + vec3(1, 0, 1)), u.x), mix(thash(i + vec3(0, 1, 1)), thash(i + vec3(1, 1, 1)), u.x), u.y);
	return mix(a, b, u.z);
}

void vertex() {
	leaf = COLOR.rgb;
	part = UV.x;
	hgt = UV.y;
	seed = INSTANCE_CUSTOM.r;
	lp = VERTEX;
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float wood = step(0.5, part) * step(part, 1.5);
	float sway = sin(TIME * 1.2 + wp.x * 0.09 + wp.z * 0.06 + seed * 6.0) * 0.02 + sin(TIME * 3.1 + wp.x * 0.6 + wp.y * 0.4) * 0.006 * (1.0 - wood);
	float k = max(VERTEX.y - 1.5, 0.0);
	VERTEX.x += sway * k;
	VERTEX.z += sway * 0.6 * k;
}

void fragment() {
	vec3 c;
	float rough = 0.85;
	if (part > 0.5 && part < 1.5) {
		// bark: long fissures up the trunk, moss on the weather side
		c = vec3(0.19, 0.15, 0.115) * (0.6 + 0.7 * tnoise(lp * vec3(9.0, 1.4, 9.0))) * (0.85 + 0.3 * tnoise(lp * vec3(31.0, 5.0, 31.0)));
		c = mix(c, vec3(0.16, 0.2, 0.1), smoothstep(0.55, 0.8, tnoise(lp * 1.7 + seed)) * 0.35);
	} else {
		float cut = 1.0;
		float tone = 1.0;
		if (part > 3.5) {
			// a spray of leaves on a card: every cell of it holds one leaf at its own angle (or
			// none), and everything between the leaves is cut away
			vec2 q = UV2 * 7.0;
			vec2 id = floor(q);
			vec2 f = fract(q) - 0.5;
			float hs = thash(vec3(id, seed * 7.0 + lp.y * 0.0 + 1.0));
			f += (vec2(hs, fract(hs * 7.3)) - 0.5) * 0.36;
			float ang = hs * 6.2832;
			vec2 r = vec2(cos(ang) * f.x + sin(ang) * f.y, -sin(ang) * f.x + cos(ang) * f.y);
			float lf = 1.0 - smoothstep(0.4, 0.46, length(r * vec2(1.0, 1.7)));
			lf *= step(0.1, hs) * (1.0 - smoothstep(0.34 + 0.12 * fract(hs * 5.0), 0.5, length(UV2 - 0.5)));
			cut = lf;
			// the midrib and the two halves of a leaf catch the light differently
			tone = 0.86 + 0.28 * fract(hs * 13.0) - 0.12 * smoothstep(0.03, 0.0, abs(r.y));
		}
		if (cut < 0.5) discard;
		float n = tnoise(lp * 2.6 + seed * 9.0) * 0.6 + tnoise(lp * 8.0) * 0.4;
		float shade = 0.42 + 0.58 * hgt;
		c = leaf * (0.55 + 0.9 * n) * shade * tone;
		// a few yellowing leaves
		c = mix(c, c * vec3(1.5, 1.25, 0.6), step(0.86, tnoise(lp * 1.3 + seed * 3.0)) * 0.5);
		BACKLIGHT = leaf * 0.55;
		rough = 0.7;
	}
	ALBEDO = c;
	ROUGHNESS = rough;
	SPECULAR = 0.2;
	// the lamps and windows below reach the lower leaves (near the camera real lamps do it)
	float realk = lamp_real.z > 0.0 ? smoothstep(lamp_real.z, lamp_real.w, distance(wp.xz, lamp_real.xy)) : 1.0;
	EMISSION = c * vec3(1.0, 0.66, 0.34) * night * mix(0.05, 0.24, realk) * (1.0 - 0.6 * hgt);
}
"""

## The camera in front of the world (Max / UltraMax): what a real lens and a small sensor add to
## a picture — a touch of barrel distortion, colour fringes toward the corners, fine detail a
## little soft, darker corners, lifted blacks at night, and noise: luminance grain that is
## strongest in the shadows and blotches of colour. `amount` is 0.45 in play and 1 for a photo.
const CAMERA := """
shader_type canvas_item;
global uniform float night;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float amount = 0.45;

float chash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	float r2 = dot(c, c);
	vec2 duv = uv + c * (r2 - 0.25) * 0.03 * amount;
	float ca = 0.006 * amount * r2;
	vec3 col;
	col.r = texture(screen_tex, duv + c * ca).r;
	col.g = texture(screen_tex, duv).g;
	col.b = texture(screen_tex, duv - c * ca).b;
	vec2 px = SCREEN_PIXEL_SIZE;
	vec3 blur = (texture(screen_tex, duv + px * vec2(1.2, 0.6)).rgb + texture(screen_tex, duv + px * vec2(-0.6, 1.2)).rgb
		+ texture(screen_tex, duv + px * vec2(-1.2, -0.6)).rgb + texture(screen_tex, duv + px * vec2(0.6, -1.2)).rgb) * 0.25;
	col = mix(col, blur, (0.3 + 0.5 * r2) * amount);
	col *= 1.0 - r2 * 0.6 * amount;
	col += vec3(0.01, 0.012, 0.015) * night * amount;
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	float t = floor(TIME * 24.0);
	float g1 = chash(FRAGCOORD.xy + t * 17.0) - 0.5;
	float g2 = chash(floor(FRAGCOORD.xy / 2.0) + t * 31.0) - 0.5;
	float g3 = chash(floor(FRAGCOORD.xy / 3.0) + t * 7.0) - 0.5;
	float nstr = mix(0.016, 0.055, night) * amount * (1.0 - 0.7 * smoothstep(0.0, 0.8, lum));
	col += vec3(g1) * nstr + vec3(g2, -0.5 * g2, g3) * nstr * 0.55;
	COLOR = vec4(max(col, vec3(0.0)), 1.0);
}
"""

## Paint of the military vehicles and the airframes of the threats (Fx.paint): from Ultra up the
## flat colour gets a camouflage of broad blotches, the seams between the plates, chips and
## scratches, and the dust and mud that gather low down. The pattern lives in the space of every
## part, so it stays put when a turret turns or a missile flies.
const PAINT := """
shader_type spatial;
global uniform float gfx;
uniform vec3 base : source_color = vec3(0.3, 0.34, 0.2);
uniform float rough = 0.8;
uniform float metal = 0.1;
uniform float camo = 0.6;
varying vec3 op;
varying vec3 on;
varying float wy;

float phash(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float pnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(phash(i), phash(i + vec3(1, 0, 0)), u.x), mix(phash(i + vec3(0, 1, 0)), phash(i + vec3(1, 1, 0)), u.x), u.y);
	float b = mix(mix(phash(i + vec3(0, 0, 1)), phash(i + vec3(1, 0, 1)), u.x), mix(phash(i + vec3(0, 1, 1)), phash(i + vec3(1, 1, 1)), u.x), u.y);
	return mix(a, b, u.z);
}

void vertex() {
	op = VERTEX;
	on = NORMAL;
	wy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	vec3 c = base;
	float r = rough;
	if (gfx > 1.5) {
		float n1 = pnoise(op * 0.6 + 3.0);
		float n2 = pnoise(op * 0.5 + 17.0);
		c = mix(c, base * vec3(0.5, 0.58, 0.46), smoothstep(0.52, 0.56, n1) * camo);
		c = mix(c, mix(base, vec3(0.33, 0.26, 0.17), 0.75), smoothstep(0.6, 0.64, n2) * camo);
		// the seams between the plates, a line of rivets beside them
		vec3 an = abs(on);
		vec3 q = op / vec3(1.2, 0.9, 1.4);
		vec2 t = an.y > 0.6 ? q.xz : (an.x > 0.6 ? q.zy : q.xy);
		vec2 ft = abs(fract(t) - 0.5);
		float px = max(length(dFdx(op)), length(dFdy(op)));
		float fine = 1.0 - smoothstep(0.01, 0.06, px);
		float seam = smoothstep(0.488, 0.497, max(ft.x, ft.y)) * fine;
		c *= 1.0 - 0.45 * seam;
		float rivet = step(0.45, max(ft.x, ft.y)) * step(max(ft.x, ft.y), 0.475) * step(0.8, fract((t.x + t.y) * 7.0)) * fine;
		c *= 1.0 - 0.25 * rivet;
		// the paint is never even: sun-bleached patches, chips down to the primer, scratches
		c *= 0.9 + 0.2 * pnoise(op * 2.3 + 7.0);
		c = mix(c, vec3(0.36, 0.34, 0.3), smoothstep(0.8, 0.86, pnoise(op * 7.0 + 1.0)) * 0.3 * fine);
		// dust and dried mud low down, the higher the cleaner
		float low = (1.0 - smoothstep(0.25, 1.7, wy)) * (0.55 + 0.45 * pnoise(op * 3.0 + 5.0));
		c = mix(c, vec3(0.3, 0.26, 0.2), low * 0.55 * step(0.01, camo));
		r = clamp(rough + 0.16 * (n1 - 0.5) + 0.2 * low, 0.05, 1.0);
	}
	ALBEDO = c;
	ROUGHNESS = r;
	METALLIC = metal;
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
// the diffraction star a camera draws around a point light (0 = none)
uniform float rays = 0.0;
// the hot centre (0 = a soft halo only: the haze lit around a burst)
uniform float core = 1.0;
varying float inside;

void vertex() {
	vec4 c = MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	float d = max(-c.z, 0.1);
	float s = max(base_size, d * dist_k);
	// lit haze is seen from outside: a camera standing in it is not blinded by an orange wall
	float halo = 1.0 - clamp(core, 0.0, 1.0);
	inside = mix(1.0, clamp(d / (s * 0.7), 0.0, 1.0), halo);
	// haze is a volume, the sprite a flat sheet: drawn half its size nearer (and as much smaller),
	// it does not cut into the ground or the roofs under a low burst
	float k = (d - halo * min(s * 0.45, d * 0.6)) / d;
	c.xyz *= k;
	s *= k;
	c.xy += VERTEX.xy * s;
	POSITION = PROJECTION_MATRIX * c;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float a = clamp(1.0 - r, 0.0, 1.0);
	float g = a * a * (0.3 + 0.7 * a) + pow(a, 12.0) * 2.0 * core;
	if (rays > 0.0) {
		// four long spikes a little off the axes and four short ones between them
		vec2 d1 = vec2(p.x * 0.966 - p.y * 0.259, p.x * 0.259 + p.y * 0.966);
		vec2 d2 = vec2(d1.x + d1.y, d1.y - d1.x) * 0.7071;
		float s1 = exp(-abs(d1.x) * 80.0) + exp(-abs(d1.y) * 80.0);
		float s2 = exp(-abs(d2.x) * 120.0) + exp(-abs(d2.y) * 120.0);
		g += rays * (s1 + s2 * 0.4) * a * 1.6;
	}
	float f = 1.0 - flicker * 0.35 * (sin(TIME * 37.0) * 0.5 + 0.5) * (sin(TIME * 23.0 + 1.7) * 0.5 + 0.5);
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
	// a halo without a centre is haze lit against the sky: the brighter sky of Forward+ needs more
	f *= mix(1.9, 1.0, clamp(core, 0.0, 1.0));
#endif
	ALBEDO = color.rgb * energy * g * f * inside * mix(day_vis, 1.0, night);
}
"""

## The streak a missile leaves across the night sky (scripts/game/trail.gd): one ribbon that is both
## the smoke and the line of light a long exposure keeps of the motor. The mesh holds the points
## the motor passed (NORMAL = the direction of flight, UV = side / second of birth, UV2 = follows
## the head / metres along the trail); everything that changes with time happens here, so a trail
## that only hangs in the sky and fades costs the game nothing.
##  - the smoke widens, curls and drifts as it ages, is broken into puffs along its length, glows
##    behind the nozzle and is lit from below by the city;
##  - down its middle runs the afterglow: a line a pixel or two wide, white-hot at the head and
##    cooling to an ember that outlives the smoke — the arcs of an air-defence battery at work.
## Premultiplied: the smoke covers, the light adds.
const TRAIL := """
shader_type spatial;
render_mode unshaded, blend_premul_alpha, cull_disabled, depth_draw_never, shadows_disabled;
global uniform float night;
uniform float now = 0.0;
uniform vec3 head = vec3(0.0);
uniform float life = 9.0;
uniform float hot_time = 1.4;
uniform float glow_time = 6.0;
uniform float w0 = 1.4;
uniform float w1 = 16.0;
uniform float px = 0.0013;
uniform float wobble = 14.0;
// how much longer than usual the bends are: a fast missile's points are far apart
uniform float curl_scale = 1.0;
uniform float seed = 0.0;
uniform vec4 hot : source_color = vec4(1.0, 0.7, 0.4, 0.95);
uniform float hot_energy = 3.0;
uniform vec4 smoke : source_color = vec4(0.62, 0.62, 0.66, 0.42);
uniform vec4 glow : source_color = vec4(1.0, 0.72, 0.4, 1.0);
uniform float glow_energy = 2.2;
varying float age;
varying float along;
varying float height;

float hash1(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash1(i), hash1(i + vec2(1.0, 0.0)), f.x), mix(hash1(i + vec2(0.0, 1.0)), hash1(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	vec3 p = VERTEX;
	age = max(now - UV.y, 0.0);
	if (UV2.x > 0.5) {
		p = head;
		age = 0.0;
	}
	along = UV2.y;
	height = p.y;
	float k = clamp(age / life, 0.0, 1.0);
	// the air is never still: the column curls wider the longer it hangs, and drifts downwind
	// (long lazy bends only: a trail has few points to bend at)
	vec3 q = p * (0.0042 / curl_scale) + vec3(seed, seed * 1.7, seed * 0.6);
	vec3 curl = vec3(sin(q.y * 1.7 + q.z * 1.3) + sin(q.z * 2.9 + q.x * 0.8),
		sin(q.x * 1.9 + q.z * 0.7) * 0.6 + sin(q.y * 2.3 + q.x * 1.1) * 0.4,
		sin(q.x * 1.3 + q.y * 2.1) + sin(q.y * 3.1 + q.z * 0.9));
	p += curl * wobble * (1.0 - exp(-age * 0.22)) + vec3(2.2, 0.5, 1.3) * age;
	vec3 to_cam = CAMERA_POSITION_WORLD - p;
	float dist = length(to_cam);
	vec3 side = cross(NORMAL, to_cam);
	float sl = length(side);
	side = sl > 0.0001 ? side / sl : vec3(0.0, 1.0, 0.0);
	// never thinner than a pixel or two, however far away
	float w = max(mix(w0, w1, sqrt(k)), dist * px);
	VERTEX = p + side * (UV.x - 0.5) * w;
}

void fragment() {
	float k = clamp(age / life, 0.0, 1.0);
	float x = abs(UV.x * 2.0 - 1.0);
	// the smoke: soft across, torn into puffs along its length as it thins out
	float puff = vnoise(vec2(along * 0.035, seed * 7.0)) * 0.6 + vnoise(vec2(along * 0.11, seed * 3.0 + x)) * 0.4;
	float body = smoothstep(1.0, 0.2, x) * (1.0 - k) * (1.0 - k) * smoke.a;
	body *= mix(1.0, smoothstep(0.15, 0.75, puff) * 1.3, smoothstep(0.05, 0.6, k));
	body = clamp(body, 0.0, 1.0);
	float h = clamp(1.0 - age / hot_time, 0.0, 1.0);
	// by night smoke shows only where something lights it: the city from below, the motor behind it
	vec3 city = vec3(1.0, 0.58, 0.3) * 0.7 * exp(-max(height, 0.0) / 1200.0);
	vec3 lit = smoke.rgb * mix(vec3(1.0), vec3(0.34, 0.34, 0.4) + city, night);
	vec3 col = mix(lit, hot.rgb * hot_energy, h * h * hot.a);
	// the afterglow: a line down the middle that keeps its width on the screen
	float fw = max(fwidth(x), 0.0001);
	float line = smoothstep(fw * 2.2, 0.0, x);
	float g = clamp(1.0 - age / glow_time, 0.0, 1.0);
	float ember = g * sqrt(g);
	vec3 light = glow.rgb * glow_energy * line * (ember + 2.5 * exp(-age * 2.2)) * mix(0.1, 1.0, night);
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
	// the bright, moonlit sky of the Forward+ levels takes more light to draw a line on
	light *= 1.7;
#endif
	ALBEDO = col * body + light;
	ALPHA = body;
}
"""

## A burst of sparks (scripts/game/sparks.gd): every spark is a short ribbon whose path — thrown
## out, slowed by the air, bent down by its weight — is worked out here from the second of the
## burst, so a hundred of them cost one draw and no script. VERTEX carries the spark's velocity
## (a share of `speed`), UV = side / place along the streak (0 head, 1 tail), UV2 = how long this
## spark lives (a share of `life`) / a random number.
const SPARKS := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
global uniform float night;
uniform float t = 0.0;
uniform float speed = 40.0;
uniform float gravity = 12.0;
uniform float drag = 1.0;
uniform float life = 3.0;
uniform float streak = 0.35;
uniform float size = 0.8;
uniform float px = 0.0012;
uniform vec4 head_color : source_color = vec4(1.0, 0.9, 0.7, 1.0);
uniform vec4 tail_color : source_color = vec4(1.0, 0.45, 0.1, 1.0);
uniform float energy = 3.0;
varying float fade;
varying float tailness;
varying float rnd;

void vertex() {
	vec3 v0 = VERTEX * speed;
	float mine = life * UV2.x;
	// the tail is where the head was a moment ago
	float tt = clamp(t - UV.y * streak * (0.5 + UV2.y), 0.0, mine);
	vec3 gd = vec3(0.0, -gravity, 0.0) / drag;
	float e = exp(-drag * tt);
	vec3 p = gd * tt + (v0 - gd) * (1.0 - e) / drag;
	vec3 vel = gd + (v0 - gd) * e;
	vec3 wp = MODEL_MATRIX[3].xyz + p;
	vec3 to_cam = CAMERA_POSITION_WORLD - wp;
	vec3 side = cross(vel, to_cam);
	float sl = length(side);
	side = sl > 0.0001 ? side / sl : vec3(1.0, 0.0, 0.0);
	fade = clamp(1.0 - t / mine, 0.0, 1.0);
	tailness = UV.y;
	rnd = UV2.y;
	float w = max(size * (0.4 + 0.6 * fade), length(to_cam) * px);
	VERTEX = p + side * (UV.x - 0.5) * w;
}

void fragment() {
	float x = 1.0 - abs(UV.x * 2.0 - 1.0);
	float along = 1.0 - tailness;
	vec3 c = mix(tail_color.rgb, head_color.rgb, along * along * fade);
	// a dying spark flickers
	float tw = 0.75 + 0.25 * sin(t * 43.0 + rnd * 97.0) * (1.0 - fade);
	ALBEDO = c * energy * x * along * pow(fade, 0.7) * tw * mix(0.5, 1.0, night);
}
"""

## Smoke and fire particles (Fx.smoke_mat / Fx.fire_mat): the particle meshes are little spheres,
## and a sphere drawn flat has a hard polygon for an edge. Here it thins out towards its rim, so
## a cloud of them reads as one soft volume. Smoke that is not lit goes dark at night; the
## colour comes from the particle (COLOR) times `tint`.
const PUFF := """
shader_type spatial;
render_mode unshaded, BLEND, depth_draw_never, shadows_disabled;
global uniform float night;
uniform vec4 tint = vec4(1.0);

void fragment() {
	float f = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float a = smoothstep(0.05, 0.9, f);
	vec3 c = COLOR.rgb * tint.rgb;
	float bright = max(c.r, max(c.g, c.b));
	c = mix(c * mix(1.0, 0.55, night), c, smoothstep(0.45, 0.85, bright));
	ALBEDO = c;
	ALPHA = COLOR.a * tint.a * a * a;
}
"""

## Full-screen night-vision filter for the gunner sight and the FPV camera. Like a real image
## intensifier it has automatic gain: full amplification in the dark, far less at dusk or by day,
## and bright spots roll off softly instead of flooding the picture green.
const NIGHT_VISION := """
shader_type canvas_item;
global uniform float night;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.3, 0.59, 0.11));
	l = pow(clamp(l, 0.0, 4.0), 0.5) * mix(0.5, 1.7, clamp(night, 0.0, 1.0));
	l = 1.05 * l / (1.0 + 0.45 * l) + 0.03;
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


static var _shared := {}


## One material per shader, shared by everything that draws with it.
static func shared(key: String, code: String) -> ShaderMaterial:
	if not _shared.has(key):
		_shared[key] = material(code)
	return _shared[key]


static func canvas_material(code: String) -> ShaderMaterial:
	return material(code)
