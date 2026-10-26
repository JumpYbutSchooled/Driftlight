shader_type spatial;
// The system's star (and its companion, in a binary): a wide quad held far out along the star's direction
// from the camera, wherever the camera is, so the star sits in the sky like the sky itself but can move every
// frame (as you warp across the system it swings round and grows or shrinks) without re-rendering the sky.
// A disc with a bright core and darker, redder limb, a little boiling granulation on the big ones, a corona
// and a glow scattered wide round it. Ships and planets in front of it hide it. Not fogged.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://shaders/noise.gdshaderinc"

const float DIST = 400000.0;  // how far out the quad is held (planets are nearer, so they pass in front)
const float SPREAD = 2.0;  // the quad's half-width, as a share of DIST (63 degrees either side)

uniform vec3 star_dir = vec3(0.4, 0.3, -0.85);  // towards the star, world space
uniform vec3 star_color : source_color = vec3(1.0, 0.92, 0.78);
uniform float star_rad = 0.015;  // its angular radius, radians
uniform vec3 comp_dir = vec3(0.4, 0.3, -0.85);
uniform vec3 comp_color : source_color = vec3(1.0, 0.6, 0.4);
uniform float comp_rad = 0.0;  // 0: no companion

varying vec3 wdir;

void vertex() {
	vec3 s = normalize(star_dir);
	vec3 up = abs(s.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 r = normalize(cross(up, s));
	vec3 u = cross(s, r);
	wdir = (s + (r * VERTEX.x + u * VERTEX.y) * SPREAD) * DIST;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(CAMERA_POSITION_WORLD + wdir, 1.0);
}

// the angle between two directions, precise even when tiny
float angle(vec3 a, vec3 b) {
	return atan(length(cross(a, b)), dot(a, b));
}

vec3 star(vec3 d, vec3 s, vec3 col, float rad) {
	float a = angle(d, s);
	float x = a / rad;
	// bigger stars are dimmer per pixel, so a red giant's colour and surface show rather than burning white
	float hdr = 3.0 + 22.0 / (1.0 + rad * 60.0);
	vec3 c = vec3(0.0);
	if (x < 1.0) {
		float mu = sqrt(1.0 - x * x);
		float gran = fbm3(d * (7.0 / rad) + vec3(TIME * 0.04, 0.0, TIME * 0.03));
		vec3 limb = col * (0.3 + 0.7 * mu) * (0.85 + 0.3 * gran);
		c = mix(limb, mix(col, vec3(1.0), 0.7), mu * mu * mu) * hdr * smoothstep(1.0, 0.94, x);
	}
	c += col * 2.2 * exp(-max(x - 1.0, 0.0) * 2.4) * smoothstep(0.94, 1.0, x);  // corona, just off the limb
	c += col * 0.45 * exp(-a / (rad * 5.0 + 0.004));  // glow
	c += col * 0.05 * exp(-a / 0.3);  // light scattered wide across the sky
	return c;
}

void fragment() {
	vec3 d = normalize(wdir);
	vec3 c = star(d, normalize(star_dir), star_color, star_rad);
	if (comp_rad > 0.0) {
		c += star(d, normalize(comp_dir), comp_color, comp_rad);
	}
	// fade out well before the quad's edge
	float edge = smoothstep(1.05, 0.8, angle(d, normalize(star_dir)));
	ALBEDO = c * edge;
}
