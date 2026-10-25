shader_type spatial;
// Engine exhaust in vacuum, drawn on a slightly flaring cone behind each nozzle. A narrow white-hot core
// with standing shock diamonds (bright knots at fixed spacing, which don't move with the flow) inside a
// faint, translucent outer plume that fades out along its length. `power` scales it with throttle.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(0.5, 0.68, 1.0, 1.0);  // the outer plume
uniform vec4 core : source_color = vec4(0.93, 0.96, 1.0, 1.0);
uniform float power = 1.0;
uniform float diamonds = 4.0;  // how many shock diamonds along the plume

varying float along;  // 0 at the nozzle, 1 at the far tip

void vertex() {
	along = VERTEX.y + 0.5;  // the mesh is turned so +Y points away behind the ship
}

void fragment() {
	float f = abs(dot(normalize(NORMAL), normalize(VIEW)));  // 1 looking through the middle of the cone
	float a = clamp(along, 0.0, 1.0);
	float outer = pow(f, 2.0) * pow(1.0 - a, 1.6) * 0.14;
	float core_mask = pow(f, 14.0) * smoothstep(0.65, 0.0, a);
	float knots = pow(0.5 + 0.5 * cos(a * diamonds * 6.2831853), 6.0) * smoothstep(0.75, 0.05, a);
	float flick = 0.93 + 0.07 * sin(TIME * 53.0 + a * 17.0) * sin(TIME * 37.0);
	float c = core_mask * (0.45 + 1.0 * knots);
	ALBEDO = mix(color.rgb, core.rgb, clamp(c * 1.6, 0.0, 1.0)) * (0.9 + 1.6 * c);
	ALPHA = clamp((outer + c * 0.85) * power * flick, 0.0, 1.0);
}
