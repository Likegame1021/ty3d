shader_type spatial;
render_mode cull_disabled;
uniform vec4 base_color : source_color = vec4(0.25, 0.42, 0.06, 1.0);
uniform vec3 player_position = vec3(1000.0);
uniform vec3 disturbance_position = vec3(1000.0);
uniform float night = 0.0;
uniform float animation_time = 0.0;
varying float shade;
void vertex() {
 vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
 float height_weight = pow(clamp(VERTEX.y / 2.3, 0.0, 1.0), 1.7);
 float phase = animation_time * 1.75 + world.x * 0.47 + world.z * 0.63 + INSTANCE_CUSTOM.x * 6.28;
 vec2 push = world.xz - player_position.xz;
 float d = length(push);
 vec2 animal_push = world.xz - disturbance_position.xz;
 float ad = length(animal_push);
 vec2 bend = vec2(sin(phase) * 0.09, cos(phase * 0.79) * 0.055);
 bend += push / max(d, 0.15) * exp(-d*d*1.25) * 0.48;
 bend += animal_push / max(ad, 0.15) * exp(-ad*ad*1.4) * (0.35 + sin(animation_time*9.0) * 0.10);
 // Convert the world-space disturbance back into each rotated instance's local axes.
 VERTEX += inverse(mat3(MODEL_MATRIX)) * vec3(bend.x, 0.0, bend.y) * height_weight;
 shade = 0.88 + INSTANCE_CUSTOM.y * 0.22;
}
void fragment() {
 ALBEDO = base_color.rgb * shade;
 ROUGHNESS = 0.88;
 EMISSION = base_color.rgb * night * 0.065;
}

