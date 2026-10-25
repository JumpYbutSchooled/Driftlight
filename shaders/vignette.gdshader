shader_type canvas_item;
// Soft screen-edge vignette. `damage` washes the edges red when you're hit, `glow` tints them (used while
// the warp drive charges).

uniform float strength : hint_range(0.0, 1.0) = 0.55;
uniform float damage : hint_range(0.0, 1.0) = 0.0;
uniform vec4 glow : source_color = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec2 res = vec2(1920.0, 1080.0);

void fragment() {
	vec2 uv = (UV - 0.5) * vec2(res.x / res.y, 1.0);
	float v = smoothstep(0.45, 1.15, length(uv));
	float a = clamp(v * strength, 0.0, 1.0);
	vec3 c = mix(vec3(0.0), vec3(0.6, 0.03, 0.02), damage);
	c = mix(c, glow.rgb, glow.a * v);
	a = clamp(a + (damage * 0.6 + glow.a * 0.5) * v, 0.0, 1.0);
	COLOR = vec4(c, a);
}