shader_type spatial;
// One layer of the warp tunnel: a long open tube around the ship, lined with wisps and fine threads of
// light that stream past from the front. The noise is stretched along the tube and scrolls along it,
// so you get streaks, never rings. Brightest where you look along the tube wall, fading at both ends.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

#include "res://shaders/noise.gdshaderinc"

uniform vec4 tint : source_color = vec4(0.45, 0.7, 1.0, 1.0);
uniform float intensity = 0.0;
uniform float speed = 1.0;
uniform float layer = 0.0;  // offsets the pattern so the layers differ
uniform float twist = 0.15;  // the streaks spiral very slightly

varying vec3 lp;

void vertex() {
	lp = VERTEX;  // a cylinder of radius 1 and height 1: y runs along the tube, -0.5 at the back
}

float lane_hash(float n) {
	return fract(sin(n * 91.345) * 47453.5453);
}

void fragment() {
	float ang = atan(lp.z, lp.x) + lp.y * twist * 6.2831;
	vec2 ring = vec2(cos(ang), sin(ang));
	float flow = lp.y * 1.6 + TIME * speed;  // patterns move from the front (+y) toward the back
	float wisps = fbm3(vec3(ring * 2.2, flow * 0.7 + layer * 7.0));
	wisps = smoothstep(0.5, 0.9, wisps);
	// threads: thin lanes of light around the tube, each streaking past at its own speed
	float f = (ang / 6.2831 + 0.5) * 240.0;
	float h = lane_hash(floor(f) + layer * 31.0);
	float across = abs(fract(f) - 0.5) * 2.0;
	float z = fract(h * 13.0 + flow * (0.6 + h));
	float threads = smoothstep(0.82, 1.0, z) * step(0.62, h) * (1.0 - smoothstep(0.15, 0.85, across));
	float ends = smoothstep(0.5, 0.25, abs(lp.y)) * mix(1.0, 1.6, smoothstep(-0.2, 0.5, lp.y));
	float graze = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	float k = (wisps * 0.3 + threads * 1.1) * ends * (0.3 + 0.7 * graze) * intensity;
	ALBEDO = mix(tint.rgb, vec3(0.9, 0.95, 1.0), clamp(threads * 0.7, 0.0, 1.0));
	ALPHA = clamp(k, 0.0, 1.0);
}
