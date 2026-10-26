// Shared by hull.gdshader (one-sided) and hull_2s.gdshader (two-sided, for open tubes like engine bells):
// surface detail for the Blender ship, station and prop models, on top of each material's own colour -
// a staggered grid of armour sub-panels with real relief (a height field, lit by bump-mapping): bevelled
// grooves between the plates, some plates sitting proud and some recessed, rivets at their corners and a fine
// grain over the metal; grime that settles in the grooves and in patches, streaks, worn bright edges and tiny
// scratches that catch the light. Habitat surfaces (windows > 0) also get decks of lit windows on their walls,
// some decks dark, a few windows cool white instead of warm. Worked out from object-space position
// (triplanar), so it needs no textures or UVs.
#include "res://shaders/noise.gdshaderinc"

uniform vec4 albedo : source_color = vec4(0.6, 0.62, 0.68, 1.0);
uniform float metallic = 0.4;
uniform float roughness = 0.5;
uniform float panel = 2.2;  // sub-panels per metre
uniform float grime = 1.0;
uniform float relief = 1.0;  // how deep the panel relief reads
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
	// sub-panels: a staggered grid of plates
	vec2 p = uv * panel;
	p.x += step(1.0, mod(floor(p.y), 2.0)) * 0.5;
	vec2 cell = floor(p);
	vec2 fp = fract(p);
	vec2 f = abs(fp - 0.5);
	float aa = fwidth(p.x) + fwidth(p.y);
	float line = smoothstep(0.5 - aa * 1.5, 0.5, max(f.x, f.y));
	float tint = hash2(cell) - 0.5;
	// the relief, in panel widths: plates bevelled down into the grooves between them, some proud, some
	// recessed, rivets near the corners, and a fine grain - faded out where it would only shimmer
	vec2 e2 = min(fp, 1.0 - fp);
	float edge = min(e2.x, e2.y);
	float bevel = smoothstep(0.0, 0.07, edge);
	float raise = (hash2(cell + 5.3) - 0.5) * 0.6;
	float rivet_d = length(min(fp, 1.0 - fp) - vec2(0.075));
	float rivet = (1.0 - smoothstep(0.012, 0.026, rivet_d)) * step(0.45, hash2(cell + 9.1));
	float detail = 1.0 - smoothstep(0.08, 0.35, aa);  // grooves and rivets only where they're bigger than a pixel
	float grain = noise3(opos * panel * 9.0) - 0.5;
	float h = (bevel * (1.0 + raise) + rivet * 0.35) * detail + grain * 0.04 * (1.0 - smoothstep(0.02, 0.1, aa));
	// grime patches, vertical streaks and fine scratches; grime settles in the grooves too
	float g = fbm3(opos * 0.35 + vec3(3.1, 1.7, 5.3));
	float streak = noise3(vec3(uv.x * 9.0, uv.y * 0.6, 0.0) + opos * 0.05);
	float cavity = (1.0 - bevel) * detail;
	float dirt = clamp(smoothstep(0.45, 0.85, g) * 0.8 + smoothstep(0.6, 0.95, streak) * 0.25 + cavity * 0.35, 0.0, 1.0) * grime;
	float scratch = step(0.93, noise3(vec3(uv * vec2(40.0, 3.0), 2.0))) * (1.0 - dirt);
	// the raised edge of each plate is worn bright where things have brushed it
	float wear = smoothstep(0.07, 0.03, edge) * step(0.07 * 0.4, edge) * smoothstep(0.55, 0.8, noise3(opos * panel * 3.0)) * detail;
	vec3 col = albedo.rgb * (1.0 + tint * 0.08 + raise * 0.06);
	col *= 1.0 - line * 0.14;
	col *= 1.0 - dirt * 0.3;
	col = mix(col, col * 1.4 + 0.05, scratch * 0.5);
	col = mix(col, col * 1.25 + 0.04, wear * 0.6);
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
		glow = wcol * lit * shape * 1.8;
		col *= 1.0 - shape * 0.7 * (1.0 - far);
		h *= 1.0 - shape;
	}
	// bump-map the relief (screen-space derivatives, so it works on any mesh without tangents). The height is in
	// panel widths: turn it into view-space metres, allowing for the model being shown scaled up
	float model_scale = length(MODEL_MATRIX[0].xyz);
	float hm = h * relief * 0.035 / panel * model_scale;
	vec3 dpx = dFdx(VERTEX);
	vec3 dpy = dFdy(VERTEX);
	vec3 r1 = cross(dpy, NORMAL);
	vec3 r2 = cross(NORMAL, dpx);
	float det = dot(dpx, r1);
	vec3 grad = sign(det) * (dFdx(hm) * r1 + dFdy(hm) * r2);
	NORMAL = normalize(abs(det) * NORMAL - grad);
	ALBEDO = col;
	EMISSION = glow;
	METALLIC = clamp(metallic + scratch * 0.3 + wear * 0.3 - dirt * 0.2, 0.0, 1.0);
	ROUGHNESS = clamp(roughness + tint * 0.15 + line * 0.25 + dirt * 0.25 - scratch * 0.3 - wear * 0.25, 0.05, 1.0);
	SPECULAR = 0.5;
	AO = 1.0 - cavity * 0.55;
	AO_LIGHT_AFFECT = 0.35;
}
