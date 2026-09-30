shader_type spatial;
uniform vec4 dirt_color : source_color = vec4(0.47, 0.34, 0.19, 1.0);
varying vec3 world_position;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void vertex() { world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
 vec2 p = world_position.xz;
 float fleck = hash(floor(p * 45.0));
 float large = sin(p.x * 2.1 + sin(p.y * 1.3)) * sin(p.y * 2.8) * 0.04;
 float path = 1.0 - smoothstep(1.05, 2.1, abs(p.x + sin(p.y * 0.38) * 0.18));
 vec3 earth = dirt_color.rgb * (0.88 + fleck * 0.16 + large);
 vec3 field = vec3(0.25, 0.29, 0.105) * (0.86 + fleck * 0.20);
 ALBEDO = mix(field, earth + vec3(0.055, 0.035, 0.005), path);
 ROUGHNESS = 1.0;
}
