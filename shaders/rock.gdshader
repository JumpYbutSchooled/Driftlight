shader_type spatial;
// Asteroid: dark, dusty stone threaded with thin veins of ore and flecked with it, the way real mineral
// veins run through rock. Better quality ore runs in thicker, brighter veins; pristine ore glints. The
// mesh is a unit lump scaled up to `size` metres, so the big structure is as huge as the rock; finer grit
// and a craggy bump-mapped surface are added at a metre scale so a big rock still looks like rock up close.

#include "res://shaders/noise.gdshaderinc"

uniform vec3 ore_color : source_color = vec3(0.76, 0.56, 0.36);
uniform float ore_amount = 0.2;
uniform float glow = 0.4;
uniform float sparkle = 0.0;
uniform vec3 offset = vec3(0.0);
uniform float hit = 0.0;  // flashes when shot
uniform float size = 1.0;  // radius in metres
uniform float bump = 1.0;
uniform float ore_tint = 0.0;  // loose chunks are mostly ore: tint the whole stone toward it

varying vec3 objpos;

// Distance to the nearest crack in a 3D Voronoi pattern (the gap between the two nearest cell points),
// so veins run as an irregular network of fractures of even width.
float cracks(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			for (int z = -1; z <= 1; z++) {
				vec3 o = vec3(float(x), float(y), float(z));
				vec3 c = cell + o;
				vec3 pt = o + vec3(hash3(c), hash3(c + 17.3), hash3(c + 31.7)) - f;
				float d = dot(pt, pt);
				if (d < d1) {
					d2 = d1;
					d1 = d;
				} else if (d < d2) {
					d2 = d;
				}
			}
		}
	}
	return sqrt(d2) - sqrt(d1);
}

void fragment() {
	vec3 m = objpos * size;  // metres
	float n = fbm3(objpos * 2.4 + offset);
	float grit = noise3(m * 0.9 + offset) * 0.5 + noise3(m * 3.1) * 0.5;
	vec3 rock = mix(vec3(0.035, 0.032, 0.03), vec3(0.12, 0.108, 0.095), n) * (0.75 + 0.4 * grit);
	rock = mix(rock, ore_color * 0.35, ore_tint);
	// veins: a network of fractures filled with ore, in some parts of the rock, plus a finer web of
	// hairline cracks; the crack pattern is bent a little by noise so it doesn't look geometric
	float zone = smoothstep(0.5, 0.72, fbm3(objpos * 1.5 + offset * 0.7)) + ore_tint;
	vec3 warp = vec3(noise3(objpos * 3.0 + offset), noise3(objpos * 3.0 + offset + 5.2), noise3(objpos * 3.0 + offset + 9.4)) - 0.5;
	float w = ore_amount * 0.16 * (0.5 + 1.0 * noise3(objpos * 6.0 + offset));
	float big = 1.0 - smoothstep(w * 0.4, w, cracks(objpos * 3.2 + warp * 0.6 + offset));
	float web = 1.0 - smoothstep(w * 0.15, w * 0.45, cracks(objpos * 9.0 + warp * 1.2 + offset * 1.7));
	float grains = smoothstep(0.78, 0.86, noise3(m * 1.7 + offset)) * zone;  // specks of ore in the stone round the veins
	float ore = clamp((big + web * 0.5) * zone + grains * 0.5, 0.0, 1.0);
	ALBEDO = mix(rock, ore_color * mix(0.45, 0.8, big), ore);
	ROUGHNESS = mix(0.97, 0.3, ore);
	METALLIC = ore * 0.5;
	// craggy surface: bump-map a height made of metre-scale noise (screen-space derivative method)
	float h = fbm3(m * 0.12 + offset) * 2.5 + noise3(m * 0.8) * 0.35;
	vec3 dpx = dFdx(VERTEX);
	vec3 dpy = dFdy(VERTEX);
	float hx = dFdx(h);
	float hy = dFdy(h);
	vec3 r1 = cross(dpy, NORMAL);
	vec3 r2 = cross(NORMAL, dpx);
	float det = dot(dpx, r1);
	vec3 grad = sign(det) * (hx * r1 + hy * r2);
	NORMAL = normalize(abs(det) * NORMAL - grad * bump * (1.0 - ore * 0.7));
	float spark = sparkle * step(0.985, hash3(floor(m * 2.0 + offset))) * (0.5 + 0.5 * sin(TIME * 6.0 + n * 30.0)) * ore;
	EMISSION = ore_color * ore * glow * 0.7 + vec3(spark) * 4.0 + vec3(1.0, 0.9, 0.7) * hit;
}

void vertex() {
	objpos = VERTEX;
}