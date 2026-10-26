shader_type spatial;
// A mote of space dust drawn as a short streak along the path it has taken past the camera: each vertex of
// the strip (VERTEX.z 0 at the mote, 1 at the far end of its trail) is moved by `trail`, how far the camera
// travelled between now and that moment. So the streaks bend round with the ship when it turns instead of
// swinging about as stiff lines. VERTEX.x (-1..1) is across the strip, kept facing the camera and about a
// pixel wide however far off the mote is.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform, fog_disabled;

const int POINTS = 8;
uniform vec3 trail[8];  // world-space camera travel from each trail point's moment until now (trail[0] = 0)
uniform vec4 color : source_color = vec4(0.85, 0.8, 0.72, 0.22);
uniform float width = 0.0015;  // half-width, as a share of the distance to the camera

varying float along;

void vertex() {
	float f = clamp(VERTEX.z, 0.0, 1.0) * float(POINTS - 1);
	int k = min(int(floor(f)), POINTS - 2);
	float fr = f - float(k);
	vec3 off = mix(trail[k], trail[k + 1], fr);
	vec3 tangent = trail[k + 1] - trail[k];
	vec3 base = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 vpos = (VIEW_MATRIX * vec4(base + off, 1.0)).xyz;
	vec3 vt = (VIEW_MATRIX * vec4(tangent, 0.0)).xyz;
	vec3 side = cross(vt, vpos);
	side = length(side) > 1e-6 ? normalize(side) : vec3(1.0, 0.0, 0.0);
	vpos += side * VERTEX.x * max(0.02, -vpos.z * width);
	along = clamp(f / float(POINTS - 1), 0.0, 1.0);
	VERTEX = vpos;
}

void fragment() {
	// brightest at the mote, fading along its trail
	float a = color.a * (1.0 - along * 0.85);
	ALBEDO = color.rgb;
	ALPHA = a;
}
