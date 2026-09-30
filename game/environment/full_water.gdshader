shader_type spatial;
render_mode cull_disabled;

uniform float animation_time = 0.0;
uniform float weather_mode = 0.0;
uniform float night = 0.0;
uniform float flowing = 0.0;
varying vec3 canal_world_position;

void vertex() {
    canal_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    vec2 p = canal_world_position.xz;
    float wave = sin(p.x * 2.8 + animation_time * (1.1 + flowing * 1.4)) * 0.5;
    wave += sin(p.x * 5.2 - p.y * 2.3 - animation_time * 2.5) * 0.25;
    float rain_ring = sin(length(fract(p * 0.75) - 0.5) * 28.0 - animation_time * 9.0) * 0.06 * clamp(weather_mode, 0.0, 1.0);
    ALBEDO = mix(vec3(0.18, 0.39, 0.40), vec3(0.30, 0.49, 0.43), wave + 0.5) + rain_ring;
    ALBEDO = mix(ALBEDO, vec3(0.42, 0.49, 0.51), clamp(weather_mode - 1.0, 0.0, 1.0) * 0.32);
    ALBEDO *= 1.0 - night * 0.21;
    ROUGHNESS = 0.33;
    METALLIC = 0.02;
}
