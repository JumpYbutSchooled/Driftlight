shader_type spatial;
// A planet seen from far off: fractal terrain blended smoothly through a 5-colour palette (kind 0), gas
// bands (1), lava with glowing cracks (2) or an ocean world (3), all muted the way distance and dust mute
// them, with thin cloud cover. Lit by the sun, so the night side falls away into darkness. Not fogged.
render_mode specular_schlick_ggx, fog_disabled;

#include "res://shaders/noise.gdshaderinc"

uniform vec3 c0 : source_color;
uniform vec3 c1 : source_color;
uniform vec3 c2 : source_color;
uniform vec3 c3 : source_color;
uniform vec3 c4 : source_color;
uniform int kind = 0;
uniform float seed = 0.0;
uniform float clouds = 0.5;

varying vec3 objpos;

void vertex() {
	objpos = VERTEX;
}

vec3 palette(float t) {
	t = clamp(t, 0.0, 1.0) * 4.0;
	vec3 a = mix(c0, c1, smoothstep(0.0, 1.0, clamp(t, 0.0, 1.0)));
	a = mix(a, c2, smoothstep(0.0, 1.0, clamp(t - 1.0, 0.0, 1.0)));
	a = mix(a, c3, smoothstep(0.0, 1.0, clamp(t - 2.0, 0.0, 1.0)));
	return mix(a, c4, smoothstep(0.0, 1.0, clamp(t - 3.0, 0.0, 1.0)));
}

void fragment() {
	vec3 p = normalize(objpos);
	float n = fbm3(p * 3.0 + vec3(seed));
	float fine = fbm3(p * 14.0 + vec3(seed * 2.0));
	float t;
	if (kind == 1) {
		t = 0.5 + 0.5 * sin(p.y * 16.0 + n * 7.0 + fine * 1.5);
	} else {
		t = clamp(n * 1.35 - 0.18 + (fine - 0.5) * 0.25, 0.0, 1.0);
	}
	vec3 col = palette(t);
	float luma = dot(col, vec3(0.3, 0.59, 0.11));
	col = mix(vec3(luma), col, 0.5) * 0.42;  // muted and dark
	float cl = smoothstep(0.55, 0.8, fbm3(p * vec3(5.0, 9.0, 5.0) + vec3(seed + 7.0))) * clouds;
	if (kind != 1 && kind != 2) {
		col = mix(col, vec3(0.42, 0.42, 0.4), cl);
	}
	ALBEDO = col;
	ROUGHNESS = 0.95;
	if (kind == 3 && t < 0.6 && cl < 0.3) {
		ROUGHNESS = 0.35;
		SPECULAR = 0.6;
	}
	if (kind == 2 && abs(n - 0.5) < 0.03) {
		EMISSION = c4 * 1.5;
	}
}