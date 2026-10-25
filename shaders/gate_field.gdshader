shader_type spatial;
// The shimmering energy sheet inside a stargate ring (on a flat cylinder; radius 1 before scaling).
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform vec3 color : source_color = vec3(0.3, 0.66, 1.0);

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	float r = length(lp.xz);
	float a = atan(lp.z, lp.x);
	float swirl = 0.5 + 0.5 * sin(a * 5.0 + TIME * 1.4 - r * 9.0);
	float shimmer = 0.5 + 0.5 * sin(lp.x * 26.0 + TIME * 3.0) * sin(lp.z * 21.0 - TIME * 2.2);
	float edge = smoothstep(1.0, 0.82, r);
	float alpha = (0.04 + 0.11 * swirl + 0.05 * shimmer) * edge + smoothstep(0.86, 1.0, r) * 0.14;
	ALBEDO = color * (0.4 + 0.6 * swirl);
	ALPHA = clamp(alpha, 0.0, 1.0);
}
