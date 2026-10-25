shader_type canvas_item;
// The camera's own look, over the whole screen: a soft vignette, a fine moving film grain, and a faint
// colour fringe toward the corners like a real lens. `damage` washes the edges red when you're hit,
// `glow` tints them (used while the warp drive charges).

uniform float strength : hint_range(0.0, 1.0) = 0.55;
uniform float damage : hint_range(0.0, 1.0) = 0.0;
uniform vec4 glow : source_color = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec2 res = vec2(1920.0, 1080.0);
uniform float grain = 0.0;  // film grain (off: it read as pixelation)
uniform float fringe = 0.0016;
uniform sampler2D screen : hint_screen_texture, filter_linear;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = (UV - 0.5) * vec2(res.x / res.y, 1.0);
	float r = length(uv);
	float v = smoothstep(0.45, 1.15, r);
	// lens fringe: red and blue pulled very slightly apart toward the corners
	vec2 off = (SCREEN_UV - 0.5) * fringe * r * 2.0;
	vec3 scene = vec3(texture(screen, SCREEN_UV + off).r, texture(screen, SCREEN_UV).g, texture(screen, SCREEN_UV - off).b);
	if (grain > 0.0) {
		float n = hash(floor(SCREEN_UV * res) + floor(TIME * 24.0) * 7.31) - 0.5;
		scene += n * grain * (0.35 + 0.65 * dot(scene, vec3(0.33)));
	}
	vec3 tint = mix(vec3(0.0), vec3(0.6, 0.03, 0.02), damage);
	tint = mix(tint, glow.rgb, glow.a * v);
	float a = clamp(v * strength + (damage * 0.6 + glow.a * 0.5) * v, 0.0, 1.0);
	COLOR = vec4(mix(scene, tint, a), 1.0);
}
