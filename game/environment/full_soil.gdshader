shader_type spatial;
render_mode cull_disabled;

uniform float weather_mode = 0.0;
uniform float night = 0.0;
uniform float animation_time = 0.0;
varying vec3 field_world_position;

void vertex() {
    field_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float segment_distance(vec2 p, vec2 a, vec2 b) {
    vec2 v = b - a;
    return length(p - (a + v * clamp(dot(p - a, v) / dot(v, v), 0.0, 1.0)));
}

float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float soft_noise(vec2 p) {
    vec2 cell = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(cell), hash21(cell + vec2(1.0, 0.0)), f.x),
               mix(hash21(cell + vec2(0.0, 1.0)), hash21(cell + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
    vec2 p = field_world_position.xz;
    float road = segment_distance(p, vec2(0.0, 42.0), vec2(0.0, -29.0));
    road = min(road, segment_distance(p, vec2(0.0, 39.0), vec2(-3.5, 36.0)));
    road = min(road, segment_distance(p, vec2(-3.5, 36.0), vec2(-5.0, 31.0)));
    road = min(road, segment_distance(p, vec2(0.0, 23.0), vec2(5.0, 19.0)));
    road = min(road, segment_distance(p, vec2(0.0, 7.0), vec2(-7.0, 9.0)));
    road = min(road, segment_distance(p, vec2(0.0, -5.0), vec2(16.0, -15.0)));
    road = min(road, segment_distance(p, vec2(16.0, -15.0), vec2(0.0, -27.0)));
    float arena = length(p - vec2(0.0, -34.0));
    float lane = 1.0 - smoothstep(1.45, 2.45, road);
    lane = max(lane, 1.0 - smoothstep(8.0, 9.1, arena));
    float fleck = soft_noise(p * 0.72) * 0.62 + soft_noise(p * 2.4) * 0.38;
    float grain = (soft_noise(p * 10.0) - 0.5) * 0.048;
    vec3 earth = mix(vec3(0.36, 0.35, 0.22), vec3(0.28, 0.36, 0.21), fleck);
    vec3 path = mix(vec3(0.55, 0.39, 0.23), vec3(0.62, 0.46, 0.28), fleck);
    vec3 color = mix(earth, path, lane) + grain;
    float puddle = smoothstep(0.59, 0.72, soft_noise(p * 0.7)) * (1.0 - lane * 0.33);
    float wet = clamp(weather_mode, 0.0, 1.0);
    float ring = sin(length(fract(p * 0.42) - 0.5) * 29.0 - animation_time * 7.0) * 0.5 + 0.5;
    color = mix(color, mix(color * 0.56, vec3(0.20, 0.29, 0.29) + ring * 0.055, puddle * 0.70), wet);
    float snow = clamp(weather_mode - 1.0, 0.0, 1.0);
    float snow_cover = mix(0.78, 0.52, lane);
    color = mix(color, vec3(0.65, 0.72, 0.76) + fleck * 0.065, snow * snow_cover);
    ALBEDO = color * (1.0 - night * 0.08);
    ROUGHNESS = mix(0.94, 0.45, wet * puddle);
}
