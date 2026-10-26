shader_type sky;
render_mode use_half_res_pass;
// Space in colour, different in every system (see Game.system_look). Each sky has a great nebula in its
// own palette - after real ones: hydrogen red and oxygen teal, reflection blue, dusty gold... - swirled and
// folded, with bright filaments and shock fronts through it, a hotter core, and dark dust lying across it;
// a broader, fainter cloud elsewhere in the sky; a galactic band with a warm bulge at its centre, lanes of
// dust and pink star-forming knots; and stars of every colour, thickest in the band and hidden by the dust.
// The clouds are soft, so they're worked out at half resolution (with the star density in alpha); the stars
// are drawn at full resolution on top. The system's own star isn't in the sky: it's shaders/star.gdshader,
// so it can move without the sky being drawn again.

#include "res://shaders/noise.gdshaderinc"

uniform vec3 c1 : source_color = vec3(1.0, 0.24, 0.36);  // the main glowing gas
uniform vec3 c2 : source_color = vec3(0.18, 0.74, 0.82);  // the second gas, in the dense hearts
uniform vec3 c3 : source_color = vec3(0.95, 0.62, 0.3);  // filaments and dust glow
uniform float nebula = 1.0;  // how bright the clouds are
uniform vec3 neb_dir = vec3(0.5, 0.3, -0.8);  // where the great nebula lies
uniform float neb_size = 0.4;  // its size (radians)
uniform vec3 neb_dir2 = vec3(-0.6, -0.2, 0.7);  // the broad faint cloud
uniform float neb_size2 = 0.7;
uniform vec3 band_axis = vec3(0.3, 0.9, 0.2);  // the galactic plane's pole
uniform vec3 core_dir = vec3(1.0, 0.0, 0.0);  // the galactic centre (on the plane)
uniform float band = 1.0;
uniform float star_density = 1.0;
uniform float turb = 2.5;  // how much the clouds swirl
uniform float lanes = 0.7;  // how dark the dust is
uniform float seed = 0.0;

