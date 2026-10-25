shader_type spatial;
// The ship's shield: invisible until hit. Each hit flares where the bolt struck and sends a faint ripple out
// across the field from there; the rest of the bubble only shows as a whisper at its rim while it's being
// hammered. A fine hex lattice shows through in the flare, not across the whole bubble.
render_mode unshaded, blend_add, depth_draw_never, cull_back;

uniform vec3 color : source_color = vec3(0.4, 0.85, 1.0);
uniform float hit = 0.0;
uniform vec3 hit_dir = vec3(0.0, 0.0, -1.0);  // where the last hit landed, as a direction from the centre
uniform float hit_age = 10.0;  // seconds since then

varying vec3 dir;

void vertex() {
	dir = normalize(VERTEX);
}

float hex(vec2 p) {
	p.x *= 1.1547;
	p.y += mod(floor(p.x), 2.0) * 0.5;
	p = abs(fract(p) - 0.5);
	return abs(max(p.x * 1.5 + p.y, p.y * 2.0) - 1.0);
}

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 d = normalize(dir);
	vec2 sph = vec2(atan(d.z, d.x) * 9.0, d.y * 13.0);
	float cells = 1.0 - smoothstep(0.0, 0.1, hex(sph));
	float ang = acos(clamp(dot(d, normalize(hit_dir)), -1.0, 1.0));
	float ripple = exp(-pow((ang - hit_age * 3.0) * 9.0, 2.0)) * exp(-hit_age * 4.5);
	float spot = exp(-ang * 5.0) * exp(-hit_age * 7.0);
	float a = hit * rim * 0.025 + ripple * 0.08 + spot * (0.4 + 0.7 * cells);
	ALBEDO = mix(color, vec3(1.0), spot * 0.6) * 1.6;
	ALPHA = clamp(a, 0.0, 1.0);
}
