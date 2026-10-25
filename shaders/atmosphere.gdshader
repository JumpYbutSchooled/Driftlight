shader_type spatial;
// A thin haze round a planet's limb: a slightly bigger sphere that only shows at grazing angles, and
// only on the side the sun lights (with a faint fringe round onto the night side). Not fogged.
render_mode unshaded, blend_add, depth_draw_never, cull_back, fog_disabled;

uniform vec3 color : source_color = vec3(0.5, 0.7, 1.0);
uniform float strength = 0.45;
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);  // towards the sun, world space

void fragment() {
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 wn = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	float lit = smoothstep(-0.25, 0.5, dot(normalize(wn), normalize(sun_dir)));
	ALBEDO = color * strength * f * lit;
	ALPHA = f * lit;
}