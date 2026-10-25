shader_type spatial;
// Surface detail for the Blender ship, station and prop models, on top of each material's own colour:
// a fine grid of sub-panel lines, a slight tint per panel, grime that collects in patches, streaks and
// tiny scratches that catch the light. Habitat surfaces (windows > 0) also get decks of lit windows on
// their walls, some decks dark, a few windows cool white instead of warm. Worked out from object-space
// position (triplanar), so it needs no textures or UVs. Double-sided because engine bells are open tubes.
render_mode cull_disabled;

#include "res://shaders/noise.gdshaderinc"

uniform vec4 albedo : source_color = vec4(0.6, 0.62, 0.68, 1.0);
uniform float metallic = 0.4;
uniform float roughness = 0.5;
uniform float panel = 2.2;  // sub-panels per metre
uniform float grime = 1.0;
uniform float windows = 0.0;  // 0 = none, 1 = most windows lit
uniform vec2 window_cell = vec2(2.6, 3.8);  // metres between windows (along the wall, up)

varying vec3 opos;
varying vec3 onrm;

void vertex() {
	opos = VERTEX;
	onrm = NORMAL;
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec3 an = abs(onrm);
	vec2 uv = an.x > an.y && an.x > an.z ? opos.yz : (an.y > an.z ? opos.xz : opos.xy);
	// sub-panels: a staggered grid of plates with thin dark lines between them
	vec2 p = uv * panel;
	p.x += step(1.0, mod(floor(p.y), 2.0)) * 0.5;
	vec2 cell = floor(p);
	vec2 f = abs(fract(p) - 0.5);
	float aa = fwidth(p.x) + fwidth(p.y);
	float line = smoothstep(0.5 - aa * 1.5, 0.5, max(f.x, f.y));
	float tint = hash2(cell) - 0.5;
	// grime patches, vertical streaks and fine scratches
	float g = fbm3(opos * 0.35 + vec3(3.1, 1.7, 5.3));
	float streak = noise3(vec3(uv.x * 9.0, uv.y * 0.6, 0.0) + opos * 0.05);
	float dirt = clamp(smoothstep(0.45, 0.85, g) * 0.8 + smoothstep(0.6, 0.95, streak) * 0.25, 0.0, 1.0) * grime;
	float scratch = step(0.93, noise3(vec3(uv * vec2(40.0, 3.0), 2.0))) * (1.0 - dirt);
	vec3 col = albedo.rgb * (1.0 + tint * 0.12);
	col *= 1.0 - line * 0.3;
	col *= 1.0 - dirt * 0.4;
	col = mix(col, col * 1.4 + 0.05, scratch * 0.5);
	vec3 glow = vec3(0.0);
	if (windows > 0.0 && an.y < 0.45) {
		vec2 wuv = vec2(an.x > an.z ? opos.z : opos.x, opos.y) / window_cell;
		vec2 wc = floor(wuv);
		vec2 wf = fract(wuv);
		float deck = step(0.3, hash2(vec2(wc.y, 7.0)));
		float run = step(0.35, hash2(vec2(floor(wc.x / 6.0), wc.y + 31.0)));
		float lit = step(1.0 - windows * 0.8, hash2(wc + 3.0)) * deck * run;
		float rect = step(0.18, wf.x) * step(wf.x, 0.82) * step(0.3, wf.y) * step(wf.y, 0.72);
		// far away a window is smaller than a pixel: fade to its average glow instead of shimmering
		float far = smoothstep(0.25, 0.8, max(fwidth(wuv.x), fwidth(wuv.y)));
		float shape = mix(rect, 0.28, far);
		vec3 wcol = mix(vec3(1.0, 0.8, 0.5), vec3(0.62, 0.88, 1.0), step(0.78, hash2(wc + 11.0)));
		glow = wcol * lit * shape * 2.6;
		col *= 1.0 - shape * 0.7 * (1.0 - far);
	}
	ALBEDO = col;
	EMISSION = glow;
	METALLIC = clamp(metallic + scratch * 0.3 - dirt * 0.2, 0.0, 1.0);
	ROUGHNESS = clamp(roughness + tint * 0.15 + line * 0.25 + dirt * 0.25 - scratch * 0.3, 0.05, 1.0);
	SPECULAR = 0.5;
}
