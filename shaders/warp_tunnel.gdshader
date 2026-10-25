shader_type canvas_item;
// Full-screen speed lines on top of the 3D warp tunnel: you fly into the screen, so thin lanes of light
// rush outward from the centre past the edges. No rings. `intensity` 0 = off, 1 = full.

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(0.3, 0.6, 1.0, 1.0);
uniform vec2 res = vec2(1920.0, 1080.0);

float hash(float n) {
	return fract(sin(n * 91.345) * 47453.5453);
}

void fragment() {
	vec2 uv = (UV - 0.5) * vec2(res.x / res.y, 1.0);
	float r = length(uv);
	float a = atan(uv.y, uv.x);
	float f = (a + 3.14159) / 6.28318 * 420.0;
	float lane = floor(f);
	float h = hash(lane);
	float across = abs(fract(f) - 0.5) * 2.0;  // 0 down the middle of the lane
	float speed = 0.8 + h * 1.6;
	float z = fract(h * 13.0 + TIME * speed - log(r + 0.002) * 0.9);
	float streak = smoothstep(0.8, 1.0, z) * step(0.55, h) * smoothstep(0.1, 0.55, r) * (1.0 - smoothstep(0.2, 0.9, across));
	vec3 col = mix(tint.rgb, vec3(1.0), z * 0.75);
	COLOR = vec4(col, clamp(streak * intensity, 0.0, 1.0));
}
