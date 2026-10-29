shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_back, fog_disabled;
uniform vec4 rim_color : source_color = vec4(1.0, 0.95, 0.76, 0.60);
void fragment() {
 float edge = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
 ALBEDO = rim_color.rgb;
 ALPHA = smoothstep(0.48, 0.88, edge) * rim_color.a;
}
