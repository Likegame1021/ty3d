shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;

varying float upward;
varying vec3 world_pos;

void vertex() {
	upward = (MODEL_NORMAL_MATRIX * NORMAL).y;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float speckle = sin(world_pos.x * 16.0) * sin(world_pos.z * 19.0);
	ALBEDO = vec3(0.76, 0.81, 0.82);
	ALPHA = smoothstep(0.40, 0.83, upward) * (0.46 + 0.08 * speckle);
	ROUGHNESS = 0.96;
}
