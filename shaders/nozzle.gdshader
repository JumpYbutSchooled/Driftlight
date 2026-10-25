shader_type spatial;
// The glowing throat of an engine nozzle: a flat disc just inside the bell, seen only from behind. White-hot
// in the middle, cooling through the exhaust colour to the dull red of heated metal at the rim. `power`
// follows the throttle; it never quite goes out (the metal stays hot).
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

uniform vec4 color : source_color = vec4(0.5, 0.68, 1.0, 1.0);
uniform float power = 1.0;

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float hot = exp(-r * r * 5.0);
	float rim = smoothstep(1.0, 0.8, r);
	vec3 metal = vec3(0.9, 0.3, 0.08);
	vec3 c = mix(metal, color.rgb, smoothstep(0.95, 0.4, r));
	c = mix(c, vec3(1.0, 0.98, 0.95), hot * power);
	ALBEDO = c * (0.45 + 1.1 * hot * power);
	ALPHA = clamp(rim * (0.2 + 0.6 * hot) * (0.15 + 0.6 * power), 0.0, 1.0);
}
