shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform float animation_time = 0.0;
uniform float snow = 0.0;
uniform float night = 0.0;

void vertex() {
    float phase = INSTANCE_CUSTOM.x;
    float speed = mix(12.0, 2.1, snow);
    float fall = mod(animation_time * speed + phase * 8.0, 8.0);
    VERTEX.y -= fall;
    VERTEX.x += sin(animation_time * 1.5 + phase * 19.0) * snow * 0.35;
}

void fragment() {
    ALBEDO = mix(vec3(0.65, 0.78, 0.84), vec3(0.96, 0.97, 0.95), snow) * (1.0 - night * 0.10);
    ALPHA = mix(0.30, 0.83, snow);
}
