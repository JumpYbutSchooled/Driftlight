shader_type spatial;
// The ship's shield bubble: invisible until hit. A hit lights up a fresnel rim with a hex shimmer, a hot
// spot where the bolt struck and a ripple that runs out across the bubble from there.
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
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	vec3 d = normalize(dir);
	vec2 sph = vec2(atan(d.z, d.x) * 6.0, d.y * 9.0);
	float cells = smoothstep(0.0, 0.12, hex(sph));
	float shimmer = 0.6 + 0.4 * sin(TIME * 12.0 + d.y * 40.0);
	float ang = acos(clamp(dot(d, normalize(hit_dir)), -1.0, 1.0));
	float ripple = exp(-pow((ang - hit_age * 3.2) * 5.0, 2.0)) * exp(-hit_age * 2.2);
	float spot = exp(-ang * 3.5) * exp(-hit_age * 5.0);
	float a = hit * f * 0.16 * shimmer + (ripple * 0.55 + spot * 1.2) * (0.3 + 0.7 * (1.0 - cells));
	ALBEDO = mix(color, vec3(1.0), spot * 0.5) * 2.0;
	ALPHA = clamp(a, 0.0, 1.0);
}