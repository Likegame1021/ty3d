shader_type spatial;
render_mode cull_disabled, depth_draw_never;

uniform float mouth_cleared = 0.0;
uniform float flowing = 0.0;
uniform float weather_mode = 0.0;
uniform float night = 0.0;
uniform float animation_time = 0.0;
varying vec3 wet_world_position;

void vertex() {
    wet_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    vec2 p = wet_world_position.xz;
    float banks = smoothstep(0.0, 0.27, UV.x) * smoothstep(0.0, 0.27, UV.y);
    banks *= smoothstep(0.0, 0.27, 1.0 - UV.x) * smoothstep(0.0, 0.27, 1.0 - UV.y);
    float irregular = sin(p.x * 2.8 + p.y * 1.9) * 0.12 + sin(p.x * 6.3 - p.y * 3.1) * 0.05;
    float pooled = smoothstep(0.15, 0.58, banks + irregular);
    float ripple = sin(length(fract(p * 0.46) - 0.5) * 26.0 - animation_time * (3.0 + flowing * 4.0)) * 0.045;
    vec3 damp_soil = vec3(0.25, 0.29, 0.20);
    vec3 water = vec3(0.16, 0.30, 0.32) + ripple;
    ALBEDO = mix(damp_soil, water, (mouth_cleared * 0.50 + flowing * 0.38) * pooled);
    ALBEDO = mix(ALBEDO, vec3(0.61, 0.67, 0.67), clamp(weather_mode - 1.0, 0.0, 1.0) * 0.35);
    ALBEDO *= 1.0 - night * 0.12;
    ROUGHNESS = mix(0.88, 0.38, flowing * pooled);
    ALPHA = banks * (0.46 + mouth_cleared * 0.20);
}
