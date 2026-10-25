shader_type spatial;
// A wormhole: spiral arms of light pouring into a dark centre (on a flat cylinder; radius 1 before scaling).
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform vec3 color : source_color = vec3(0.7, 0.4, 1.0);

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	float r = length(lp.xz);
	float a = atan(lp.z, lp.x);
	float arms = 0.5 + 0.5 * sin(a * 3.0 + log(r + 0.02) * 6.0 + TIME * 2.5);
	float body = smoothstep(1.0, 0.3, r) * smoothstep(0.02, 0.18, r);
	vec3 col = mix(color, vec3(1.0), smoothstep(0.5, 0.1, r));
	ALBEDO = col * (1.5 + arms * 2.0);
	ALPHA = clamp(body * (0.25 + arms * 0.75), 0.0, 1.0);
}
