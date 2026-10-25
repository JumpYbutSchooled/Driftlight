shader_type spatial;
// Planetary rings on a flat quad (UV 0..1 across the outer diameter): many fine bands of dust and ice
// with darker gaps, transparent inside and outside the ring. Lit by the sun from either side.
render_mode cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://shaders/noise.gdshaderinc"

uniform vec4 c1 : source_color = vec4(0.7, 0.6, 0.5, 1.0);
uniform vec4 c2 : source_color = vec4(0.9, 0.85, 0.8, 1.0);
uniform float seed = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float fine = noise3(vec3(r * 140.0, seed, 0.0));
	float broad = noise3(vec3(r * 18.0, seed * 1.7, 3.0));
	float gaps = smoothstep(0.2, 0.45, noise3(vec3(r * 9.0, seed * 0.6, 9.0)));
	float band = fine * 0.5 + broad * 0.5;
	float a = smoothstep(0.5, 0.55, r) * smoothstep(1.0, 0.9, r) * (0.25 + 0.75 * band) * gaps;
	vec3 col = mix(c1.rgb, c2.rgb, band);
	ALBEDO = mix(vec3(dot(col, vec3(0.3, 0.59, 0.11))), col, 0.5) * 0.45;
	ROUGHNESS = 1.0;
	ALPHA = clamp(a * 0.85, 0.0, 1.0);
}