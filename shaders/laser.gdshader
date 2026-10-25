shader_type spatial;
// A laser bolt, drawn on two crossed quads lying along it: a thin white-hot core inside a soft coloured
// glow. UV.x runs across the bolt and UV.y from the head (0) back to the tail (1), so it's brightest and
// sharpest at the head and fades away to nothing at the tail.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.35, 0.3, 1.0);
uniform float intensity = 1.0;

void fragment() {
	float x = abs(UV.x - 0.5) * 2.0;  // 0 down the middle, 1 at the edge
	float core = exp(-x * x * 70.0);
	float glow = exp(-x * x * 7.0) * (1.0 - x);
	float head = smoothstep(0.0, 0.035, UV.y);  // a softly rounded tip
	float fade = pow(1.0 - UV.y, 1.8);
	ALBEDO = color.rgb * glow * 1.5 + vec3(1.0, 0.97, 0.92) * core * 2.4;
	ALPHA = clamp((glow * 0.7 + core) * head * fade * intensity, 0.0, 1.0);
}
