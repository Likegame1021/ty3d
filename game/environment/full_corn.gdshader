shader_type spatial;
render_mode cull_disabled;

uniform vec4 base_color : source_color = vec4(0.25, 0.42, 0.08, 1.0);
uniform vec3 player_position = vec3(1000.0);
uniform vec3 source_a = vec3(1000.0);
uniform vec3 source_b = vec3(1000.0);
uniform vec3 source_c = vec3(1000.0);
uniform vec3 source_d = vec3(1000.0);
uniform float night = 0.0;
uniform float weather_mode = 0.0;
uniform float animation_time = 0.0;
varying float shade;

vec2 disturbance(vec2 p, vec2 source, float strength, float spread) {
    vec2 offset = p - source;
    float distance_value = length(offset);
    return offset / max(distance_value, 0.15) * exp(-distance_value * distance_value * spread) * strength;
}

void vertex() {
    vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    float tip = pow(clamp(VERTEX.y / 2.3, 0.0, 1.0), 1.6);
    float phase = animation_time * (1.55 + weather_mode * 0.25) + world.x * 0.47 + world.z * 0.63 + INSTANCE_CUSTOM.x * 6.28;
    vec2 bend = vec2(sin(phase) * 0.075, cos(phase * 0.79) * 0.045) * (1.0 + weather_mode * 0.34);
    bend += disturbance(world.xz, player_position.xz, 0.52, 0.88);
    bend += disturbance(world.xz, source_a.xz, 0.12 + sin(animation_time * 9.0) * 0.035, 1.55);
    bend += disturbance(world.xz, source_b.xz, 0.34 + sin(animation_time * 6.0) * 0.08, 0.82);
    bend += disturbance(world.xz, source_c.xz, 0.65 + sin(animation_time * 5.0) * 0.14, 0.25);
    bend += disturbance(world.xz, source_d.xz, 0.28 + sin(animation_time * 7.0) * 0.06, 0.95);
    VERTEX += inverse(mat3(MODEL_MATRIX)) * vec3(bend.x, 0.0, bend.y) * tip;
    float player_distance = length(world.xz - player_position.xz);
    VERTEX.y *= 1.0 - exp(-player_distance * player_distance * 1.8) * 0.55;
    shade = 0.88 + INSTANCE_CUSTOM.y * 0.20;
}

void fragment() {
    vec3 color = base_color.rgb * shade;
    color = mix(color, vec3(0.68, 0.76, 0.62), clamp(weather_mode - 1.0, 0.0, 1.0) * 0.34);
    ALBEDO = color;
    ROUGHNESS = mix(0.89, 0.53, clamp(weather_mode, 0.0, 1.0));
    EMISSION = color * night * 0.025;
}