float fbmn(vec3 p, int n) {
	float v = 0.0;
	float a = 0.5;
	float t = 0.0;
	for (int i = 0; i < n; i++) {
		v += a * noise3(p);
		t += a;
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return v / t;
}

// a soft patch of sky round `axis`, `s` radians across
float cone(vec3 d, vec3 axis, float s) {
	float a = acos(clamp(dot(d, normalize(axis)), -1.0, 1.0));
	return exp(-(a * a) / (s * s));
}

// the clouds and the band (rgb) and how thick the stars are there (a)
vec4 space(vec3 d) {
	vec3 p = d * 2.0 + vec3(seed, seed * 0.7, -seed * 0.3);
	// domain warp: the gas swirls and folds instead of sitting in round blobs
	vec3 w = vec3(fbmn(p * 1.3, 4), fbmn(p * 1.3 + vec3(5.2, 1.3, 2.8), 4), fbmn(p * 1.3 + vec3(1.7, 9.2, 4.1), 4)) - 0.5;
	float n = fbmn(p * 1.7 + w * turb, 6);
	float n2 = fbmn(p * 3.3 + w * turb * 1.4 + 11.0, 5);
	float f = fbmn(p * 2.4 + w * turb * 1.6 + 23.0, 5);
	// wisps: bright ridges along one level of a swirled noise, of varying width, and only here and there
	float g = fbmn(p * 1.1 + w * 0.6 + 51.0, 3);
	float fil = exp(-pow((f - 0.5) / mix(0.006, 0.03, g), 2.0)) * smoothstep(0.47, 0.6, g);
	float dust = smoothstep(0.5, 0.7, fbmn(p * 2.1 + w * turb * 0.8 + 37.0, 5));
	float tex = clamp(1.0 + (n2 - 0.5) * 3.5, 0.2, 2.0);  // mottling, so no patch of gas is flat

	// the great nebula: dense in the middle, broken into wisps at its edges
	float m1 = cone(d, neb_dir, neb_size);
	float d1 = clamp(m1 * 1.25 + (n - 0.5) * 2.6 - 0.32, 0.0, 1.0);
	d1 *= d1;
	float heart = smoothstep(0.2, 0.95, d1 * 0.8 + (n2 - 0.5) * 1.4);
	vec3 col = mix(c1, c2, heart) * d1 * tex * 0.3;
	col += mix(c2, vec3(1.0), 0.5) * pow(heart * d1, 3.0) * tex * 0.13;  // the hot core, lit by young stars
	col += c3 * fil * clamp(m1 * 1.6, 0.0, 1.0) * (0.25 + d1) * 0.2;
	// the broad cloud: faint, smooth, in the other colours
	float m2 = cone(d, neb_dir2, neb_size2);
	float d2 = clamp(m2 * 1.1 + (n2 - 0.5) * 2.0 - 0.4, 0.0, 1.0);
	col += mix(c2, c3, n) * d2 * d2 * 0.11;
	col += c1 * fil * m2 * 0.05;
	// and a whisper of colour everywhere, so the dark is never quite grey
	col += mix(c1, c2, smoothstep(0.35, 0.65, fbmn(p * 0.7 + 3.0, 3))) * 0.006 * (0.4 + n);
	col *= nebula;

	// the galactic band
	vec3 axis = normalize(band_axis);
	float lat = dot(d, axis);
	float bw = fbmn(d * 3.0 + vec3(5.0) + seed, 4) - 0.5;
	float wide = exp(-pow(lat * 3.0 + bw * 0.9, 2.0));
	float ridge = exp(-pow(lat * 7.5 + bw * 1.4, 2.0));
	float bulge = cone(d, core_dir, 0.55) * wide;
	float blanes = smoothstep(0.46, 0.66, fbmn(d * 6.0 + vec3(1.3, 4.0, 2.2) + seed, 5));
	vec3 bcol = mix(vec3(0.55, 0.65, 0.95), vec3(1.0, 0.88, 0.7), ridge);  // blue-white edges, warm heart
	bcol = mix(bcol, vec3(1.0, 0.76, 0.5), bulge);
	float bb = (wide * 0.035 + ridge * 0.05 + bulge * 0.22) * (1.0 - blanes * ridge * 0.92);
	vec3 milky = bcol * bb;
	float knots = smoothstep(0.66, 0.8, fbmn(d * 13.0 + seed * 1.3, 3)) * ridge * (1.0 - blanes);
	milky += c1 * knots * 0.05;
	col += milky * band;

	// dust lies across all of it
	float shade = dust * lanes * clamp(m1 * 1.4 + m2 * 0.6 + ridge * band * 0.6, 0.0, 1.0);
	col *= 1.0 - shade * 0.9;
	col += vec3(0.0004, 0.0005, 0.0009);
	float dens = (0.25 + 0.9 * wide * (1.0 - blanes * 0.7) + 0.8 * bulge + 0.3 * d1) * (1.0 - shade * 0.85);
	return vec4(col, dens * 0.25);
}

// stars in cells of a 3D grid: one in a few cells, at a random spot (kept far enough inside the cell that
// its glow never reaches the edge), its brightness from the cell's hash
float stars(vec3 dir, float scale, float thresh, float rad, float jit, out float tint) {
	vec3 p = dir * scale;
	vec3 cell = floor(p);
	float h = hash3(cell + seed * 0.37);
	tint = hash3(cell + 9.1);
	if (h < thresh) {
		return 0.0;
	}
	vec3 c = cell + 0.5 + (vec3(hash3(cell + 1.3), hash3(cell + 2.7), hash3(cell + 4.1)) - 0.5) * jit;
	float r = length(p - c) / rad;
	float k = (h - thresh) / (1.0 - thresh);
	return exp(-r * r) * k * k;
}

// red dwarfs to blue giants, most of them warm white
vec3 star_col(float t) {
	if (t < 0.12) return vec3(1.0, 0.52, 0.36);
	if (t < 0.35) return vec3(1.0, 0.78, 0.56);
	if (t < 0.7) return vec3(1.0, 0.95, 0.88);
	if (t < 0.9) return vec3(0.78, 0.86, 1.0);
	return vec3(0.6, 0.72, 1.0);
}

vec3 all_stars(vec3 d, float dens) {
	float t;
	vec3 col = vec3(0.0);
	float s = stars(d, 300.0, 0.9, 0.2, 0.4, t);  // a dust of faint ones, about a pixel each
	col += star_col(t) * s * 0.55 * dens;
	s = stars(d, 140.0, 0.955, 0.11, 0.4, t);
	col += star_col(t) * s * 1.6 * (0.4 + dens);
	s = stars(d, 60.0, 0.988, 0.07, 0.3, t);  // the few bright ones, with a little glow
	float g = stars(d, 60.0, 0.988, 0.12, 0.3, t);
	col += star_col(t) * (s * 7.0 + g * 0.3);
	return col * star_density;
}

void sky() {
	vec3 d = EYEDIR;
	if (AT_HALF_RES_PASS) {
		vec4 s = space(d);
		COLOR = s.rgb;
		ALPHA = s.a;
	} else if (AT_CUBEMAP_PASS) {
		COLOR = space(d).rgb;  // (what metal reflects: the stars are too small to matter)
	} else {
		COLOR = HALF_RES_COLOR.rgb + all_stars(d, HALF_RES_COLOR.a * 4.0);
	}
}
