shader_type spatial;
// Engine exhaust plume: a soft cone of light behind each nozzle, hottest and whitest at the core near the
// nozzle, fading out along its length. `power` scales brightness with throttle; it shimmers slightly.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.6, 0.25, 1.0);
uniform vec4 core : source_color = vec4(1.0, 0.95, 0.85, 1.0);
uniform float power = 1.0;

varying float along;  // 0 at the nozzle, 1 at the far tip

void vertex() {
	along = VERTEX.y + 0.5;  // the mesh is turned so +Y points away behind the ship
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float fall = pow(clamp(1.0 - along, 0.0, 1.0), 1.7);
	float flick = 0.85 + 0.15 * sin(TIME * 47.0 + along * 23.0) * sin(TIME * 31.0);
	float hot = pow(facing, 4.0) * (1.0 - along);
	ALBEDO = mix(color.rgb, core.rgb, hot) * (1.5 + hot * 2.0);
	ALPHA = clamp(fall * pow(facing, 1.3) * flick * power, 0.0, 1.0);
}