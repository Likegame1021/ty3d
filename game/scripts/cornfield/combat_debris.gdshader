shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

// UV/UV2 hold one constant launch velocity per piece. Every burst is one
// cached mesh and one draw; the shader never participates in combat physics.
uniform float age = 0.0;
uniform float life = 0.3;
uniform float strength = 1.0;
uniform float flash_life = 0.14;
uniform float flash_scale = 1.0;
uniform float ground_y = -0.25;
uniform vec4 tint : source_color = vec4(1.0);
varying float piece_kind;

void vertex() {
	piece_kind = UV.y;
	if (piece_kind >= 0.0) {
		vec3 velocity = vec3(UV2.x, UV.x, UV2.y) * strength;
		float gravity = piece_kind > 1.5 ? 0.18 : 2.4;
		VERTEX += velocity * age + vec3(0.0, -gravity * age * age, 0.0);
		VERTEX.y = max(VERTEX.y, ground_y);
	} else {
		// Billboard only the small contact mark in WORLD units. No pixel-size
		// compensation, depth bypass, light, or screen-space overlay is used.
		vec2 mark_xy = VERTEX.xy * flash_scale * (1.0 + age * 1.2);
		mat3 local_from_world = inverse(mat3(MODEL_MATRIX));
		VERTEX = local_from_world * (INV_VIEW_MATRIX[0].xyz * mark_xy.x + INV_VIEW_MATRIX[1].xyz * mark_xy.y);
	}
}

void fragment() {
	float fraction = clamp(age / max(life, 0.01), 0.0, 1.0);
	float fade = (1.0 - fraction) * (1.0 - fraction);
	if (piece_kind < 0.0) {
		fade = clamp((flash_life - age) / max(flash_life - 0.04, 0.01), 0.0, 1.0);
	}
	// Species tint belongs to the flecks, not the cream/brown contact mark.
	ALBEDO = COLOR.rgb * (piece_kind < 0.0 ? vec3(1.0) : tint.rgb);
	ALPHA = COLOR.a * tint.a * fade;
}
