shader_type sky;
// Deep space, dark and dusty: near-black, a faint milky galactic band cut through by dark dust lanes,
// dim smoky nebulae only lightly tinted by the system, a great many faint stars with the odd bright one,
// and the local sun as a small, harsh white disc with a dusty glow round it.

#include "res://shaders/noise.gdshaderinc"

uniform vec3 tint : source_color = vec3(0.29, 0.66, 1.0);
uniform vec3 tint2 : source_color = vec3(1.0, 0.49, 0.91);
uniform vec3 sun_dir = vec3(0.4, 0.3, -0.85);
uniform vec3 sun_color : source_color = vec3(1.0, 0.9, 0.7);
uniform float nebula = 1.0;
uniform vec3 band_axis = vec3(0.3, 0.9, 0.2);  // the galactic plane's pole (differs per system)

float stars(vec3 dir, float scale, float thresh) {
	vec3 p = dir * scale;
	vec3 cell = floor(p);
	float h = hash3(cell);
	if (h < thresh) {
		return 0.0;
	}
	vec3 c = cell + 0.5 + (vec3(hash3(cell + 1.3), hash3(cell + 2.7), hash3(cell + 4.1)) - 0.5) * 0.6;
	float d = length(p - c);
	return smoothstep(0.12, 0.0, d) * pow((h - thresh) / (1.0 - thresh), 2.0);
}

vec3 star_tint(vec3 dir, float scale) {
	float t = hash3(floor(dir * scale) + 9.1);
	return mix(vec3(1.0, 0.78, 0.6), vec3(0.75, 0.85, 1.0), t);
}

void sky() {
	vec3 d = EYEDIR;
	vec3 axis = normalize(band_axis);
	float lat = dot(d, axis);
	// the galactic band: a soft haze along the plane, broken by dark lanes of dust
	float warp = fbm3(d * 3.0 + vec3(5.0)) - 0.5;
	float band = exp(-pow(lat * 3.2 + warp * 0.8, 2.0));
	float lanes = smoothstep(0.42, 0.7, fbm3(d * 7.0 + vec3(1.3, 4.0, 2.2)));
	float haze = band * (1.0 - lanes * 0.85);
	vec3 milky = vec3(0.16, 0.15, 0.14) * haze;
	// dim smoky nebulae, mostly grey-brown dust with a little of the system's colour in it
	float n = fbm3(d * 1.8 + vec3(3.0));
	float n2 = fbm3(d * 4.0 + vec3(11.0));
	vec3 dust = vec3(0.09, 0.075, 0.065);
	vec3 neb = mix(dust, tint * 0.35, 0.35) * pow(n, 4.0) * 1.6 + mix(dust, tint2 * 0.3, 0.25) * pow(n2, 5.0) * 1.1;
	vec3 col = vec3(0.0006, 0.0007, 0.001) + milky * 0.35 + neb * 0.22 * nebula;
	// stars: thick in the band, thin elsewhere, and mostly faint
	float dens = 0.35 + 0.65 * band * (1.0 - lanes * 0.7);
	col += star_tint(d, 520.0) * stars(d, 520.0, 0.955) * 0.9 * dens;
	col += star_tint(d, 260.0) * stars(d, 260.0, 0.975) * 1.6 * dens;
	col += star_tint(d, 110.0) * stars(d, 110.0, 0.993) * 3.5;
	// the sun: a small harsh disc, a tight glow and a wide faint scatter through the dust
	vec3 s = normalize(sun_dir);
	float sd = max(dot(d, s), 0.0);
	col += sun_color * (smoothstep(0.99955, 0.99975, sd) * 60.0 + pow(sd, 900.0) * 4.0 + pow(sd, 40.0) * 0.12 + pow(sd, 6.0) * 0.025);
	COLOR = col;
}